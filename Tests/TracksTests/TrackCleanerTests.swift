import Foundation
import Testing

@testable import Tracks

/// Cutting a recorded track where it jumped, and merging the points where the runner stood still.
@Suite("Track cleaner")
struct TrackCleanerTests {
    private let start = Date(timeIntervalSince1970: 1_793_516_400)

    /// A point on the equator `index` steps of 0.0001 degrees (11.1 m) from the origin, `seconds` after the start.
    private func point(_ index: Double, at seconds: Double?) -> TrackPoint {
        TrackPoint(latitude: 0, longitude: index * 0.0001, time: seconds.map { start.addingTimeInterval($0) })
    }

    /// `count` points, one every 5 s, 11.1 m apart (2.2 m/s); the first is at step `from` (of 11.1 m) and at `seconds` after the start.
    private func run(_ count: Int, from first: Int = 0, at seconds: Double = 0) -> [TrackPoint] {
        (0..<count).map { point(Double(first + $0), at: seconds + Double($0) * 5) }
    }

    @Test("A clean run is one stretch with every point and no cut")
    func clean() {
        let result = TrackCleaner.clean(run(50))
        #expect(result.segments.count == 1 && result.segments[0].points.count == 50)
        #expect(result.breaks.isEmpty && result.mergedPoints == 0 && result.droppedSegments == 0 && result.segments[0].stops.isEmpty)
    }

    @Test("Nothing, and one point, give no stretch")
    func tooFew() {
        #expect(TrackCleaner.clean([]).segments.isEmpty)
        let one = TrackCleaner.clean(run(1))
        #expect(one.segments.isEmpty && one.droppedSegments == 1)
    }

    @Test("Points where the runner stood still become one point with the time it lasted")
    func standingStill() throws {
        // 10 points of running, 30 fixes within a metre or two, 10 points of running.
        var points = run(10)
        let stopTime = 10.0 * 5
        for index in 0..<30 {
            points.append(TrackPoint(latitude: 0.00001 * Double(index % 3), longitude: 0.00100 + 0.00001 * Double(index % 2), time: start.addingTimeInterval(stopTime + Double(index) * 2)))
        }
        points += run(10, from: 11, at: 140)
        let result = TrackCleaner.clean(points)
        let segment = try #require(result.segments.first)
        #expect(result.segments.count == 1 && result.breaks.isEmpty)
        #expect(result.mergedPoints == 29 && segment.points.count == 10 + 1 + 10)
        let stop = try #require(segment.stops.first)
        #expect(segment.stops.count == 1 && stop.pointIndex == 10 && stop.seconds == 58)
        #expect(segment.points[10].time == start.addingTimeInterval(stopTime), "the stop keeps the time of its first point")
        #expect(abs(segment.points[10].coordinate.longitude - 0.00100) < 0.00002)
    }

    @Test("Points that are close for a moment are not a stop: they all stay")
    func shortStop() throws {
        var points = run(5)
        // A fix 1 m from the last point, 2 s later: the same place for 2 s, which is no stop.
        points.append(TrackPoint(latitude: 0, longitude: 0.0004 + 0.00001, time: start.addingTimeInterval(20 + 2)))
        points += run(5, from: 5, at: 25)
        let result = TrackCleaner.clean(points)
        #expect(result.mergedPoints == 0 && result.segments[0].stops.isEmpty && result.segments[0].points.count == 11)
    }

    @Test("A run recorded once a second keeps every point, and so does a slow climb")
    func denseRecording() {
        // 3 m/s at 1 Hz: two points within 4 m of each other all the way. Nothing is merged and nothing is a stop.
        let fast = (0..<600).map { TrackPoint(latitude: 0, longitude: Double($0) * 3 / 111_195, time: start.addingTimeInterval(Double($0))) }
        let result = TrackCleaner.clean(fast)
        #expect(result.segments.count == 1 && result.segments[0].points == fast && result.mergedPoints == 0 && result.segments[0].stops.isEmpty)
        // 0.3 m/s at 1 Hz (a snowshoe climb): 13 s inside 4 m. Each cluster of 14 points lasts over 10 s, so those are stops.
        let slow = (0..<60).map { TrackPoint(latitude: 0, longitude: Double($0) * 0.3 / 111_195, time: start.addingTimeInterval(Double($0))) }
        #expect(TrackCleaner.clean(slow).segments.first?.stops.isEmpty == false, "below walking pace the points are taken as standing still")
    }

    @Test("Without times nothing shows that the runner stood still, so no point is merged")
    func untimedStop() {
        let points = (0..<20).map { TrackPoint(latitude: 0, longitude: Double($0) * 0.00001) }  // 1.1 m apart
        let result = TrackCleaner.clean(points)
        #expect(result.mergedPoints == 0 && result.segments.first?.points.count == 20)
    }

    @Test("A time that goes back is a cut when the step is long, and no time at all when it is short")
    func timeGoesBack() {
        var points = run(5)
        points.append(point(40, at: 15))  // 400 m on, 5 s before the previous point
        points += run(5, from: 41, at: 20)
        let result = TrackCleaner.clean(points)
        #expect(result.breaks.count >= 1)
        let wander = [point(0, at: 10), point(0.1, at: 9), point(0.2, at: 12)]
        #expect(TrackCleaner.clean(wander).breaks.isEmpty)
    }

    @Test("A stop at the start or the end of a stretch, and two stops with their indexes")
    func stopsAtEnds() throws {
        func still(_ count: Int, from seconds: Double, at index: Double) -> [TrackPoint] {
            (0..<count).map { TrackPoint(latitude: 0, longitude: index * 0.0001, time: start.addingTimeInterval(seconds + Double($0))) }
        }
        let points = still(15, from: 0, at: 0) + run(5, from: 1, at: 20) + still(15, from: 50, at: 6)
        let segment = try #require(TrackCleaner.clean(points).segments.first)
        #expect(segment.stops.map(\.pointIndex) == [0, 6] && segment.stops.allSatisfy { $0.seconds == 14 })
        #expect(segment.points.count == 7)
    }

    @Test("The limits are 'more than': just under is no cut, just over is")
    func thresholds() {
        let rules = TrackCleaningRules(maximumGap: 120, gapDistance: 100)
        let metre = 1 / 111_195.0
        func pair(metres: Double, seconds: Double) -> [TrackPoint] {
            [TrackPoint(latitude: 0, longitude: 0, time: start), TrackPoint(latitude: 0, longitude: metres * metre, time: start.addingTimeInterval(seconds))]
        }
        #expect(TrackCleaner.clean(pair(metres: 99.5, seconds: 500), rules: rules).breaks.isEmpty, "a move under 100 m is the same place")
        #expect(TrackCleaner.clean(pair(metres: 100.5, seconds: 500), rules: rules).breaks.count == 1)
        #expect(TrackCleaner.clean(pair(metres: 500, seconds: 119.5), rules: rules).breaks.isEmpty, "a gap under 120 s is none (4 m/s)")
        #expect(TrackCleaner.clean(pair(metres: 500, seconds: 120.5), rules: rules).breaks.count == 1)
    }

    @Test("A pause in the same place is a stop, not a cut")
    func pauseInPlace() throws {
        var points = run(10)
        // Forty minutes later, 20 m on: the same stretch (the move is under 100 m).
        points += run(10, from: 11, at: 45 + 2_400)
        let result = TrackCleaner.clean(points)
        #expect(result.breaks.isEmpty && result.segments.count == 1 && result.segments[0].points.count == 20)
    }

    @Test("A recording that went on somewhere else is cut, and nothing joins the two places")
    func resumedElsewhere() throws {
        // A hike, 40 minutes of pause, and then points 25 km away (the real case, 10 m/s over the gap).
        var points = run(10)
        points += run(10, from: 225_000, at: 45 + 2_400)
        let result = TrackCleaner.clean(points)
        #expect(result.segments.count == 2 && result.segments.map(\.points.count) == [10, 10])
        let cut = try #require(result.breaks.first)
        #expect(result.breaks.count == 1 && cut.afterIndex == 9)
        guard case .gap(let seconds, let metres) = cut.reason else { Issue.record("not a gap: \(cut.reason)"); return }
        #expect(abs(seconds - 2_400) < 5 && metres > 20_000)
    }

    @Test("A step faster than any runner is cut: one bad fix between two good stretches leaves two stretches")
    func badFix() throws {
        var points = run(10)
        points.append(TrackPoint(latitude: 0.05, longitude: 0.0010, time: start.addingTimeInterval(50)))  // 5.5 km in 5 s
        points += run(10, from: 11, at: 55)
        let result = TrackCleaner.clean(points)
        #expect(result.segments.map(\.points.count) == [10, 10])
        #expect(result.breaks.count == 2 && result.droppedSegments == 1)
        #expect(result.breaks.map(\.afterIndex) == [9, 10])
        guard case .speed(let speed, _) = result.breaks[0].reason else { Issue.record("not a speed"); return }
        #expect(speed > 1_000)
    }

    @Test("A step with no time to it is a jump when it is long")
    func noTime() throws {
        var points = run(5)
        points.append(point(5, at: 25.0))
        points.append(TrackPoint(latitude: 0.1, longitude: 0, time: start.addingTimeInterval(25)))  // 11 km, the same second
        points += run(5, from: 12_000, at: 25)
        let result = TrackCleaner.clean(points)
        #expect(result.breaks.count == 2, "the point in no time is cut off on both sides")
        guard case .speed(let speed, _) = result.breaks[0].reason else { Issue.record("not a speed"); return }
        #expect(speed.isInfinite)
    }

    @Test("A short step is never a jump, however fast it looks")
    func shortStep() {
        // 30 m in 1 s is 30 m/s, but under the jump distance of 50 m.
        let points = [point(0, at: 0), point(2.7, at: 1), point(5.4, at: 2), point(8.1, at: 3)]
        #expect(TrackCleaner.clean(points).breaks.isEmpty)
    }

    @Test("Points with no times are cut by distance only")
    func untimed() throws {
        let points = (0..<5).map { point(Double($0), at: nil) } + (0..<5).map { point(Double(20_000 + $0), at: nil) }
        let result = TrackCleaner.clean(points)
        #expect(result.segments.count == 2)
        guard case .jump(let metres) = try #require(result.breaks.first).reason else { Issue.record("not a jump"); return }
        #expect(metres > 2_000)
    }

    @Test("The rules can be changed: a faster limit lets a descent through, and negative numbers become 0")
    func rules() {
        let fast = (0..<10).map { point(Double($0) * 10, at: Double($0)) }  // 111 m in 1 s
        #expect(TrackCleaner.clean(fast).breaks.count == 9)
        #expect(TrackCleaner.clean(fast, rules: TrackCleaningRules(maximumSpeed: 200)).breaks.isEmpty)
        let rules = TrackCleaningRules(maximumGap: -1, gapDistance: -1, maximumSpeed: -1, jumpDistance: -1, jumpDistanceUntimed: -1, stationaryRadius: -1, minimumStop: -1)
        #expect(rules.maximumGap == 0 && rules.stationaryRadius == 0 && rules.minimumStop == 0 && rules.maximumSpeed == 0)
    }

    @Test("An activity cleans itself with the same rules")
    func activity() throws {
        let track = try ActivityTrack(points: run(20))
        #expect(track.cleaned().segments.first?.points.count == 20)
    }
}
