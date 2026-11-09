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
    private static let sampleSpacing = 5.0

    private let projection: LocalMetres
    private(set) var town = AreaLayer()
    private(set) var green = AreaLayer()

    /// Builds the index from the closed ways and the multipolygon relations of an extract.
    init(extract: OSMExtract, classifier: FeatureClassifier) {
        projection = LocalMetres(around: extract.boundingBox)
        let areas = AreaPolygons.collect(extract: extract, classifier: classifier) { classification, tags in
            let isPlatform = tags.value(forKey: "railway") == "platform" || tags.value(forKey: "public_transport") == "platform"
            let role = Self.role(of: classification, tags, isPlatform: isPlatform)
            return role == .none ? nil : role
        }
        for area in areas { add(area.polygon, as: area.role) }
    }

    private enum Role { case none, town, green }

    private static func role(of classification: Classification, _ tags: any ClassifierTags, isPlatform: Bool) -> Role {
        if isPlatform { return .town }
        guard classification.kind == .area else { return .none }
        switch classification.featureClass {
        case .landuseUrban, .militaryArea, .roadArea: return .town
        case .landcover, .forest: return .green
        default:
            return tags.value(forKey: "amenity") == "parking" || tags.value(forKey: "place") == "square" ? .town : .none
        }
    }

    private mutating func add(_ polygon: AreaPolygon, as role: Role) {
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
}
