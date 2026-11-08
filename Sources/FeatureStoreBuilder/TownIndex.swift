import FeatureStore
import Foundation
import OSMPBF

/// The built-up and green areas of an extract, for asking whether a footway lies in a town rather than in a park.
///
/// Many footways in a city are not beside a road: they cross a plaza, a station, a yard or a car park. They are the pavement of
/// the town, not paths to run. A footway is taken to be one when most of its length lies in a built-up area (urban land use, a
/// pedestrian area, a platform, a car park, a square) and not in a green one (a park, a garden, a wood, open land).
///
/// The areas are the closed ways and the multipolygon relations of the extract, with their holes. Both matter: a park that
/// is mapped as a relation must count as green, or its paths would be taken for sidewalks because the closed way of the
/// housing around it is seen. A relation that is incomplete in the extract is not used.
struct TownIndex {
    /// The share of the footway's length that must lie in a town.
    static let minimumShare = 0.7
    /// A footway shorter than this, in metres, is not judged.
    static let minimumLength = 10.0
    /// Polygons whose bounding box covers more grid cells than this are kept in a short list that every query tests, instead
    /// of in the grid: a wood of 20 km would otherwise take tens of thousands of cells.
    static let largestGridded = 400
    private static let sampleSpacing = 5.0
    private static let cellSize = 100.0

    /// An area with its holes: rings in metres, filled by the even-odd rule.
    struct Polygon {
        var rings: [(xs: [Double], ys: [Double])]
        var minX: Double, maxX: Double, minY: Double, maxY: Double

        init?(rings projected: [[(x: Double, y: Double)]]) {
            let usable = projected.filter { $0.count >= 4 }
            guard !usable.isEmpty else { return nil }
            rings = usable.map { ring in (ring.map(\.x), ring.map(\.y)) }
            minX = usable.flatMap { $0.map(\.x) }.min() ?? 0
            maxX = usable.flatMap { $0.map(\.x) }.max() ?? 0
            minY = usable.flatMap { $0.map(\.y) }.min() ?? 0
            maxY = usable.flatMap { $0.map(\.y) }.max() ?? 0
        }

        /// Whether a point lies in the area: inside an odd number of its rings.
        func contains(x: Double, y: Double) -> Bool {
            guard x >= minX, x <= maxX, y >= minY, y <= maxY else { return false }
            var inside = false
            for ring in rings {
                var j = ring.xs.count - 1
                for i in 0..<ring.xs.count {
                    if (ring.ys[i] > y) != (ring.ys[j] > y),
                        x < (ring.xs[j] - ring.xs[i]) * (y - ring.ys[i]) / (ring.ys[j] - ring.ys[i]) + ring.xs[i]
                    {
                        inside.toggle()
                    }
                    j = i
                }
            }
            return inside
        }
    }

    /// A set of polygons with a grid for the small ones.
    struct Layer {
        private(set) var polygons: [Polygon] = []
        private var grid: [Int64: [Int]] = [:]
        private var large: [Int] = []

        mutating func add(_ polygon: Polygon) {
            let index = polygons.count
            polygons.append(polygon)
            let columns = TownIndex.cell(polygon.minX)...TownIndex.cell(polygon.maxX)
            let rows = TownIndex.cell(polygon.minY)...TownIndex.cell(polygon.maxY)
            if columns.count * rows.count > TownIndex.largestGridded {
                large.append(index)
                return
            }
            for column in columns {
                for row in rows { grid[TownIndex.key(column, row), default: []].append(index) }
            }
        }

        func contains(x: Double, y: Double) -> Bool {
            if (grid[TownIndex.key(TownIndex.cell(x), TownIndex.cell(y))] ?? []).contains(where: { polygons[$0].contains(x: x, y: y) }) {
                return true
            }
            return large.contains { polygons[$0].contains(x: x, y: y) }
        }
    }

    private let projection = LocalMetres()
    private(set) var town = Layer()
    private(set) var green = Layer()

    /// Builds the index from the closed ways and the multipolygon relations of an extract.
    init(extract: OSMExtract, classifier: FeatureClassifier) {
        for position in extract.ways.indices {
            let nodeIDs = extract.ways.nodeIDs(at: position)
            guard nodeIDs.count >= 4, nodeIDs.first == nodeIDs.last else { continue }
            let tags = extract.ways.tags(at: position)
            let classification = classifier.classify(tags, shape: .closedWay)
            let isPlatform = tags.value(forKey: "railway") == "platform" || tags.value(forKey: "public_transport") == "platform"
            let role = Self.role(of: classification, tags, isPlatform: isPlatform)
            guard role != .none else { continue }
            let (runs, gaps) = FeatureStoreBuilder.runs(ofWayAt: position, in: extract)
            guard gaps == 0, runs.count == 1, let polygon = polygon(from: [runs[0]]) else { continue }
            add(polygon, as: role)
        }
        for position in extract.relations.indices {
            let item = extract.relations[position]
            let relation = item.relation
            guard item.isComplete, relation.tagValue(forKey: "type") == "multipolygon" else { continue }
            let tags = ClassifierTagArray(relation.orderedTags)
            let classification = classifier.classify(tags, shape: .multipolygon)
            let role = Self.role(of: classification, tags, isPlatform: false)
            guard role != .none else { continue }
            var members: [MultipolygonMember] = []
            for member in relation.members where member.type == .way {
                let memberRole = MultipolygonRole(osmRole: member.role)
                guard memberRole != .ignored, let way = extract.ways.index(ofID: member.id) else { continue }
                let nodeIDs = Array(extract.ways.nodeIDs(at: way))
                let points = nodeIDs.compactMap {
                    extract.nodes.index(ofID: $0).map { FeatureStoreBuilder.packed(extract.nodes.coordinate(at: $0)) }
                }
                members.append(MultipolygonMember(
                    wayID: member.id, role: memberRole, nodeIDs: nodeIDs, points: points.count == nodeIDs.count ? points : nil))
            }
            let assembly = MultipolygonAssembler.assemble(members: members, relationIsComplete: item.isComplete)
            guard assembly.isComplete else { continue }
            for assembled in assembly.polygons {
                if let polygon = polygon(from: assembled.rings) { add(polygon, as: role) }
            }
        }
    }

    private enum Role { case none, town, green }

    private static func role(of classification: Classification, _ tags: some ClassifierTags, isPlatform: Bool) -> Role {
        if isPlatform { return .town }
        guard classification.kind == .area else { return .none }
        switch classification.featureClass {
        case .landuseUrban, .roadArea: return .town
        case .landcover, .forest: return .green
        default:
            return tags.value(forKey: "amenity") == "parking" || tags.value(forKey: "place") == "square" ? .town : .none
        }
    }

    private func polygon(from rings: [[PackedPoint]]) -> Polygon? {
        Polygon(rings: rings.map { $0.map { projection.project($0) } })
    }

    private mutating func add(_ polygon: Polygon, as role: Role) {
        switch role {
        case .town: town.add(polygon)
        case .green: green.add(polygon)
        case .none: break
        }
    }

    /// Whether most of a footway lies in a built-up area and not in a green one.
    ///
    /// - Parameter runs: The footway's points, one array per piece (a way with a gap has two).
    func isInTown(_ runs: [[PackedPoint]]) -> Bool {
        var total = 0.0, inside = 0.0
        for run in runs where run.count >= 2 {
            for index in 0..<(run.count - 1) {
                let a = projection.project(run[index]), b = projection.project(run[index + 1])
                let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
                guard length > 0 else { continue }
                let samples = max(1, Int((length / Self.sampleSpacing).rounded(.up)))
                let weight = length / Double(samples)
                for sample in 0..<samples {
                    let t = (Double(sample) + 0.5) / Double(samples)
                    let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
                    total += weight
                    if town.contains(x: x, y: y) && !green.contains(x: x, y: y) { inside += weight }
                }
            }
        }
        return total >= Self.minimumLength && inside >= Self.minimumShare * total
    }

    fileprivate static func cell(_ value: Double) -> Int { Int((value / cellSize).rounded(.down)) }
    fileprivate static func key(_ column: Int, _ row: Int) -> Int64 { (Int64(column) << 32) ^ (Int64(row) & 0xFFFF_FFFF) }
}
