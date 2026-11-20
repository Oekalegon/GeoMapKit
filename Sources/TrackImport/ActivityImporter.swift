import Foundation
import GeoCore
import TrackMatching
import TrackStorage
import Tracks

/// Turns recorded activities into what the store keeps: clean, match to the lines of a map, cut into legs, and add.
///
/// The importer knows no source and no sport. The app turns what it has (GPX files, a workout store) into ``ActivityTrack``s, chooses
/// the category and the matching rules for it, and gives the importer a ``LineNetwork`` of the map the activity was recorded on.
///
/// Matching takes seconds for a long track: call ``prepare(_:category:mode:)`` or ``add(_:category:mode:to:)`` off the main actor.
public struct ActivityImporter: Sendable {
    /// The lines of the map.
    public let network: LineNetwork
    /// A name or identity of the map, stored with each activity so that a map update can tell which activities to match again.
    public var mapID: String
    /// How points are cleaned.
    public var cleaning: TrackCleaningRules
    /// How points are matched; the app chooses them for the sport.
    public var matching: MatchingRules
    /// The least confidence of a stretch that counts, from 0 to 1.
    public var minimumConfidence: Double
    /// The shortest recorded length of a stretch that counts, in metres.
    public var minimumStretchLength: Double
    /// The version number stored as ``StoredActivity/matchedWith``: raise it when the rules change, so that older activities can be found.
    public var matchedWith: Int

    /// Creates an importer.
    public init(
        network: LineNetwork, mapID: String, cleaning: TrackCleaningRules = .standard, matching: MatchingRules = .standard,
        minimumConfidence: Double = 0.5, minimumStretchLength: Double = 100, matchedWith: Int = 1
    ) {
        self.network = network
        self.mapID = mapID
        self.cleaning = cleaning
        self.matching = matching
        self.minimumConfidence = minimumConfidence
        self.minimumStretchLength = minimumStretchLength
        self.matchedWith = matchedWith
    }

    /// Makes an activity ready for the store, without touching the store.
    ///
    /// - Parameters:
    ///   - activity: The activity; its id becomes the app id in the store, so the same activity read twice replaces itself.
    ///   - category: The category the app chooses; it keeps the counts apart.
    ///   - mode: Whether the track is laid on the lines.
    /// - Throws: ``TrackLegsError`` if the matched and cleaned tracks disagree (a bug, not bad input).
    public func prepare(_ activity: ActivityTrack, category: String, mode: ImportMode) throws -> ImportedActivity {
        let cleaned = activity.cleaned(rules: cleaning)
        let record = StoredActivity(
            appID: activity.id, started: activity.startDate, category: category, tags: activity.tags, mapID: mapID, matchedWith: matchedWith)
        let length = cleaned.segments.reduce(0.0) { $0 + Self.length(of: $1) }
        switch mode {
        case .raw:
            let lines = cleaned.segments.compactMap { segment -> OffTrackLine? in
                guard let start = segment.points.first?.time, let end = segment.points.last?.time else { return nil }
                return OffTrackLine(
                    coordinates: segment.points.map(\.coordinate), start: start, elapsed: end.timeIntervalSince(start),
                    length: Self.length(of: segment))
            }
            return ImportedActivity(
                activity: record, legs: [], offTrack: lines, length: length, matchedLength: 0, lengthByClass: [:],
                droppedSegments: cleaned.droppedSegments)
        case .matched:
            let matched = TrackMatcher.match(cleaned, on: network, rules: matching)
            let legs = try TrackLegs.legs(
                of: matched, from: cleaned, in: network, minimumConfidence: minimumConfidence, minimumStretchLength: minimumStretchLength)
            let lines = try OffTrackLines.lines(of: matched, from: cleaned)
            return ImportedActivity(
                activity: record, legs: legs, offTrack: lines, length: length, matchedLength: matched.length - matched.unmatchedLength,
                lengthByClass: matched.lengthByClass, droppedSegments: cleaned.droppedSegments)
        }
    }

    /// Makes an activity ready and adds it to the store; an activity with the same id is replaced.
    ///
    /// Runs off the main actor.
    ///
    /// - Returns: What was added.
    /// - Throws: ``TrackStoreError``, or what ``prepare(_:category:mode:)`` throws; the store is not changed then.
    @concurrent
    @discardableResult
    public func add(_ activity: ActivityTrack, category: String, mode: ImportMode, to store: TrackStore) async throws -> ImportedActivity {
        let imported = try prepare(activity, category: category, mode: mode)
        try await store.add(imported.activity, legs: imported.legs, offTrack: imported.offTrack)
        return imported
    }

    private static func length(of segment: TrackSegment) -> Double {
        zip(segment.points, segment.points.dropFirst()).reduce(0) { $0 + $1.0.coordinate.distance(to: $1.1.coordinate) }
    }
}
