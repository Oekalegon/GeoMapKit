import Foundation
import GeoCore
import Testing

@testable import Tracks

/// The route model: lengths, positions along it, segments, and the projection of a position onto it.
@Suite("Route")
struct RouteTests {
    /// Points along the equator, `step` degrees apart (0.001 degrees is about 111.2 m).
    private func equator(_ count: Int, step: Double = 0.001) -> [TrackPoint] {
        (0..<count).map { TrackPoint(latitude: 0, longitude: Double($0) * step) }
    }

    private let metresPerStep = 111.195

    @Test("The distances add up along the steps, and the box and the length follow")
    func lengths() throws {
        let route = try Route(name: "Line", points: equator(3))
        #expect(route.name == "Line" && route.points.count == 3 && route.distances.count == 3)
        #expect(route.distances[0] == 0)
        #expect(abs(route.distances[1] - metresPerStep) < 0.5 && abs(route.length - 2 * metresPerStep) < 1)
        #expect(route.boundingBox == BoundingBox(south: 0, west: 0, north: 0, east: 0.002))
        #expect(route.segmentStarts == [0])
    }

    @Test("A route of one point has length 0, and so does one whose points are all the same")
    func degenerate() throws {
        let one = try Route(points: [TrackPoint(latitude: 59, longitude: 10)])
        #expect(one.length == 0 && one.coordinate(atDistance: 50) == Coordinate(latitude: 59, longitude: 10))
        let same = try Route(points: Array(repeating: TrackPoint(latitude: 59, longitude: 10), count: 3))
        #expect(same.length == 0 && same.project(Coordinate(latitude: 59.001, longitude: 10)).distanceAlong == 0)
        #expect(abs(one.project(Coordinate(latitude: 59.001, longitude: 10)).distance - 111.2) < 0.5)
    }

    @Test("A step of zero length in the middle is passed over without trouble")
    func zeroLengthStep() throws {
        var points = equator(3)
        points.insert(points[1], at: 1)
        let route = try Route(points: points)
        #expect(abs(route.length - 2 * metresPerStep) < 1)
        let middle = route.coordinate(atDistance: route.length / 2)
        #expect(abs(middle.longitude - 0.001) < 1e-6)
        #expect(abs(route.project(Coordinate(latitude: 0, longitude: 0.001)).distanceAlong - metresPerStep) < 0.5)
    }

    @Test("The position at a distance is found between the points, clamped at the ends")
    func coordinateAtDistance() throws {
        let route = try Route(points: equator(3))
        #expect(route.coordinate(atDistance: -10) == route.points[0].coordinate)
        #expect(route.coordinate(atDistance: 0) == route.points[0].coordinate)
        #expect(abs(route.coordinate(atDistance: metresPerStep / 2).longitude - 0.0005) < 1e-6)
        #expect(abs(route.coordinate(atDistance: metresPerStep * 1.5).longitude - 0.0015) < 1e-6)
        #expect(route.coordinate(atDistance: route.length) == route.points[2].coordinate)
        #expect(route.coordinate(atDistance: route.length + 1000) == route.points[2].coordinate)
    }

    @Test("Segments are joined, and the distance goes on across the gap")
    func segments() throws {
        let track = GPXTrack(segments: [equator(2), [TrackPoint(latitude: 0, longitude: 0.01), TrackPoint(latitude: 0, longitude: 0.011)]])
        let route = try track.route()
        #expect(route.segmentStarts == [0, 2] && route.points.count == 4)
        // 0.001 + the gap of 0.009 + 0.001 degrees.
        #expect(abs(route.length - 0.011 * 111_195) < 2)
        #expect(throws: RouteError.invalidSegmentStarts) { try Route(points: equator(3), segmentStarts: [0, 3]) }
        #expect(throws: RouteError.invalidSegmentStarts) { try Route(points: equator(3), segmentStarts: [1]) }
        #expect(throws: RouteError.invalidSegmentStarts) { try Route(points: equator(3), segmentStarts: [0, 2, 1]) }
    }

    @Test("No points, an invalid position, and a step across the antimeridian are refused")
    func refused() {
        #expect(throws: RouteError.empty) { try Route(points: []) }
        #expect(throws: RouteError.invalidCoordinate(index: 1)) {
            try Route(points: [TrackPoint(latitude: 0, longitude: 0), TrackPoint(latitude: .nan, longitude: 0)])
        }
        #expect(throws: RouteError.invalidCoordinate(index: 0)) { try Route(points: [TrackPoint(latitude: 91, longitude: 0)]) }
        #expect(throws: RouteError.crossesAntimeridian(index: 1)) {
            try Route(points: [TrackPoint(latitude: 0, longitude: 179.9), TrackPoint(latitude: 0, longitude: -179.9)])
        }
    }

    // MARK: Projection

    @Test("A position beside the route is projected onto it, with the distance along and the distance to it")
    func projection() throws {
        let route = try Route(points: equator(3))
        // 0.0005 degrees of latitude is 55.6 m, abreast of the middle of the first step.
        let side = route.project(Coordinate(latitude: 0.0005, longitude: 0.0005))
        #expect(abs(side.distance - 55.6) < 0.5 && abs(side.distanceAlong - metresPerStep / 2) < 0.5 && side.stepIndex == 0)
        #expect(abs(side.coordinate.longitude - 0.0005) < 1e-6 && abs(side.coordinate.latitude) < 1e-9)
        let on = route.project(Coordinate(latitude: 0, longitude: 0.0015))
        #expect(on.distance < 0.01 && abs(on.distanceAlong - 1.5 * metresPerStep) < 0.5 && on.stepIndex == 1)
    }

    @Test("A position before the start or beyond the end is projected onto the end point")
    func beyondTheEnds() throws {
        let route = try Route(points: equator(3))
        let before = route.project(Coordinate(latitude: 0, longitude: -0.001))
        #expect(before.distanceAlong == 0 && abs(before.distance - metresPerStep) < 0.5)
        let after = route.project(Coordinate(latitude: 0, longitude: 0.004))
        #expect(abs(after.distanceAlong - route.length) < 1e-9 && abs(after.distance - 2 * metresPerStep) < 1)
    }

    @Test("Out and back: a position on the way back is ambiguous, and a window tells the passes apart")
    func outAndBack() throws {
        // East for 0.003 degrees, then back west along the same line: the point at 0.002 is passed twice.
        let out = equator(4), back = Array(equator(4).reversed().dropFirst())
        let route = try Route(points: out + back)
        let position = Coordinate(latitude: 0, longitude: 0.002)
        let nearest = route.project(position)
        #expect(nearest.distance < 0.01)
        #expect(abs(nearest.distanceAlong - 2 * metresPerStep) < 0.5, "equally near: the smaller distance along wins")
        let onTheWayBack = route.project(position, in: (4 * metresPerStep)...route.length)
        #expect(onTheWayBack.distance < 0.01 && abs(onTheWayBack.distanceAlong - 4 * metresPerStep) < 0.5)
        // A window around the first pass finds the first pass.
        let first = route.project(position, in: 0...(3 * metresPerStep))
        #expect(abs(first.distanceAlong - 2 * metresPerStep) < 0.5)
        // The total length is out and back.
        #expect(abs(route.length - 6 * metresPerStep) < 1)
    }

    @Test("A loop that crosses itself: the window picks the pass, and the nearest pass wins without one")
    func selfCrossing() throws {
        // A figure of eight: along the equator east, up and back diagonally across, then ...
        let points = [
            TrackPoint(latitude: 0, longitude: 0), TrackPoint(latitude: 0, longitude: 0.002),
            TrackPoint(latitude: 0.002, longitude: 0.002), TrackPoint(latitude: 0.002, longitude: 0),
            TrackPoint(latitude: -0.001, longitude: 0.001),
        ]
        let route = try Route(points: points)
        // The crossing at (0.0005... on the diagonal) is a place the route passes twice; the diagonal from (0.002, 0) to (-0.001, 0.001).
        let crossing = Coordinate(latitude: 0, longitude: 0.00067)
        let whole = route.project(crossing)
        #expect(whole.distance < 3)
        let late = route.project(crossing, in: route.distances[3]...route.length)
        #expect(late.distance < 3 && late.distanceAlong > route.distances[3])
        let early = route.project(crossing, in: 0...route.distances[1])
        #expect(early.distanceAlong <= route.distances[1] && early.distance < 3)
        #expect(early.distanceAlong < late.distanceAlong)
    }

    @Test("A window beyond an end of the route is moved to that end")
    func windowBeyondTheRoute() throws {
        let route = try Route(points: equator(3))
        let past = route.project(Coordinate(latitude: 0, longitude: 0.001), in: 10_000...20_000)
        #expect(abs(past.distanceAlong - route.length) < 1e-9)
        let negative = route.project(Coordinate(latitude: 0, longitude: 0.001), in: (-500)...(-100))
        #expect(negative.distanceAlong == 0)
    }

    @Test("The projection is right at high latitude, where a degree of longitude is short")
    func highLatitude() throws {
        let points = [TrackPoint(latitude: 69, longitude: 18), TrackPoint(latitude: 69, longitude: 18.01)]
        let route = try Route(points: points)
        // 0.01 degrees of longitude at 69 N is 0.01 * 111195 * cos(69 deg) = 398.5 m.
        #expect(abs(route.length - 398.5) < 1.5)
        let beside = route.project(Coordinate(latitude: 69.001, longitude: 18.005))
        #expect(abs(beside.distance - 111.2) < 1 && abs(beside.distanceAlong - route.length / 2) < 1)
    }
}
