import FeatureStore
import Foundation
import GeoCore

/// One map held on the Watch.
struct WatchMapEntry: Identifiable, Hashable, Sendable {
    /// The file name with its extension: unique in the store.
    let id: String
    /// What is shown: the file name without its extension.
    let name: String
    let bytes: Int64
    let date: Date
    let url: URL
}

/// Why a map that arrived could not be kept.
enum WatchMapStoreError: Error, Equatable, LocalizedError {
    case notAStore(String)

    var errorDescription: String? {
        switch self {
        case .notAStore(let reason): "The file that arrived is not a map the Watch can use: \(reason)"
        }
    }
}

/// The maps on the Watch: store files in `Maps/` in the Documents of the app. The phone sends them; the Watch only reads them.
///
/// The type is plain Foundation, so that the phone's test target can test it too.
struct WatchMapStore: Sendable {
    let directory: URL

    /// Creates a store.
    ///
    /// - Parameter directory: The folder of the maps; created when the first map arrives.
    init(directory: URL) { self.directory = directory }

    /// The store in the Documents of the app.
    static var standard: WatchMapStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return WatchMapStore(directory: documents.appendingPathComponent("Maps", isDirectory: true))
    }

    /// A name that is a file name here: no folders, no hidden file, the `.gmk` extension.
    static func fileName(for name: String) -> String {
        var base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if base.lowercased().hasSuffix(".gmk") { base.removeLast(4) }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Map" }
        return String(base.prefix(80)) + ".gmk"
    }

    /// Checks a file that arrived and moves it into the store.
    ///
    /// The file is read completely (its checksum is checked), so that a damaged file is refused here and not when the map is opened.
    /// A file with the same name is replaced, since the phone sends a new copy of a map under the same name.
    ///
    /// - Parameters:
    ///   - file: The file that arrived. It is moved, and gone from where it was.
    ///   - name: The name the phone gave it.
    /// - Returns: The entry of the map.
    /// - Throws: ``WatchMapStoreError/notAStore(_:)`` if the file is not a valid store; the file is deleted then.
    @discardableResult
    func accept(_ file: URL, named name: String) throws -> WatchMapEntry {
        do {
            let store = try FeatureStoreFile(contentsOf: file)
            try store.verify()
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw WatchMapStoreError.notAStore("\(error)")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(Self.fileName(for: name))
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: file, to: target)
        return try entry(at: target)
    }

    /// The maps, newest first.
    func list() -> [WatchMapEntry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "gmk" }.compactMap { try? entry(at: $0) }.sorted { $0.date > $1.date }
    }

    /// Removes a map.
    func delete(_ entry: WatchMapEntry) throws {
        try FileManager.default.removeItem(at: entry.url)
    }

    private func entry(at url: URL) throws -> WatchMapEntry {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return WatchMapEntry(
            id: url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent, bytes: Int64(values.fileSize ?? 0),
            date: values.contentModificationDate ?? .distantPast, url: url)
    }

    /// Where to look first in a map: the middle of its box, at a zoom the Watch style draws.
    static func start(of file: FeatureStoreFile) -> (center: Coordinate, zoom: Double) {
        let box = file.boundingBox
        return (Coordinate(latitude: (box.south + box.north) / 2, longitude: (box.west + box.east) / 2), 13)
    }
}
