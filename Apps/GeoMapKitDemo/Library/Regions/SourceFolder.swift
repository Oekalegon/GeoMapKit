#if os(macOS)
import Foundation
import Synchronization

/// The folder of the source files that the user chose, kept as a security-scoped bookmark so that the sandbox lets the app in again at
/// every start (question 63).
///
/// The files are the same ones the command-line tool uses (`~/Library/Application Support/GeoMapKit/Sources`), which the sandboxed app
/// cannot see by itself; with the folder chosen, the app and the tool share one cache. Without a choice the app uses the folder of its own container.
struct SourceFolder {
    /// What the choice is now.
    enum State: Equatable {
        /// No folder was chosen: the app uses the folder of its own container.
        case own
        /// The chosen folder, opened for the sandbox.
        case chosen(URL)
        /// A folder was chosen, but it cannot be reached now (it was moved or deleted, or its disk is not there). The choice is kept.
        case unavailable
    }

    /// Why a folder cannot be used.
    struct NotWritable: Error, LocalizedError {
        let path: String
        var errorDescription: String? { "The app cannot write in “\(path)”: choose another folder." }
    }

    private let defaults: UserDefaults
    private let key = "sourceFolderBookmark"
    /// The folders whose access was started in this run: each is opened once, and stays open while the app runs.
    private static let started = Mutex<Set<String>>([])

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The state of the choice; a folder that is chosen is opened for the sandbox.
    var state: State {
        guard let data = defaults.data(forKey: key) else { return .own }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
            Self.open(url)
        else { return .unavailable }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: key)
        }
        return .chosen(url)
    }

    /// The folder the user chose, or `nil` for no choice or one that cannot be reached.
    func resolve() -> URL? {
        if case .chosen(let url) = state { return url }
        return nil
    }

    /// Whether a folder was chosen (also when it cannot be reached now).
    var isChosen: Bool { defaults.data(forKey: key) != nil }

    /// Keeps a folder that the user picked as the folder of the source files.
    ///
    /// - Parameter url: The folder, from an open panel.
    /// - Throws: ``NotWritable`` when files cannot be made in it; the error of the bookmark when the folder cannot be remembered.
    func choose(_ url: URL) throws {
        _ = Self.open(url)
        // The folder is tried with a file: the first download must not be the one to find out.
        let probe = url.appendingPathComponent(".geomapkit-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch {
            throw NotWritable(path: url.path)
        }
        defaults.set(try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: key)
    }

    /// Goes back to the folder of the app's own container.
    func reset() { defaults.removeObject(forKey: key) }

    /// Opens a folder for the sandbox, once for each path while the app runs.
    private static func open(_ url: URL) -> Bool {
        started.withLock { opened in
            if opened.contains(url.path) { return true }
            guard url.startAccessingSecurityScopedResource() else { return false }
            opened.insert(url.path)
            return true
        }
    }
}
#endif
