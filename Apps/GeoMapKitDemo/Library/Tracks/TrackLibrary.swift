import Foundation
import GeoCore
import Observation
import TrackOverlays
import Tracks

/// The GPX files the user has added, which of them are shown on the map, and what the map needs to draw them.
///
/// The files are copied into a folder `Tracks` next to the maps and styles of the library. A file is read when it is added (a file that
/// is not GPX, or has no track or route, is refused with the reason and the line), and again to show it: the routes of a file are kept in
/// memory only while it is shown. The choice of what to show is remembered.
@MainActor
@Observable
final class TrackLibrary {
    /// A request to fit the map to a box, from the library; the map follows it once.
    struct Fit: Equatable {
        let id = UUID()
        let box: BoundingBox
    }

    /// The tracks, by name.
    private(set) var items: [TrackItem] = []
    /// The ids of the tracks that are shown.
    private(set) var visible: Set<String>
    /// What was found in each file that has been read.
    private(set) var summaries: [String: TrackSummary] = [:]
    /// Why a file could not be read now (it was changed or damaged outside the app).
    private(set) var failures: [String: String] = [:]
    /// The latest request to fit the map to a track.
    private(set) var fit: Fit?

    /// The folder of the GPX files.
    let directory: URL
    private let defaults: UserDefaults
    private static let visibleKey = "visibleTracks"
    /// The overlays of the tracks that are shown and have been read.
    private var loaded: [String: [RouteOverlay]] = [:]

    /// Opens the library in a folder: the Documents of the app, or another folder (tests use a new one).
    init(root: URL = URL.documentsDirectory, defaults: UserDefaults = .standard) {
        directory = root.appendingPathComponent("Tracks", isDirectory: true)
        self.defaults = defaults
        visible = Set(defaults.stringArray(forKey: Self.visibleKey) ?? [])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        Task { await loadVisible() }
    }

    /// The overlays of the tracks that are shown, in the order of the list, for the map view.
    var overlays: [RouteOverlay] { items.filter { visible.contains($0.id) }.flatMap { loaded[$0.id] ?? [] } }

    /// Where a track is.
    func url(of item: TrackItem) -> URL { directory.appendingPathComponent(item.id) }

    // MARK: Reading the folder

    /// Reads the folder again. What is shown and what was read is dropped for files that are gone.
    func reload() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        items = urls.filter { $0.pathExtension.lowercased() == "gpx" }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return TrackItem(
                id: url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent, bytes: Int64(values?.fileSize ?? 0),
                date: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let ids = Set(items.map(\.id))
        let missing = visible.subtracting(ids)
        if !missing.isEmpty { visible.subtract(missing); remember() }
        summaries = summaries.filter { ids.contains($0.key) }
        failures = failures.filter { ids.contains($0.key) }
        loaded = loaded.filter { ids.contains($0.key) }
    }

    // MARK: Adding and removing

    /// Adds GPX files: each is read first, then copied into the library, shown and fitted on the map.
    ///
    /// - Parameter urls: The files the user picked.
    /// - Returns: The ids of the tracks that were added, and one error for each file that could not be added.
    @discardableResult
    func add(_ urls: [URL]) async -> (added: [String], errors: [LibraryError]) {
        var added: [String] = []
        var errors: [LibraryError] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard url.pathExtension.lowercased() == "gpx" else { errors.append(.failed(name, "it is not a GPX file (.gpx)")); continue }
            do {
                let read = try await Self.read(url)
                let target = uniqueURL(name: url.deletingPathExtension().lastPathComponent)
                try FileManager.default.copyItem(at: url, to: target)
                added.append(target.lastPathComponent)
                summaries[target.lastPathComponent] = read.summary
                visible.insert(target.lastPathComponent)
                loaded[target.lastPathComponent] = read.overlays
            } catch let error as LibraryError {
                errors.append(error)
            } catch {
                errors.append(.failed(name, error.localizedDescription))
            }
        }
        reload()
        remember()
        if let first = added.first, let box = summaries[first]?.box { requestFit(box) }
        return (added, errors)
    }

    /// Removes a track and its copy of the file.
    func delete(_ item: TrackItem) throws {
        try FileManager.default.removeItem(at: url(of: item))
        visible.remove(item.id)
        summaries[item.id] = nil
        failures[item.id] = nil
        loaded[item.id] = nil
        remember()
        reload()
    }

    private func uniqueURL(name: String) -> URL {
        var candidate = directory.appendingPathComponent("\(name).gpx")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(number).gpx")
            number += 1
        }
        return candidate
    }

    // MARK: Showing

    /// Shows or hides a track. Showing reads the file if that has not been done.
    func setVisible(_ item: TrackItem, _ on: Bool) async {
        if on { visible.insert(item.id) } else { visible.remove(item.id); loaded[item.id] = nil }
        remember()
        if on { await load(item) }
    }

    /// Asks the map to fit a box (a track).
    func requestFit(_ box: BoundingBox) { fit = Fit(box: box) }

    /// Reads the files of the tracks that are shown (after a start), and the summaries of the rest, one file at a time.
    func loadVisible() async {
        for item in items where visible.contains(item.id) { await load(item) }
    }

    /// Reads the summaries of the files that have none, one at a time, so the list can show lengths and dates.
    func loadSummaries() async {
        for item in items where summaries[item.id] == nil && failures[item.id] == nil { await load(item) }
    }

    private func load(_ item: TrackItem) async {
        guard loaded[item.id] == nil || summaries[item.id] == nil else { return }
        do {
            let read = try await Self.read(url(of: item))
            summaries[item.id] = read.summary
            failures[item.id] = nil
            // The routes are kept only for a track that is shown, and only if it still is when the file has been read.
            if visible.contains(item.id) { loaded[item.id] = read.overlays }
        } catch {
            failures[item.id] = error.localizedDescription
        }
    }

    private func remember() { defaults.set(visible.sorted(), forKey: Self.visibleKey) }

    // MARK: Reading a file

    private struct Read: Sendable {
        let summary: TrackSummary
        let overlays: [RouteOverlay]
    }

    /// Reads a GPX file off the main thread: what can be drawn, and what it holds.
    private nonisolated static func read(_ url: URL) async throws -> Read {
        try await Task.detached(priority: .userInitiated) {
            let name = url.lastPathComponent
            let file: GPXFile
            do { file = try GPXFile(contentsOf: url) } catch { throw LibraryError.failed(name, error.localizedDescription) }
            var summary = TrackSummary()
            var overlays: [RouteOverlay] = []
            func add(_ make: () throws -> Route, label: String?) {
                do {
                    var route = try make()
                    route.waypoints = file.waypoints(near: route)
                    overlays.append(RouteOverlay(route: route))
                    summary.lines += 1
                    summary.points += route.points.count
                    summary.length += route.length
                    summary.box = summary.box.map { union($0, route.boundingBox) } ?? route.boundingBox
                } catch {
                    summary.problems.append("\(label ?? "a track"): \(error.localizedDescription)")
                }
            }
            for track in file.tracks where !track.points.isEmpty {
                add({ try track.route() }, label: track.name)
                if let activity = try? track.activity() {
                    summary.activities += 1
                    summary.startDate = min(summary.startDate ?? activity.startDate, activity.startDate)
                }
            }
            for route in file.routes where !route.points.isEmpty { add({ try route.route() }, label: route.name) }
            guard !overlays.isEmpty else {
                throw LibraryError.failed(name, summary.problems.first ?? "it has no track or route")
            }
            return Read(summary: summary, overlays: overlays)
        }.value
    }
}

private func union(_ a: BoundingBox, _ b: BoundingBox) -> BoundingBox {
    BoundingBox(south: min(a.south, b.south), west: min(a.west, b.west), north: max(a.north, b.north), east: max(a.east, b.east))
}
