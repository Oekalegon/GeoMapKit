import Foundation
import Tracks

/// Something to import: a name to report it by, and a way to read the activities in it when its turn comes.
///
/// Reading is done late and inside the run, so a thousand files are not all in memory at once.
public struct ImportRequest: Sendable {
    /// What was read from a request.
    public struct Loaded: Sendable {
        /// The activities.
        public var activities: [ActivityTrack]
        /// What in the source was not an activity, each with the reason (a route with no times).
        public var problems: [String]

        /// Creates the result of reading.
        public init(activities: [ActivityTrack], problems: [String] = []) {
            self.activities = activities
            self.problems = problems
        }
    }

    /// The name that failures and progress are reported with (a file name).
    public let source: String
    /// Reads the activities.
    public let load: @Sendable () throws -> Loaded

    /// Creates a request.
    public init(source: String, load: @escaping @Sendable () throws -> Loaded) {
        self.source = source
        self.load = load
    }

    /// A GPX file: each of its tracks that is an activity (points with times, in order) is one; the rest are problems that are reported.
    ///
    /// The tags of an activity are the ones ``GPXTrack/activity(id:tags:rules:)`` makes (`gpx.name`, `gpx.type`), and `gpx.file`, the
    /// name of the file. **These tags are stored with the activity** (the name of a track and of a file can be personal; an export must
    /// leave them out or let the app filter them).
    ///
    /// - Parameters:
    ///   - url: The file. The app is responsible for access to it (a copy in its own folder, or security-scoped access held).
    ///   - rules: What makes a track an activity.
    public static func gpx(at url: URL, rules: ActivityRules = .standard) -> ImportRequest {
        let name = url.lastPathComponent
        return ImportRequest(source: name) {
            let file = try GPXFile(contentsOf: url)
            var loaded = Loaded(activities: [])
            for track in file.tracks where !track.points.isEmpty {
                do {
                    loaded.activities.append(try track.activity(tags: ["gpx.file": .string(name)], rules: rules))
                } catch {
                    loaded.problems.append("\(track.name ?? "a track"): \(error.localizedDescription)")
                }
            }
            for route in file.routes where !route.points.isEmpty { loaded.problems.append("\(route.name ?? "a route"): a planned route has no times.") }
            return loaded
        }
    }
}
