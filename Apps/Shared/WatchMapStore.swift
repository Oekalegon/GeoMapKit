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
    /// The maps would take more room than the Watch keeps for them.
    case noRoom(bytes: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case .notAStore(let reason): "The file that arrived is not a map the Watch can use: \(reason)"
        case .noRoom(let bytes, let limit):
            "The maps would be \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), more than the Watch keeps "
                + "(\(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))). Remove a map first."
        }
    }
}

/// The maps on the Watch: store files in `Maps/` in the Documents of the app. The phone sends them; the Watch only reads them.
///
/// The type is plain Foundation, so that the phone's test target can test it too.
struct WatchMapStore: Sendable {
    /// The most bytes all maps together may take on the Watch. Provisional, until the Watch storage ceiling is known (question 39).
    static let totalLimit: Int64 = 60_000_000

    let directory: URL
    let totalLimit: Int64

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - directory: The folder of the maps; created when the first map arrives.
    ///   - totalLimit: The most bytes all maps together may take.
    init(directory: URL, totalLimit: Int64 = WatchMapStore.totalLimit) {
        self.directory = directory
        self.totalLimit = totalLimit
    }

    /// The store in the Documents of the app.
    static var standard: WatchMapStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return WatchMapStore(directory: documents.appendingPathComponent("Maps", isDirectory: true))
    }

    /// A name that is a file name here: no folders, no hidden file, the `.gmk` extension, at most 80 bytes before the extension.
    /// Two names that differ only in `/`, `:` or what was cut off give the same file name, and the later map replaces the earlier.
    static func fileName(for name: String) -> String {
        var base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if base.lowercased().hasSuffix(".gmk") { base.removeLast(4) }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Map" }
        var cut = ""
        for character in base {
            if cut.utf8.count + String(character).utf8.count > 80 { break }
            cut.append(character)
        }
        return cut + ".gmk"
    }

    /// Checks a file that arrived and moves it into the store.
    ///
    /// A file with the same name is replaced (in one step, so the old map stays if the new one cannot be put in place), since the
    /// phone sends a new copy of a map under the same name.
    ///
    /// - Parameters:
    ///   - file: The file that arrived. It is moved, and gone from where it was.
    ///   - name: The name the phone gave it.
    ///   - fullCheck: Whether the file is read completely (checksum and every cell). The Watch passes `false`: it opens the file and
    ///     checks its structure, and the phone has checked the whole file before it sent it.
    /// - Returns: The entry of the map.
    /// - Throws: ``WatchMapStoreError/notAStore(_:)`` if the file is not a valid store (the file is deleted then), and
    ///   ``WatchMapStoreError/noRoom(bytes:limit:)`` if the maps would take more than the limit.
    @discardableResult
    func accept(_ file: URL, named name: String, fullCheck: Bool = true) throws -> WatchMapEntry {
        do {
            let store = try FeatureStoreFile(contentsOf: file)
            if fullCheck { try store.verify() }
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw WatchMapStoreError.notAStore("\(error)")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(Self.fileName(for: name))
        let incoming = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let others = list().filter { $0.url.lastPathComponent != target.lastPathComponent }.reduce(Int64(0)) { $0 + $1.bytes }
        guard others + incoming <= totalLimit else {
            try? FileManager.default.removeItem(at: file)
            throw WatchMapStoreError.noRoom(bytes: others + incoming, limit: totalLimit)
        }
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: file)
        } else {
            try FileManager.default.moveItem(at: file, to: target)
        }
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
