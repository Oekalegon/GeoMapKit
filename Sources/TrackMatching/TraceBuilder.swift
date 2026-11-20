import Foundation
import GeoCore

/// Puts off-track stretches together into traces: lines that were run more than once across open ground.
///
/// A stretch is put at the spacing of the rules and compared, point by point, with the traces that exist. Where it runs within the
/// join distance of one trace for at least the minimum join length it **joins** it: the vertices of the trace near it move to the
/// average of all the stretches that ran there, and the trace counts one more pass. The rest of the stretch (a part that is near no
/// trace, or near one for too short a distance) starts **new traces**. A trace is walked either way, so a stretch that comes back along
/// it joins it as well. A stretch is compared with the traces that existed before it, never with the ones it makes itself.
///
/// The result depends on the order in which the stretches are added (the first line of a trace is its first shape), so a store adds
/// them in the order of the activities' start times. The builder is a value, and everything in it is derived: it can be made again
/// from the stretches.
public struct TraceBuilder: Sendable {
    /// The rules.
    public let rules: TraceRules

    private struct Trace: Sendable {
        var id: Int64
        var latitudes: [Double]
        var longitudes: [Double]
        var weights: [Double]
        var sources: [Int64]
    }

    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    private struct VertexReference: Hashable {
        var trace: Int
        var index: Int
    }

    private struct Match {
        var trace: Int
        var segment: Int
        var fraction: Double
        var distance: Double
        var latitude: Double
        var longitude: Double
    }

    private var traceList: [Trace] = []
    private var grid: [Cell: [VertexReference]] = [:]
    private var longitudeScale: Double?
    private static let cellDegrees = 0.0002

    /// Creates an empty builder.
    public init(rules: TraceRules = .standard) { self.rules = rules }

    /// The traces made so far, in the order they were started.
    public var traces: [TrackTrace] {
        traceList.map { trace in
            let coordinates = zip(trace.latitudes, trace.longitudes).map { Coordinate(latitude: $0, longitude: $1) }
            let length = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
            return TrackTrace(id: trace.id, coordinates: coordinates, length: length, sources: trace.sources)
        }
    }

    /// Adds a stretch.
    ///
    /// - Parameters:
    ///   - line: The positions of the stretch in order.
    ///   - source: A number that says where the stretch is from (the store gives the id of the stretch). A trace that the stretch starts
    ///     gets the id `source * 1000 + k`, with k counting the traces the stretch starts (at most 1,000 for one stretch).
    /// - Returns: The ids of the traces that the stretch made or joined.
    @discardableResult
    public mutating func add(_ line: [Coordinate], source: Int64) -> [Int64] {
        let samples = resample(line)
        guard samples.count >= 2 else { return [] }
        if longitudeScale == nil { longitudeScale = max(cos(samples[0].latitude * .pi / 180), 0.01) }

        // What each sample runs along, against the traces as they are now.
        let matches = samples.map { nearest(to: $0) }

        // Sections of samples along one trace; a section long enough joins it.
        var joined = [Bool](repeating: false, count: samples.count)
        var touched: [Int64] = []
        var index = 0
        var sections: [(trace: Int, range: Range<Int>)] = []
        while index < samples.count {
            guard let first = matches[index] else {
                index += 1
                continue
            }
            var end = index + 1
            while end < samples.count, matches[end]?.trace == first.trace { end += 1 }
            let length = Double(end - index - 1) * rules.spacing
            if length >= rules.minimumJoinLength {
                for position in index..<end { joined[position] = true }
                sections.append((first.trace, index..<end))
            }
            index = end
        }

        // The rest starts new traces (made before the joins move anything, from the shape of the stretch itself).
        var made: [Trace] = []
        var start = 0
        while start < samples.count {
            if joined[start] {
                start += 1
                continue
            }
            var end = start + 1
            while end < samples.count, !joined[end] { end += 1 }
            if end - start >= 2, made.count < 1_000 {
                let part = samples[start..<end]
                made.append(
                    Trace(
                        id: source * 1_000 + Int64(made.count), latitudes: part.map(\.latitude), longitudes: part.map(\.longitude),
                        weights: [Double](repeating: 1, count: part.count), sources: [source]))
            }
            start = end
        }

        // The joins: the vertex nearest to each sample moves towards it.
        for section in sections {
            for position in section.range {
                guard let match = matches[position] else { continue }
                let vertex = match.fraction < 0.5 ? match.segment : match.segment + 1
                move(trace: match.trace, vertex: vertex, towards: samples[position])
            }
            traceList[section.trace].sources.append(source)
            touched.append(traceList[section.trace].id)
        }
        for trace in made {
            let number = traceList.count
            traceList.append(trace)
            for vertex in trace.latitudes.indices { insert(VertexReference(trace: number, index: vertex)) }
            touched.append(trace.id)
        }
        return touched
    }

    // MARK: Geometry

    /// The line at the spacing of the rules: its first point, a point every `spacing` metres along it, and its last point.
    private func resample(_ line: [Coordinate]) -> [Coordinate] {
        guard let first = line.first, line.count >= 2 else { return line }
        var result = [first]
        var carried = 0.0  // the distance since the last sample
        for (a, b) in zip(line, line.dropFirst()) {
            let length = a.distance(to: b)
            guard length > 0 else { continue }
            var position = rules.spacing - carried
            while position < length {
                let t = position / length
                result.append(
                    Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t))
                position += rules.spacing
            }
            carried = length - (position - rules.spacing)
        }
        if let last = line.last, let kept = result.last, kept != last, kept.distance(to: last) > 0 { result.append(last) }
        return result
    }

    private func cell(latitude: Double, longitude: Double) -> Cell {
        let scale = longitudeScale ?? 1
        return Cell(x: Int((longitude * scale / Self.cellDegrees).rounded(.down)), y: Int((latitude / Self.cellDegrees).rounded(.down)))
    }

    private mutating func insert(_ vertex: VertexReference) {
        let trace = traceList[vertex.trace]
        grid[cell(latitude: trace.latitudes[vertex.index], longitude: trace.longitudes[vertex.index]), default: []].append(vertex)
    }

    private mutating func remove(_ vertex: VertexReference) {
        let trace = traceList[vertex.trace]
        let key = cell(latitude: trace.latitudes[vertex.index], longitude: trace.longitudes[vertex.index])
        grid[key]?.removeAll { $0 == vertex }
        if grid[key]?.isEmpty == true { grid[key] = nil }
    }

    private mutating func move(trace: Int, vertex: Int, towards point: Coordinate) {
        let reference = VertexReference(trace: trace, index: vertex)
        remove(reference)
        let weight = traceList[trace].weights[vertex]
        traceList[trace].latitudes[vertex] = (traceList[trace].latitudes[vertex] * weight + point.latitude) / (weight + 1)
        traceList[trace].longitudes[vertex] = (traceList[trace].longitudes[vertex] * weight + point.longitude) / (weight + 1)
        traceList[trace].weights[vertex] = weight + 1
        insert(reference)
    }

    /// The nearest segment of any trace to a point, if it is within the join distance.
    private func nearest(to point: Coordinate) -> Match? {
        guard !grid.isEmpty else { return nil }
        let centre = cell(latitude: point.latitude, longitude: point.longitude)
        // A cell is at least about 15 m across at the latitudes of Europe; the reach is the join distance and a segment.
        let reach = max(1, Int(((rules.joinDistance + rules.spacing) / 15).rounded(.up)))
        let metresPerDegree = Coordinate.earthRadius * .pi / 180
        let cosine = max(cos(point.latitude * .pi / 180), 0.01)
        var best: Match?
        var checked = Set<VertexReference>()
        for x in (centre.x - reach)...(centre.x + reach) {
            for y in (centre.y - reach)...(centre.y + reach) {
                for vertex in grid[Cell(x: x, y: y)] ?? [] {
                    let trace = traceList[vertex.trace]
                    for segment in [vertex.index - 1, vertex.index] where segment >= 0 && segment + 1 < trace.latitudes.count {
                        let key = VertexReference(trace: vertex.trace, index: segment)
                        guard checked.insert(key).inserted else { continue }
                        // The segment on a flat map in metres, with the point at the origin.
                        let ax = (trace.longitudes[segment] - point.longitude) * metresPerDegree * cosine
                        let ay = (trace.latitudes[segment] - point.latitude) * metresPerDegree
                        let bx = (trace.longitudes[segment + 1] - point.longitude) * metresPerDegree * cosine
                        let by = (trace.latitudes[segment + 1] - point.latitude) * metresPerDegree
                        let dx = bx - ax, dy = by - ay
                        let squared = dx * dx + dy * dy
                        let fraction = squared > 0 ? max(0, min(1, -(ax * dx + ay * dy) / squared)) : 0
                        let distance = hypot(ax + fraction * dx, ay + fraction * dy)
                        guard distance <= rules.joinDistance, distance < (best?.distance ?? .infinity) else { continue }
                        best = Match(
                            trace: vertex.trace, segment: segment, fraction: fraction, distance: distance,
                            latitude: trace.latitudes[segment] + (trace.latitudes[segment + 1] - trace.latitudes[segment]) * fraction,
                            longitude: trace.longitudes[segment] + (trace.longitudes[segment + 1] - trace.longitudes[segment]) * fraction)
                    }
                }
            }
        }
        return best
    }
}
