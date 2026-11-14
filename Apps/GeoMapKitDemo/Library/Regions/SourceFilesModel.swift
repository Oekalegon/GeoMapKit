import FeatureStore
import Foundation
import Observation
import Regions

/// The downloaded source files of the app: what is in the cache, which maps were built from each file, and deleting them (question 63).
///
/// A built map does not read its source files again, so a file can go without changing any map; Build again, Add a region and a new
/// map download what they need. The model knows no platform and no screen.
@MainActor
@Observable
final class SourceFilesModel {
    /// One thing in the cache.
    struct File: Identifiable, Equatable {
        enum State: Equatable {
            /// A usable file.
            case file(downloadedAt: Date, checkedAt: Date)
            /// A file or record that cannot be used, with the reason.
            case damaged(String)
            /// The bytes of a download that did not finish.
            case unfinished
        }

        /// The cache entry's identity (a region can have a file and an unfinished download).
        let id: String
        let regionID: String
        /// The region as the user knows it.
        let name: String
        let state: State
        let bytes: Int64
        /// The names of the maps of this app that were built from the file, sorted.
        let usedBy: [String]
    }

    /// Why a delete was refused.
    enum Failure: Error, LocalizedError, Equatable {
        case busy
        var errorDescription: String? { "A map is being built, and the build reads and writes these files. Wait for it, or dismiss its result." }
    }

    /// What is in the cache, by region name.
    private(set) var files: [File] = []
    private(set) var isLoading = false
    /// The free space on the volume of the cache, if the system says.
    private(set) var availableBytes: Int64?
    /// Whether a map of the app has blocks that do not record their source files (it was built before they were recorded): a file
    /// that is listed as used by no map can be in use by that map.
    private(set) var someMapsDoNotRecordSources = false

    private let cache: SourceCache
    private let mapsRoot: URL?
    private let name: @MainActor (String) -> String

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - cache: The source cache of the app.
    ///   - mapsRoot: The folder the app builds its maps in; the manifests of its folders say which files each map was built from. `nil`
    ///     if the app builds none.
    ///   - name: The name of a region by its id (the id itself if it is not known).
    init(cache: SourceCache, mapsRoot: URL?, name: @escaping @MainActor (String) -> String) {
        self.cache = cache
        self.mapsRoot = mapsRoot
        self.name = name
    }

    /// The bytes the files take.
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    /// What "delete unused" would remove: usable files no map was built from, files that cannot be used, and unfinished downloads.
    var unused: [File] {
        files.filter { file in
            if case .file = file.state { return file.usedBy.isEmpty }
            return true
        }
    }

    /// Reads the cache and the manifests again.
    ///
    /// - Parameter mapNames: The names of the maps in the library by the name of their folder; a folder that is not in the library
    ///   (its map was removed from it) is named after the folder.
    func reload(mapNames: [String: String] = [:]) async {
        isLoading = true
        defer { isLoading = false }
        let cache = cache, root = mapsRoot
        let (entries, found) = await Task.detached { (cache.entries(), Self.usage(in: root, names: mapNames)) }.value
        let usage = found.byRegion
        someMapsDoNotRecordSources = found.unrecorded
        files = entries.map { entry in
            let state: File.State
            switch entry.kind {
            case .file(let record): state = .file(downloadedAt: record.downloadedAt, checkedAt: record.checkedAt)
            case .damaged(let reason): state = .damaged(reason)
            case .unfinished: state = .unfinished
            }
            return File(
                id: entry.id, regionID: entry.regionID, name: name(entry.regionID), state: state, bytes: entry.bytes,
                usedBy: usage[entry.regionID] ?? [])
        }
        .sorted { first, second in
            let order = first.name.localizedStandardCompare(second.name)
            return order == .orderedSame ? first.id < second.id : order == .orderedAscending
        }
        availableBytes = cache.availableBytes()
    }

    /// Deletes one entry: a usable file with its record, a damaged one, or an unfinished download. Each leaves the others of the same
    /// region alone, because they are listed, sized and deleted one by one.
    ///
    /// - Parameters:
    ///   - file: The entry.
    ///   - isBusy: Whether a build is running or its result is shown.
    /// - Throws: ``Failure/busy``, or the error of the file system.
    func delete(_ file: File, isBusy: Bool) throws {
        guard !isBusy else { throw Failure.busy }
        if case .unfinished = file.state {
            try cache.removeUnfinished(regionID: file.regionID)
        } else {
            try cache.remove(regionID: file.regionID, includingUnfinished: false)
        }
    }

    /// Deletes everything in ``unused``.
    ///
    /// - Parameter isBusy: Whether a build is running or its result is shown.
    /// - Returns: The bytes that were freed.
    /// - Throws: ``Failure/busy``, or the first error of the file system.
    @discardableResult
    func deleteUnused(isBusy: Bool) throws -> Int64 {
        guard !isBusy else { throw Failure.busy }
        var freed: Int64 = 0
        for file in unused {
            try delete(file, isBusy: false)
            freed += file.bytes
        }
        return freed
    }

    /// The maps built from each source file, by region id: read from the manifests of the folders of `root`, and whether a manifest
    /// has blocks that record no source.
    nonisolated static func usage(in root: URL?, names: [String: String]) -> (byRegion: [String: [String]], unrecorded: Bool) {
        guard let root, let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return ([:], false) }
        var usage: [String: [String]] = [:]
        var unrecorded = false
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                let manifest = try? StoreManifest(json: data)
            else { continue }
            let mapName = names[folder.lastPathComponent] ?? folder.lastPathComponent
            if manifest.blocks.contains(where: { $0.sources.isEmpty }) { unrecorded = true }
            for id in Set(manifest.blocks.flatMap(\.sources).map(\.regionID)) { usage[id, default: []].append(mapName) }
        }
        return (usage.mapValues { $0.sorted() }, unrecorded)
    }
}
