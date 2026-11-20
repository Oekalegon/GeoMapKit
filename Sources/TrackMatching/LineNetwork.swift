import FeatureStore
import Foundation
import GeoCore

/// The roads and paths of a part of the map as a network: nodes where lines meet or bend, and edges between them.
///
/// The feature store keeps ways as lines clipped to cells, with no node identity. A network is made from them by taking every vertex of
/// a line as a node and every step from one vertex to the next as an edge. Two lines meet where they have a vertex at the same position
/// (OpenStreetMap ways share their nodes, and a line that crosses a cell border nearly always has the same vertex on the border in both
/// cells), so junctions and the joins between cells appear without any further information. It is the ground a track is matched to.
///
/// **Joins are exact, so a few are missing.** On the real map of Eidsvoll (186,103 nodes) about one cell border in a hundred leaves a
/// way as two pieces whose ends lie a metre apart. A matcher must therefore allow a short hop (a metre or two) between two dead ends
/// instead of taking the network as complete.
///
/// **Edges have no direction.** A one-way road is the same both ways, and the classes (see ``travelClasses``) include pavements, which
/// lie a few metres from the road they follow; a matcher for one sport narrows them. A box that crosses the antimeridian is refused.
///
/// The network is built for a map area on the phone or the Mac, not for the Watch: it holds every vertex of the area in memory.
/// Distances are in metres, on the sphere of ``Coordinate/earthRadius``.
public struct LineNetwork: Sendable {
    /// A step along one line, from one vertex to the next.
    public struct Edge: Sendable, Equatable {
        /// The index of the node at the start.
        public let from: Int
        /// The index of the node at the end.
        public let to: Int
        /// The length in metres.
        public let length: Double
        /// The OSM id of the way the step belongs to.
        public let wayID: Int64
        /// The feature class of the way (see ``FeatureClass``).
        public let classID: UInt8
        /// The distance along the whole way, in metres, from its first node to ``from``. It is made from the offset that the store keeps
        /// for each piece of a way, so it is the same whichever cells the network is made of, and it stays the same when the area changes.
        /// ``from`` to ``to`` follows the order of the nodes of the way.
        public let wayOffset: Double
    }

    /// The feature classes a runner or rider can use: paths, tracks, roads, service roads and pavements. A matcher for one sport takes
    /// the ones that sport uses (a rider has no use for pavements).
    public static let travelClasses: Set<UInt8> = [
        FeatureClass.path.rawValue, FeatureClass.track.rawValue, FeatureClass.roadMajor.rawValue, FeatureClass.roadMinor.rawValue,
        FeatureClass.roadService.rawValue, FeatureClass.pavement.rawValue,
    ]

    /// The most cells a network is made from at once.
    public static let maximumCells = 4_096

    /// The position of every node.
    public private(set) var coordinates: [Coordinate] = []
    /// Every edge.
    public private(set) var edges: [Edge] = []
    /// For each node, the indexes of the edges that start or end there.
    public private(set) var incident: [[Int]] = []

    private struct Vertex: Hashable {
        var longitude: Int32
        var latitude: Int32
    }

    private struct Bucket: Hashable {
        var x: Int
        var y: Int
    }

    private struct EdgeKey: Hashable {
        var low: Int
        var high: Int
        var way: Int64
    }

    /// The index: edges by the bucket of a grid that they touch.
    private var buckets: [Bucket: [Int]] = [:]
    private static let bucketSize = 0.0005
    private var longitudeScale = 1.0

    /// The edge that touches more buckets than this is put in the index by walking along it, and not by filling its box.
    private static let boxFillLimit = 1_024

    /// How many entries the index holds (for tests: a long edge must not fill its whole box).
    var indexEntryCount: Int { buckets.values.reduce(0) { $0 + $1.count } }

    /// Makes a network from the line features of one or more cells.
    ///
    /// Features that are not lines, and lines of other classes than `classes`, are left out. A step of no length is left out, and so is a
    /// step that is stored twice for the same way (a way that goes over the same step twice has the offset of the first time).
    ///
    /// - Parameters:
    ///   - features: The features, from any band (the detail band has the whole geometry).
    ///   - classes: The classes to keep; by default ``travelClasses``.
    public init(features: [StoredFeature], classes: Set<UInt8> = LineNetwork.travelClasses) {
        var builder = Builder(classes: classes)
        builder.add(features)
        self = builder.finish()
    }

    /// Makes a network from the cells of a map that cover a box.
    ///
    /// - Parameters:
    ///   - source: The map: a store file or a set of blocks. The detail band is read, one cell at a time.
    ///   - box: The area. The cells that meet it are read whole, so the network reaches a little beyond the box. A box that crosses the
    ///     antimeridian (west of east) is not valid.
    ///   - classes: The classes to keep; by default ``travelClasses``.
    /// - Throws: ``LineNetworkError`` for a box that is not valid or covers more than ``maximumCells`` cells; the errors of the source.
    public init(source: any CellSource, box: BoundingBox, classes: Set<UInt8> = LineNetwork.travelClasses) throws {
        guard box.isValid,
            let southWest = TileID.containing(Coordinate(latitude: box.south, longitude: box.west), zoom: source.storageZoom),
            let northEast = TileID.containing(Coordinate(latitude: box.north, longitude: box.east), zoom: source.storageZoom)
        else { throw LineNetworkError.invalidBox }
        let columns = northEast.x - southWest.x + 1
        let rows = southWest.y - northEast.y + 1
        guard columns >= 1, rows >= 1 else { throw LineNetworkError.invalidBox }
        guard columns * rows <= Self.maximumCells else { throw LineNetworkError.tooManyCells(columns * rows, limit: Self.maximumCells) }
        var builder = Builder(classes: classes)
        for x in southWest.x...northEast.x {
            for y in northEast.y...southWest.y {
                guard let cell = TileID(zoom: source.storageZoom, x: x, y: y), let file = try source.file(containing: cell) else { continue }
                builder.add(try file.features(in: cell, band: .detail, classes: classes))
            }
        }
        self = builder.finish()
    }

    /// Collects the nodes and edges, a cell at a time.
    private struct Builder {
        let classes: Set<UInt8>
        var nodes: [Vertex: Int] = [:]
        var seen = Set<EdgeKey>()
        var coordinates: [Coordinate] = []
        var edges: [Edge] = []
        var incident: [[Int]] = []

        init(classes: Set<UInt8>) { self.classes = classes }

        mutating func node(_ point: PackedPoint) -> Int {
            let vertex = Vertex(longitude: point.longitude, latitude: point.latitude)
            if let found = nodes[vertex] { return found }
            let index = coordinates.count
            nodes[vertex] = index
            coordinates.append(Coordinate(latitude: Double(point.latitude) / 1e7, longitude: Double(point.longitude) / 1e7))
            incident.append([])
            return index
        }

        mutating func add(_ features: [StoredFeature]) {
            for feature in features where feature.kind == .line && classes.contains(feature.classID) {
                for part in feature.parts where part.points.count >= 2 {
                    var previous = node(part.points[0])
                    // The distance along the way to `previous`: the offset of the piece (in centimetres), then the steps.
                    var offset = Double(feature.offsetAlongLine) / 100
                    for point in part.points.dropFirst() {
                        let next = node(point)
                        let start = offset
                        offset += coordinates[previous].distance(to: coordinates[next])
                        defer { previous = next }
                        guard next != previous,
                            seen.insert(EdgeKey(low: min(previous, next), high: max(previous, next), way: feature.objectID)).inserted
                        else { continue }
                        incident[previous].append(edges.count)
                        incident[next].append(edges.count)
                        edges.append(
                            Edge(
                                from: previous, to: next, length: coordinates[previous].distance(to: coordinates[next]), wayID: feature.objectID,
                                classID: feature.classID, wayOffset: start))
                    }
                }
            }
        }

        func finish() -> LineNetwork {
            var network = LineNetwork()
            network.coordinates = coordinates
            network.edges = edges
            network.incident = incident
            network.buildIndex()
            return network
        }
    }

    private init() {}

    // MARK: Index

    private mutating func buildIndex() {
        guard let first = coordinates.first else { return }
        // A bucket is about 55 m high and as wide in longitude as in latitude at the first node.
        longitudeScale = max(cos(first.latitude * .pi / 180), 0.01)
        for (index, edge) in edges.enumerated() {
            let a = coordinates[edge.from], b = coordinates[edge.to]
            let x0 = bucketX(min(a.longitude, b.longitude)), x1 = bucketX(max(a.longitude, b.longitude))
            let y0 = bucketY(min(a.latitude, b.latitude)), y1 = bucketY(max(a.latitude, b.latitude))
            if (x1 - x0 + 1) * (y1 - y0 + 1) <= Self.boxFillLimit {
                for x in x0...x1 { for y in y0...y1 { buckets[Bucket(x: x, y: y), default: []].append(index) } }
            } else {
                // A long edge: the buckets along it, and their neighbours, so that a point near the edge finds it from any side. This is
                // a few entries for each bucket the edge crosses, not the whole box, which for a long diagonal would be millions.
                let steps = max(x1 - x0, y1 - y0) * 4 + 1
                var seen = Set<Bucket>()
                for step in 0...steps {
                    let t = Double(step) / Double(steps)
                    let x = bucketX(a.longitude + (b.longitude - a.longitude) * t), y = bucketY(a.latitude + (b.latitude - a.latitude) * t)
                    for dx in -1...1 { for dy in -1...1 where seen.insert(Bucket(x: x + dx, y: y + dy)).inserted {
                        buckets[Bucket(x: x + dx, y: y + dy), default: []].append(index)
                    } }
                }
            }
        }
    }

    private func bucketX(_ longitude: Double) -> Int { Int((longitude * longitudeScale / Self.bucketSize).rounded(.down)) }
    private func bucketY(_ latitude: Double) -> Int { Int((latitude / Self.bucketSize).rounded(.down)) }

    // MARK: Query

    /// The edges that pass within a distance of a position, nearest first.
    ///
    /// - Parameters:
    ///   - coordinate: The position.
    ///   - metres: The radius, in metres; 0 or less finds nothing.
    /// - Returns: For each edge within the radius, the nearest point on it. The distance is measured on a flat map around the position,
    ///   which is within a few centimetres at the distances of a GPS fix.
    public func edges(near coordinate: Coordinate, within metres: Double) -> [EdgeProjection] {
        guard metres > 0, metres.isFinite, !edges.isEmpty, coordinate.isValid else { return [] }
        let metresPerDegree = Coordinate.earthRadius * .pi / 180
        let cosine = max(cos(coordinate.latitude * .pi / 180), 0.01)
        let latitudeReach = metres / metresPerDegree
        let longitudeReach = metres / (metresPerDegree * cosine)
        let x0 = bucketX(coordinate.longitude - longitudeReach), x1 = bucketX(coordinate.longitude + longitudeReach)
        let y0 = bucketY(coordinate.latitude - latitudeReach), y1 = bucketY(coordinate.latitude + latitudeReach)
        var checked = Set<Int>()
        var found: [EdgeProjection] = []
        for x in x0...x1 {
            for y in y0...y1 {
                for index in buckets[Bucket(x: x, y: y)] ?? [] where checked.insert(index).inserted {
                    let edge = edges[index]
                    let a = coordinates[edge.from], b = coordinates[edge.to]
                    // The edge on a flat map in metres, with the position at the origin.
                    let ax = (a.longitude - coordinate.longitude) * metresPerDegree * cosine, ay = (a.latitude - coordinate.latitude) * metresPerDegree
                    let bx = (b.longitude - coordinate.longitude) * metresPerDegree * cosine, by = (b.latitude - coordinate.latitude) * metresPerDegree
                    let dx = bx - ax, dy = by - ay
                    let squared = dx * dx + dy * dy
                    let fraction = squared > 0 ? max(0, min(1, -(ax * dx + ay * dy) / squared)) : 0
                    let distance = hypot(ax + fraction * dx, ay + fraction * dy)
                    guard distance <= metres else { continue }
                    let point = Coordinate(
                        latitude: a.latitude + (b.latitude - a.latitude) * fraction, longitude: a.longitude + (b.longitude - a.longitude) * fraction)
                    found.append(EdgeProjection(edge: index, coordinate: point, fraction: fraction, distance: distance))
                }
            }
        }
        return found.sorted { $0.distance < $1.distance }
    }

    /// The other end of an edge, seen from one of its nodes.
    ///
    /// - Parameters:
    ///   - edge: The index of the edge.
    ///   - node: The index of a node of the edge.
    public func otherEnd(of edge: Int, from node: Int) -> Int {
        edges[edge].from == node ? edges[edge].to : edges[edge].from
    }
}
