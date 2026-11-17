#if os(macOS)
import Foundation

/// The folder of the source files that the user chose, kept as a security-scoped bookmark so that the sandbox lets the app in again at
/// every start (question 63).
///
/// The files are the same ones the command-line tool uses (`~/Library/Application Support/GeoMapKit/Sources`), which the sandboxed app
/// cannot see by itself; with the folder chosen, the app and the tool share one cache. Without a choice the app uses the folder of its own container.
struct SourceFolder {
    private let defaults: UserDefaults
    private let key = "sourceFolderBookmark"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The folder the user chose, opened for the sandbox (and kept open while the app runs), or `nil` for no choice or a bookmark that
    /// no longer leads anywhere (the folder was moved or deleted).
    func resolve() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
            url.startAccessingSecurityScopedResource()
        else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: key)
        }
        return url
    }

    /// Keeps a folder that the user picked as the folder of the source files.
    ///
    /// - Parameter url: The folder, from an open panel.
    /// - Throws: The error of the bookmark when the folder cannot be remembered.
    func choose(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        defaults.set(try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: key)
    }

    /// Goes back to the folder of the app's own container.
    func reset() { defaults.removeObject(forKey: key) }

    /// Whether a folder was chosen.
    var isChosen: Bool { defaults.data(forKey: key) != nil }
}
#endif
