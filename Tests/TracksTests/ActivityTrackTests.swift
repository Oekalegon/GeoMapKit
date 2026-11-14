import Foundation
import Testing

@testable import Tracks

/// Which tracks are activities: points with times, in order.
@Suite("Activity track")
struct ActivityTrackTests {
    private let start = Date(timeIntervalSince1970: 1_793_516_400)

    /// `count` points along the equator, one every `seconds` seconds, 0.001 degrees apart (111.2 m).
    private func points(_ count: Int, seconds: Double = 30, timed: (Int) -> Bool = { _ in true }) -> [TrackPoint] {
        (0..<count).map { index in
            TrackPoint(
                latitude: 0, longitude: Double(index) * 0.001, time: timed(index) ? start.addingTimeInterval(Double(index) * seconds) : nil)
        }
    }

    @Test("A track with times is an activity, with its start, duration and distance")
    func activity() throws {
        let track = try ActivityTrack(points: points(11))
        #expect(track.tags.isEmpty && track.points.count == 11)
        #expect(track.startDate == start && track.duration == 300)
        #expect(abs(track.distance - 1_112) < 2)
        #expect(track.id.hasPrefix("gpx-") && track.id.count == 4 + 16)
    }

    @Test("A planned route, with no times, is not an activity")
    func plannedRoute() {
        #expect(throws: NotAnActivity.tooFewTimes(fraction: 0)) { try ActivityTrack(points: points(10, timed: { _ in false })) }
        #expect(throws: NotAnActivity.tooFewPoints(0)) { try ActivityTrack(points: []) }
        #expect(throws: NotAnActivity.tooFewPoints(1)) { try ActivityTrack(points: points(1)) }
    }

    @Test("A few points with no time are dropped, and too many refuse the track")
    func missingTimes() throws {
        // One in ten without a time: 90 % are timed, which is enough.
        let mostly = try ActivityTrack(points: points(20, timed: { $0 % 10 != 5 }))
        #expect(mostly.points.count == 18 && mostly.points.allSatisfy { $0.time != nil })
        #expect(throws: NotAnActivity.self) { try ActivityTrack(points: points(20, timed: { $0 % 2 == 0 })) }
        #expect(throws: NotAnActivity.self) { try ActivityTrack(points: points(20, timed: { $0 % 4 != 0 })) }
        let rules = ActivityRules(minimumTimedFraction: 0.5)
        #expect(try ActivityTrack(points: points(20, timed: { $0 % 2 == 0 }), rules: rules).points.count == 10)
    }

    @Test("A time that goes back a little is forgiven, and a time that goes back a lot refuses the track")
    func timeGoesBack() throws {
        var forgiven = points(5)
        forgiven[3].time = forgiven[2].time!.addingTimeInterval(-1)
        let track = try ActivityTrack(points: forgiven)
        #expect(track.points[3].time == forgiven[2].time && track.points.count == 5, "set to the time before")
        var refused = points(5)
        refused[3].time = refused[2].time!.addingTimeInterval(-10)
        #expect(throws: NotAnActivity.timeGoesBack(index: 3, seconds: 10)) { try ActivityTrack(points: refused) }
    }

    @Test("All the same time is no activity")
    func noDuration() {
        #expect(throws: NotAnActivity.noDuration) { try ActivityTrack(points: points(4, seconds: 0)) }
    }

    @Test("The id is the same for the same activity and differs when the start, the size or the place differ")
    func identity() throws {
        let a = try ActivityTrack(points: points(10)), b = try ActivityTrack(points: points(10))
        #expect(a.id == b.id, "a duplicate is found by its id")
        let later = points(10).map { TrackPoint(coordinate: $0.coordinate, time: $0.time!.addingTimeInterval(60)) }
        #expect(try ActivityTrack(points: later).id != a.id)
        #expect(try ActivityTrack(points: points(11)).id != a.id)
        let moved = points(10).map { TrackPoint(latitude: 1, longitude: $0.coordinate.longitude, time: $0.time) }
        #expect(try ActivityTrack(points: moved).id != a.id)
        #expect(try ActivityTrack(id: "workout-1", points: points(10)).id == "workout-1")
    }

    @Test("A track of a GPX file is an activity when its points have times, and a route never is")
    func fromGPX() throws {
        let gpx = """
            <gpx><trk><name>Run</name><type>running</type><trkseg>
              <trkpt lat="1" lon="2"><time>2026-11-01T07:00:00Z</time></trkpt>
              <trkpt lat="1.001" lon="2"><time>2026-11-01T07:00:30Z</time></trkpt>
            </trkseg></trk>
            <trk><name>Drawn</name><trkseg><trkpt lat="1" lon="2"/><trkpt lat="1.001" lon="2"/></trkseg></trk>
            <rte><name>Planned</name><rtept lat="1" lon="2"/><rtept lat="1.001" lon="2"/></rte></gpx>
            """
        let file = try GPXFile(data: Data(gpx.utf8))
        let run = try file.tracks[0].activity()
        #expect(run.tags == ["gpx.name": .string("Run"), "gpx.type": .string("running")] && run.duration == 30)
        // The tags of the app are added, and win over those of the file.
        let tagged = try file.tracks[0].activity(tags: ["sport": .string("trail"), "gpx.type": .string("hiking"), "rating": .integer(4)])
        #expect(tagged.tags["sport"] == .string("trail") && tagged.tags["gpx.type"] == .string("hiking") && tagged.tags["rating"] == .integer(4))
        #expect(tagged.tags["gpx.name"] == .string("Run"))
        #expect(try file.tracks[0].activity().id == tagged.id, "tags are not part of the id")
        #expect(throws: NotAnActivity.self) { try file.tracks[1].activity() }
        #expect(try file.routes[0].route().length > 100)
        #expect(try file.tracks[0].activity(id: "mine").id == "mine")
    }

    @Test("Tags of any kind are kept as they are, and survive encoding")
    func tags() throws {
        let payload = Data([1, 2, 3, 250])
        let date = Date(timeIntervalSince1970: 1_793_516_400)
        let tags: [String: TagValue] = [
            "sport": .string("trail running"), "workout": .integer(12_345), "effort": .double(7.5), "race": .bool(true),
            "recorded": .date(date), "blob": .data(payload),
        ]
        let track = try ActivityTrack(id: "app-1", points: points(5), tags: tags)
        #expect(track.tags == tags)
        let data = try JSONEncoder().encode(tags)
        #expect(try JSONDecoder().decode([String: TagValue].self, from: data) == tags)
        var changed = track
        changed.tags["sport"] = .string("hiking")
        #expect(changed != track && changed.points == track.points)
    }
}
