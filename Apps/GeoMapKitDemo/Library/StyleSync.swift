import Foundation
import Observation
import os

/// Keeps the styles in the app's iCloud folder when the user wants it and it is there, and watches the folder for changes from other devices.
///
/// `start()` finds the iCloud container (off the main thread: the call can take seconds), copies the local styles into it once
/// (``StyleMigration``), switches the library to it, and starts a metadata query on the folder. When the query reports a change, files that
/// are only placeholders are downloaded, conflicting versions are resolved with ``StyleConflictRule`` and the library reads the folder again.
/// Without an iCloud account, or in a build without the iCloud entitlement, the container is `nil`, nothing changes and the status says so.
@MainActor
@Observable
final class StyleSync {
    /// Where things stand.
    enum Status: Equatable {
        /// Not started, or the user has turned iCloud off.
        case off
        /// Looking for the container and copying the local styles.
        case preparing
        /// There is no iCloud container: not signed in, iCloud Drive is off, or this build has no iCloud entitlement.
        case unavailable
        /// Files are being downloaded or uploaded.
        case syncing
        /// Everything is up to date.
        case upToDate
        /// Something went wrong; the text says what.
        case failed(String)

        /// A sentence for the library screen.
        var sentence: String {
            switch self {
            case .off: "Styles are kept on this device only."
            case .preparing: "Setting up iCloud…"
            case .unavailable: "iCloud is not available (sign in to iCloud and turn on iCloud Drive for this app). Styles are kept on this device."
            case .syncing: "Syncing styles with iCloud…"
            case .upToDate: "Styles are in iCloud and up to date."
            case .failed(let reason): "iCloud: \(reason)"
            }
        }
    }

    private static let enabledKey = "stylesInICloud"

    /// Whether the user wants the styles in iCloud (on unless turned off). Setting it starts or stops the sync.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if newValue { start() } else { stop() }
        }
    }

    private(set) var status: Status = .off
    /// What the last copy of the local styles into iCloud did, for the library screen.
    private(set) var migration: StyleMigration.Result?

    private let library: MapLibrary
    private let localRoot: URL
    private let containerIdentifier: String?
    private let defaults: UserDefaults
    private var query: NSMetadataQuery?
    /// The setup that is under way (finding the container, migrating); `start()` does nothing while there is one, and `stop()` cancels it.
    private var setup: Task<Void, Never>?
    private static let log = Logger(subsystem: "org.oekalegon.GeoMapKitDemo", category: "StyleSync")
    private var observers: [NSObjectProtocol] = []

    /// Creates the sync for a library.
    /// - Parameters:
    ///   - library: The library whose styles are kept.
    ///   - localRoot: The library's folder on this device (its `Styles` folder is the local copy).
    ///   - containerIdentifier: The iCloud container, or `nil` for the app's default one.
    init(library: MapLibrary, localRoot: URL = URL.documentsDirectory, containerIdentifier: String? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.library = library
        self.localRoot = localRoot
        self.containerIdentifier = containerIdentifier
    }

    /// Turns iCloud on: finds the container, migrates, switches the library and watches the folder.
    func start() {
        guard query == nil, setup == nil else { return }
        status = .preparing
        let identifier = containerIdentifier, root = localRoot
        setup = Task {
            defer { setup = nil }
            // `url(forUbiquityContainerIdentifier:)` can block for seconds: ask on a background thread.
            let container = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: identifier) }.value
            guard !Task.isCancelled else { return }
            let folder = StyleFolder.resolve(root: root, useICloud: true, ubiquityContainer: container)
            guard folder.place == .iCloud else {
                status = .unavailable
                return
            }
            let local = root.appendingPathComponent("Styles", isDirectory: true)
            let result = await Task.detached { StyleMigration.copyMissing(from: local, to: folder.url) }.value
            // Turned off while the styles were being copied: the copies stay (they are only copies) and nothing is switched.
            guard !Task.isCancelled else { return }
            migration = result
            library.useStylesDirectory(folder.url)
            watch(folder.url)
        }
    }

    /// Turns iCloud off: the library goes back to the local folder (the styles that are only in iCloud stay there and are not copied back).
    func stop() {
        setup?.cancel()
        setup = nil
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        library.useStylesDirectory(localRoot.appendingPathComponent("Styles", isDirectory: true))
        status = .off
    }

    // MARK: Watching

    private func watch(_ folder: URL) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.queryChanged(folder: folder) }
            })
        }
        self.query = query
        query.start()
        status = .syncing
    }

    private func queryChanged(folder: URL) {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var pending = false
        var matched = 0
        // The container can be reported as /var/… by one call and /private/var/… by another: compare with the links resolved.
        let here = folder.resolvingSymlinksInPath().path
        var toResolve: [URL] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL, url.deletingLastPathComponent().resolvingSymlinksInPath().path == here else { continue }
            matched += 1
            let state = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if state != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                // Only the name is here: ask the system for the contents (it reports again when they have arrived).
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                pending = true
            } else if (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) == true {
                toResolve.append(url)
            }
            if (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool) == true { pending = true }
        }
        if matched == 0, query.resultCount > 0 {
            Self.log.error("the query found \(query.resultCount) files and none in \(here, privacy: .public)")
        }
        status = pending || !toResolve.isEmpty ? .syncing : .upToDate
        library.reload()
        if !toResolve.isEmpty { resolve(toResolve) }
    }

    /// Resolves the conflicts of some files off the main thread (the coordinator can wait for iCloud), then reads the folder again.
    private func resolve(_ urls: [URL]) {
        Task {
            let problems = await Task.detached { urls.compactMap { Self.resolveConflicts(at: $0) } }.value
            status = problems.first.map { .failed($0) } ?? .upToDate
            library.reload()
        }
    }

    /// Keeps the newest version of a style as the file and the others as copies beside it (see ``StyleConflictRule``).
    ///
    /// - Returns: A sentence for the status if the conflict could not be resolved, otherwise `nil`.
    nonisolated private static func resolveConflicts(at url: URL) -> String? {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else { return nil }
        let currentDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let conflicts = versions.enumerated().map { (id: $0.offset, modified: $0.element.modificationDate ?? .distantPast) }
        let plan = StyleConflictRule.plan(current: currentDate, conflicts: conflicts)
        let folder = url.deletingLastPathComponent()
        var existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        do {
            // Save every version that does not win under a name of its own, before anything is replaced.
            for copy in plan.copies {
                let data = try copy.id.map { try CoordinatedFiles.read(versions[$0].url) } ?? CoordinatedFiles.read(url)
                let name = StyleConflictRule.copyName(of: url.lastPathComponent, modified: copy.modified, existing: existing)
                existing.insert(name)
                try CoordinatedFiles.write(data, to: folder.appendingPathComponent(name))
            }
            if let id = plan.winner.id { try CoordinatedFiles.write(try CoordinatedFiles.read(versions[id].url), to: url) }
            for version in versions { version.isResolved = true }
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
            return nil
        } catch {
            return "a conflict in \(url.lastPathComponent) could not be resolved (\(error.localizedDescription))"
        }
    }
}
