import FeatureStore
import Foundation
import GeoCore
import MapStyle
import Observation

/// The maps and styles the user has stored, and which of them is selected.
///
/// Everything is a file in two folders, `Maps` and `Styles`, in the app's Documents (which the Files app and Finder can see, so
/// files can be dropped in and taken out): a map is a `.gmk` store file that was copied in, or a `.maplink` file that holds a bookmark
/// to a folder of blocks that stays where it is; a style is a `.json` file the kit can read. The lists are read from the folders, so
/// a file that is added or removed outside the app shows up on the next `reload()`. Only the selection is kept elsewhere
/// (`UserDefaults`).
@MainActor
@Observable
final class MapLibrary {
    /// The maps, by name.
    private(set) var maps: [MapItem] = []
    /// The styles of the user, by name.
    private(set) var styles: [StyleItem] = []
    /// A style the library screen asks the map screen to open in the style editor (the map screen has the map to preview it on).
    var styleToEdit: String?
    /// Counts every change of the lists or of a choice of style, so that a view that reads it is drawn again.
    private(set) var revision = 0
    /// The map that is shown, as the id of its item.
    var selectedMapID: String? {
        didSet { defaults.set(selectedMapID, forKey: Keys.map) }
    }

    let mapsDirectory: URL
    /// The folder of the styles: the local one, or the one in iCloud once ``StyleSync`` has switched to it.
    private(set) var stylesDirectory: URL
    private let defaults: UserDefaults

    private enum Keys {
        static let map = "selectedMap"
        static let styles = "styleByMap"
        static let fallbackStyle = "style"
    }

    /// The extension of the files that link to a folder of blocks or to a big file.
    static let linkExtension = "maplink"

    /// A store file bigger than this is linked and not copied: a copy would take long on the main thread and use the space twice.
    /// Smaller files (the maps of one run are some ten megabytes) are copied, which is quick.
    var copyLimit: Int64 = 100_000_000

    /// What `add(_:)` did.
    struct AddResult {
        /// The ids of the maps that were added, in the order of the items given.
        var maps: [String] = []
        /// The ids of the styles that were added.
        var styles: [String] = []
        /// One error for each item that could not be added.
        var errors: [LibraryError] = []
    }

    /// Opens the library in a folder: the Documents of the app, or another folder (tests use a new one). The styles are in that folder's
    /// `Styles`, or in `stylesDirectory` (a folder in the app's iCloud container, see ``StyleFolder``).
    init(root: URL = URL.documentsDirectory, stylesDirectory: URL? = nil, defaults: UserDefaults = .standard) {
        mapsDirectory = root.appendingPathComponent("Maps", isDirectory: true)
        self.stylesDirectory = stylesDirectory ?? root.appendingPathComponent("Styles", isDirectory: true)
        self.defaults = defaults
        for folder in [mapsDirectory, self.stylesDirectory] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        selectedMapID = defaults.string(forKey: Keys.map)
        reload()
    }

    // MARK: Reading the folders

    /// Reads the two folders again.
    func reload() {
        maps = Self.items(in: mapsDirectory).compactMap { url, values in
            let ext = url.pathExtension.lowercased()
            guard ext == "gmk" || ext == Self.linkExtension else { return nil }
            let kind: MapItem.Kind = ext == "gmk" ? .file : (Self.linkKind(at: url) == .file ? .linkedFile : .blocks)
            return MapItem(
                id: url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent, kind: kind,
                bytes: ext == "gmk" ? Int64(values.fileSize ?? 0) : nil, date: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        styles = Self.items(in: stylesDirectory).compactMap { url, values in
            guard url.pathExtension.lowercased() == "json" else { return nil }
            return StyleItem(id: url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent, date: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let selectedMapID, !maps.contains(where: { $0.id == selectedMapID }) { self.selectedMapID = nil }
        // Something to look at: the first map, when none is chosen.
        if selectedMapID == nil, let first = maps.first { selectedMapID = first.id }
        revision += 1
    }

    private static func items(in folder: URL) -> [(URL, URLResourceValues)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in (try? url.resourceValues(forKeys: keys)).map { (url, $0) } }
    }

    /// Keeps the styles in another folder from now on (the one in iCloud), and reads it.
    func useStylesDirectory(_ folder: URL) {
        guard folder != stylesDirectory else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        stylesDirectory = folder
        reload()
    }

    func url(of map: MapItem) -> URL { mapsDirectory.appendingPathComponent(map.id) }
    func url(of style: StyleItem) -> URL { stylesDirectory.appendingPathComponent(style.id) }

    // MARK: Adding

    /// Adds what the user picked: a `.gmk` store file (copied), a folder of blocks (linked, not copied) or a style (copied, after it was
    /// read as a style).
    ///
    /// - Returns: The ids of what was added and one error for each item that could not be added; the others were added.
    @discardableResult
    func add(_ urls: [URL]) -> AddResult {
        var result = AddResult()
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let added = try add(url)
                if added.hasSuffix(".json") { result.styles.append(added) } else { result.maps.append(added) }
            } catch let error as LibraryError {
                result.errors.append(error)
            } catch {
                result.errors.append(.failed(url.lastPathComponent, error.localizedDescription))
            }
        }
        reload()
        return result
    }

    /// Adds one item and returns the file name it has in the library.
    private func add(_ url: URL) throws -> String {
        let name = url.lastPathComponent
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if isFolder {
            let manifest = url.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { throw LibraryError.noManifest(name) }
            do { _ = try StoreSet(manifestURL: manifest) } catch { throw LibraryError.failed(name, "\(error)") }
            return try linkFolder(url, name: url.lastPathComponent)
        }
        switch url.pathExtension.lowercased() {
        case "gmk":
            do { _ = try FeatureStoreFile(contentsOf: url) } catch { throw LibraryError.failed(name, "it is not a readable store file (\(error))") }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if size > copyLimit {
                // Too big to copy: the file stays where it is and the library keeps a bookmark to it.
                let target = uniqueURL(in: mapsDirectory, name: url.deletingPathExtension().lastPathComponent, ext: Self.linkExtension)
                try JSONEncoder().encode(Link(bookmark: try Self.bookmark(for: url), kind: .file)).write(to: target, options: .atomic)
                return target.lastPathComponent
            }
            let target = uniqueURL(in: mapsDirectory, name: url.deletingPathExtension().lastPathComponent, ext: "gmk")
            try FileManager.default.copyItem(at: url, to: target)
            return target.lastPathComponent
        case "json":
            let data = try CoordinatedFiles.read(url)
            do { _ = try MapStyle(json: data) } catch {
                // The manifest of a set of blocks is JSON too, and a file picker cannot give the folder around a single file.
                if (try? StoreManifest(json: data)) != nil { throw LibraryError.noManifest("\(name) (pick the folder, not the file)") }
                throw LibraryError.notAStyle(name, "\(error)")
            }
            let target = uniqueURL(in: stylesDirectory, name: url.deletingPathExtension().lastPathComponent, ext: "json")
            try CoordinatedFiles.write(data, to: target)
            return target.lastPathComponent
        default:
            throw LibraryError.notAMap(name)
        }
    }

    /// Writes the link to a folder of blocks into the library and returns its file name there.
    private func linkFolder(_ folder: URL, name: String) throws -> String {
        let bookmark = try Self.bookmark(for: folder)
        let target = uniqueURL(in: mapsDirectory, name: name, ext: Self.linkExtension)
        try JSONEncoder().encode(Link(bookmark: bookmark, kind: .folder)).write(to: target, options: .atomic)
        return target.lastPathComponent
    }

    /// Adds a set of blocks that the app built itself (question 63): the folder stays where it is and the library links to it.
    ///
    /// A folder that the library already links to is not added a second time, so building the same regions again updates the map
    /// that is there.
    ///
    /// - Parameters:
    ///   - folder: The folder with `manifest.json` and the block files.
    ///   - name: The name for the map: what the user sees, and the start of its file name in the library.
    /// - Returns: The id of the map in the library (new, or the one that already linked to this folder).
    /// - Throws: ``LibraryError`` for a name that cannot be a file name, a folder without a readable manifest, or a file error.
    @discardableResult
    func addBuilt(folder: URL, name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(name) else { throw LibraryError.failed(name, "that is not a name a map can have") }
        let manifest = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { throw LibraryError.noManifest(folder.lastPathComponent) }
        do { _ = try StoreSet(manifestURL: manifest) } catch { throw LibraryError.failed(name, "\(error)") }
        let wanted = folder.standardizedFileURL.resolvingSymlinksInPath().path
        if let known = maps.first(where: { $0.kind == .blocks && linkedFolder(of: $0)?.path == wanted }) { return known.id }
        let id = try linkFolder(folder, name: name)
        reload()
        return id
    }

    /// The folder a link in the library leads to, or `nil` if it cannot be resolved. No access is started.
    private func linkedFolder(of map: MapItem) -> URL? {
        guard let link = try? JSONDecoder().decode(Link.self, from: Data(contentsOf: url(of: map))) else { return nil }
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        var stale = false
        return (try? URL(resolvingBookmarkData: link.bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale))?
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    /// A file name in a folder that is not taken: `name.ext`, or `name 2.ext` and so on.
    func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    private struct Link: Codable {
        enum Kind: String, Codable { case folder, file }
        var bookmark: Data
        /// What the bookmark leads to; a link written before big files were linked has none and is a folder.
        var kind: Kind?
    }

    private static func linkKind(at url: URL) -> Link.Kind {
        ((try? JSONDecoder().decode(Link.self, from: Data(contentsOf: url)))?.kind) ?? .folder
    }

    private static func bookmark(for folder: URL) throws -> Data {
        #if os(macOS)
        try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    // MARK: Names and removal

    /// A name that can be a file name: not empty, no slash or colon, not starting with a dot.
    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix(".") && !trimmed.contains("/") && !trimmed.contains(":") && trimmed.count <= 100
    }

    func rename(_ map: MapItem, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(name) else { throw LibraryError.failed(map.name, "\"\(name)\" cannot be the name of a file.") }
        let ext = (map.id as NSString).pathExtension
        let target = mapsDirectory.appendingPathComponent(name).appendingPathExtension(ext)
        guard target.lastPathComponent != map.id else { return }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LibraryError.exists(name) }
        try FileManager.default.moveItem(at: url(of: map), to: target)
        if selectedMapID == map.id { selectedMapID = target.lastPathComponent }
        // The style that was chosen for the map goes with it.
        var chosen = storedChoices
        if let value = chosen.removeValue(forKey: map.id) { chosen[target.lastPathComponent] = value; storedChoices = chosen }
        reload()
    }

    func rename(_ style: StyleItem, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(name) else { throw LibraryError.failed(style.name, "\"\(name)\" cannot be the name of a file.") }
        let target = stylesDirectory.appendingPathComponent(name).appendingPathExtension("json")
        guard target.lastPathComponent != style.id else { return }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LibraryError.exists(name) }
        try CoordinatedFiles.move(from: url(of: style), to: target)
        // Where the old file was chosen, the renamed one is.
        var chosen = storedChoices
        for (key, value) in chosen where value == StyleChoice.user(style.id).storedValue { chosen[key] = StyleChoice.user(target.lastPathComponent).storedValue }
        storedChoices = chosen
        reload()
    }

    func delete(_ map: MapItem) throws {
        try FileManager.default.removeItem(at: url(of: map))
        var chosen = storedChoices
        chosen[map.id] = nil
        storedChoices = chosen
        reload()
    }

    func delete(_ style: StyleItem) throws {
        try CoordinatedFiles.delete(url(of: style))
        reload()
    }

    // MARK: Styles

    /// The style that draws a map: the one chosen for it, or the standard style.
    func styleChoice(forMap id: String?) -> StyleChoice {
        guard let id, let value = storedChoices[id], let choice = StyleChoice(storedValue: value) else { return .standard }
        if case .user(let file) = choice, !styles.contains(where: { $0.id == file }) { return .standard }
        return choice
    }

    func setStyleChoice(_ choice: StyleChoice, forMap id: String) {
        var chosen = storedChoices
        chosen[id] = choice.storedValue
        storedChoices = chosen
        revision += 1
    }

    private var storedChoices: [String: String] {
        get { defaults.dictionary(forKey: Keys.styles) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Keys.styles) }
    }

    /// The style a choice stands for.
    func style(for choice: StyleChoice) throws -> MapStyle {
        switch choice {
        case .standard: return .standard
        case .watch: return .watch
        case .user(let file):
            let url = stylesDirectory.appendingPathComponent(file)
            do { return try MapStyle(json: try CoordinatedFiles.read(url)) } catch { throw LibraryError.notAStyle(file, "\(error)") }
        }
    }

    /// Saves a style as a new file of the user (a copy of a built-in style to start from, or the result of editing).
    @discardableResult
    func addStyle(_ style: MapStyle, named name: String) throws -> StyleItem {
        guard Self.isValidName(name) else { throw LibraryError.failed(name, "\"\(name)\" cannot be the name of a file.") }
        let target = uniqueURL(in: stylesDirectory, name: name.trimmingCharacters(in: .whitespacesAndNewlines), ext: "json")
        try CoordinatedFiles.write(try style.jsonData(), to: target)
        reload()
        return styles.first { $0.id == target.lastPathComponent } ?? StyleItem(id: target.lastPathComponent, name: name, date: .now)
    }

    /// Writes a style to the file of an item of the library (the style editor saves with it). The map that uses the style is drawn again.
    func saveStyle(_ style: MapStyle, to item: StyleItem) throws {
        do { try CoordinatedFiles.write(try style.jsonData(), to: url(of: item)) } catch { throw LibraryError.failed(item.name, error.localizedDescription) }
        reload()
    }

    // MARK: Opening

    /// Opens a map: reads the file or the manifest, and works out where to look first.
    ///
    /// - Throws: ``LibraryError`` or the kit's store errors, which read as sentences.
    func open(_ map: MapItem) throws -> OpenedMap {
        switch map.kind {
        case .file:
            let file = try FeatureStoreFile(contentsOf: url(of: map))
            let box = file.boundingBox
            return OpenedMap(id: map.id, source: file, center: Self.middle(of: box), zoom: Self.zoom(fitting: box, limits: 4...16))
        case .blocks, .linkedFile:
            let link = try JSONDecoder().decode(Link.self, from: Data(contentsOf: url(of: map)))
            var stale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = .withSecurityScope
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            guard let target = try? URL(resolvingBookmarkData: link.bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale), !stale else {
                throw LibraryError.staleLink(map.name)
            }
            // The access is held while the map is open (it is given back when the `OpenedMap` goes).
            let accessing = target.startAccessingSecurityScopedResource()
            do {
                if map.kind == .linkedFile {
                    let file = try FeatureStoreFile(contentsOf: target)
                    let box = file.boundingBox
                    return OpenedMap(
                        id: map.id, source: file, center: Self.middle(of: box), zoom: Self.zoom(fitting: box, limits: 4...16),
                        accessed: accessing ? [target] : [])
                }
                let set = try StoreSet(manifestURL: target.appendingPathComponent("manifest.json"))
                guard let box = set.boundingBox else { throw StoreSetError.invalidManifest("the manifest lists no blocks") }
                // The middle of a big set can be in the sea: start in the block nearest to it.
                let centre = Self.middle(of: box)
                let start = Self.nearestBlockCentre(in: set, to: centre) ?? centre
                return OpenedMap(
                    id: map.id, source: set, center: start, zoom: Self.zoom(fitting: box, limits: 9...11), accessed: accessing ? [target] : [])
            } catch {
                if accessing { target.stopAccessingSecurityScopedResource() }
                throw error
            }
        }
    }

    static func middle(of box: BoundingBox) -> Coordinate {
        Coordinate(latitude: (box.south + box.north) / 2, longitude: (box.west + box.east) / 2)
    }

    /// A zoom at which a box about 600 points wide fits, within limits.
    static func zoom(fitting box: BoundingBox, limits: ClosedRange<Double>) -> Double {
        let degrees = max(box.east - box.west, 0.0001)
        let zoom = log2(360 / degrees * 600 / 256)
        return min(max(zoom, limits.lowerBound), limits.upperBound)
    }

    private static func nearestBlockCentre(in set: StoreSet, to point: Coordinate) -> Coordinate? {
        var best: (distance: Double, centre: Coordinate)?
        for block in set.manifest.blocks {
            guard let tile = TileID(zoom: set.manifest.blockZoom, x: block.x, y: block.y) else { continue }
            let centre = Coordinate(
                latitude: (tile.northWest.latitude + tile.southEast.latitude) / 2, longitude: (tile.northWest.longitude + tile.southEast.longitude) / 2)
            let d = pow(centre.latitude - point.latitude, 2) + pow((centre.longitude - point.longitude) * cos(point.latitude * .pi / 180), 2)
            if best == nil || d < best!.distance { best = (d, centre) }
        }
        return best?.centre
    }
}
