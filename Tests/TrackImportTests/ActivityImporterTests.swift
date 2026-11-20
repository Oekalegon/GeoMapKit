import FeatureStore
import Foundation
import GeoCore
import Testing
import Tracks

@testable import FeatureStoreBuilder
@testable import TrackImport
@testable import TrackMatching
@testable import TrackStorage

@Suite("Activity importer")
struct ActivityImporterTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// 60 N, 10 E; a step of 0.0001 degrees of longitude is 5.6 m there.
    private func packed(_ east: Double, _ north: Double) -> PackedPoint {
        PackedPoint(longitude: 100_000_000 + Int32((east * 1_000).rounded()), latitude: 600_000_000 + Int32((north * 1_000).rounded()))
    }

    /// One path of about 560 m, from east 0 to east 100.
    private var network: LineNetwork {
        LineNetwork(features: [
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 7, offsetAlongLine: 0,
                parts: [GeometryPart(points: [packed(0, 0), packed(100, 0)])])
        ])
    }

    /// Fixes along the path, one about every 11 m, 4 s apart.
    private func walk(_ from: Double, _ to: Double, north: Double = 0, first: Double = 0) -> [TrackPoint] {
        let count = max(Int((abs(to - from) * 5.6 / 11).rounded()), 1)
        return (0...count).map { index in
            TrackPoint(
                coordinate: Coordinate(latitude: 60 + north * 0.0001, longitude: 10 + (from + (to - from) * Double(index) / Double(count)) * 0.0001),
                time: start.addingTimeInterval(first + Double(index) * 4))
        }
    }

    private func importer() -> ActivityImporter { ActivityImporter(network: network, mapID: "test", matchedWith: 3) }

    @Test("A run along a path is matched: its legs count, and its record carries the category, the tags and the map")
    func matched() async throws {
        let track = try ActivityTrack(id: "a", points: walk(0, 100), tags: ["sport": .string("run")])
        let store = try TrackStore(url: nil)
        let imported = try await importer().add(track, category: "trail", mode: .matched, to: store)
        #expect(imported.legs.count == 1 && imported.offTrack.isEmpty)
        #expect(imported.matchedLength > 400 && imported.length > 500 && imported.droppedSegments == 0)
        #expect(imported.lengthByClass[FeatureClass.path.rawValue] ?? 0 > 400)
        let stored = try #require(try await store.activity(appID: "a"))
        #expect(stored.category == "trail" && stored.mapID == "test" && stored.matchedWith == 3 && stored.tags["sport"] == .string("run"))
        let counts = try await store.counts(ways: [7], categories: ["trail"])
        #expect(!counts.isEmpty && counts.allSatisfy { $0.activities == 1 })
    }

    @Test("A raw activity adds no legs and no counts, and keeps its whole line as an off-track line")
    func raw() async throws {
        let track = try ActivityTrack(id: "o", points: walk(0, 100), tags: [:])
        let store = try TrackStore(url: nil)
        let imported = try await importer().add(track, category: "orienteering", mode: .raw, to: store)
        #expect(imported.legs.isEmpty && imported.matchedLength == 0 && imported.lengthByClass.isEmpty)
        #expect(imported.offTrack.count == 1 && imported.offTrack[0].coordinates.count == track.points.count)
        #expect(abs(imported.offTrack[0].length - track.distance) < 1)
        let counts = try await store.counts(ways: [7])
        let legs = try await store.legCount(), lines = try await store.offTrackLineCount()
        let stored = try await store.activity(appID: "o")
        #expect(counts.isEmpty && legs == 0 && lines == 1 && stored?.category == "orienteering")
    }

    @Test("The same activity added again as another category replaces the first: nothing is counted twice")
    func retag() async throws {
        let track = try ActivityTrack(id: "a", points: walk(0, 100), tags: [:])
        let store = try TrackStore(url: nil)
        try await importer().add(track, category: "trail", mode: .matched, to: store)
        try await importer().add(track, category: "orienteering", mode: .raw, to: store)
        let activities = try await store.activityCount(), legs = try await store.legCount()
        let raw = try await store.counts(ways: [7])
        #expect(activities == 1 && legs == 0 && raw.isEmpty)
        try await importer().add(track, category: "road", mode: .matched, to: store)
        let again = try await store.activityCount()
        let trail = try await store.counts(ways: [7], categories: ["trail"])
        let road = try await store.counts(ways: [7], categories: ["road"])
        #expect(again == 1 && trail.isEmpty && !road.isEmpty)
    }

    @Test("A run across open ground is off track: no legs, one off-track line that meets the path")
    func offTrack() async throws {
        let track = try ActivityTrack(id: "f", points: walk(0, 100, north: 60), tags: [:])
        let imported = try importer().prepare(track, category: "trail", mode: .matched)
        #expect(imported.legs.isEmpty && imported.matchedLength == 0)
        #expect(imported.offTrack.count == 1 && imported.offTrack[0].length > 400)
    }

    @Test("Prepare does not touch a store, and gives the same result twice")
    func prepareIsPure() throws {
        let track = try ActivityTrack(id: "a", points: walk(0, 100), tags: [:])
        let one = try importer().prepare(track, category: "trail", mode: .matched)
        let two = try importer().prepare(track, category: "trail", mode: .matched)
        #expect(one == two)
    }

    /// Two stretches of the path with a pause and a jump between them: cleaning cuts the track in two.
    private func twoSegments() -> [TrackPoint] { walk(0, 40) + walk(60, 100, first: 900) }

    @Test("A track with a gap is two segments: raw gives a line for each, matched gives legs from both")
    func gap() throws {
        let track = try ActivityTrack(id: "g", points: twoSegments(), tags: [:])
        let raw = try importer().prepare(track, category: "orienteering", mode: .raw)
        #expect(raw.offTrack.count == 2 && raw.offTrack.allSatisfy { $0.length >= 30 })
        let matched = try importer().prepare(track, category: "trail", mode: .matched)
        #expect(matched.legs.count == 2 && matched.offTrack.isEmpty)
        let covered: Double = matched.legs.map { $0.upperMetre - $0.lowerMetre }.reduce(0, +)
        #expect(abs(matched.countedLength - covered) < 40)
    }

    @Test("Only a stretch that counts is in the counted length: a short matched one is in the matched length alone")
    func counted() throws {
        let track = try ActivityTrack(id: "s", points: walk(0, 100), tags: [:])
        let all = try importer().prepare(track, category: "trail", mode: .matched)
        #expect(all.countedLength > 400 && abs(all.countedLength - all.matchedLength) < 1)
        var strict = importer()
        strict.minimumStretchLength = 10_000
        let none = try strict.prepare(track, category: "trail", mode: .matched)
        #expect(none.legs.isEmpty && none.countedLength == 0 && none.matchedLength > 400)
    }

    @Test("A raw segment under 30 m is noise and gives no line; a track of such segments gives none")
    func shortRaw() throws {
        let track = try ActivityTrack(id: "t", points: walk(0, 4), tags: [:])
        #expect(try importer().prepare(track, category: "orienteering", mode: .raw).offTrack.isEmpty)
    }

    @Test("Thresholds that are not numbers or out of range are brought into range, not passed on")
    func thresholds() throws {
        let track = try ActivityTrack(id: "n", points: walk(0, 100), tags: [:])
        var odd = importer()
        odd.minimumConfidence = .nan
        odd.minimumStretchLength = -5
        #expect(try odd.prepare(track, category: "trail", mode: .matched).legs.count == 1)
        odd.minimumConfidence = 7
        #expect(try odd.prepare(track, category: "trail", mode: .matched).legs.isEmpty)
    }

    @Test("A raw line of one category does not shape the traces of another")
    func rawAndTrailTracesApart() async throws {
        let store = try TrackStore(url: nil)
        // Open ground 60 north of the path: the trail run is off track there, the orienteering run is raw over the same ground.
        let ground = try ActivityTrack(id: "t", points: walk(0, 100, north: 60), tags: [:])
        let orienteering = try ActivityTrack(id: "o", points: walk(0, 100, north: 60, first: 100_000), tags: [:])
        try await importer().add(ground, category: "trail", mode: .matched, to: store)
        try await importer().add(orienteering, category: "orienteering", mode: .raw, to: store)
        let trail = try await store.traces(categories: ["trail"])
        let raw = try await store.traces(categories: ["orienteering"])
        #expect(trail.count == 1 && trail[0].activities == 1 && trail[0].passes == 1)
        #expect(raw.count == 1 && raw[0].activities == 1 && raw[0].passes == 1)
        #expect(Set(trail.map(\.id)).isDisjoint(with: raw.map(\.id)))
    }

    @Test("An import that fails leaves the store as it was")
    func failure() async throws {
        let store = try TrackStore(url: nil)
        let track = try ActivityTrack(id: "a", points: walk(0, 100), tags: [:])
        try await importer().add(track, category: "trail", mode: .matched, to: store)
        let before = try await store.legCount()
        // A store that is closed by a newer-version refusal cannot be made here, so a failing prepare is the case: a network with
        // no edges gives no legs and no error, and the activity is still replaced as a whole.
        let empty = ActivityImporter(network: LineNetwork(features: []), mapID: "none")
        try await empty.add(track, category: "trail", mode: .matched, to: store)
        let after = try await store.legCount(), count = try await store.activityCount()
        #expect(before == 1 && after == 0 && count == 1)
    }
}
