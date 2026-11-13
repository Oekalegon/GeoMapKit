import Foundation

extension MapLibrary {
    /// The folder of a map that the app built itself: the folder its link leads to, if it lies inside ``builtMapsRoot``. A folder
    /// anywhere else (a command-line build, a folder the user linked) is not the app's to delete, and gives `nil`.
    func builtFolder(of map: MapItem) -> URL? {
        guard map.kind == .blocks, let root = builtMapsRoot, let folder = linkedFolder(of: map) else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parts = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        // Inside the root and not the root itself: the path of the root is the start of the path of the folder.
        guard parts.count > base.count, Array(parts.prefix(base.count)) == base else { return nil }
        return folder
    }

    /// Deletes a map that the app built, with the folder of its blocks and levels, and then the entry in the library.
    ///
    /// The downloaded source files are kept: they are shared between maps (a neighbour's file serves several). The files go first;
    /// if they cannot be deleted the map stays in the library.
    ///
    /// - Parameters:
    ///   - map: The map.
    ///   - buildingFolder: The folder a build is writing to now, if any.
    /// - Throws: ``LibraryError/failed(_:_:)`` if the map is the one that is open, a build is writing to its folder, its folder is not
    ///   the app's to delete, or the files cannot be deleted.
    func deleteWithFiles(_ map: MapItem, buildingFolder: URL? = nil) throws {
        guard let folder = builtFolder(of: map) else {
            throw LibraryError.failed(map.name, "its files are not held by this app; Remove takes it out of the library and leaves the folder")
        }
        guard selectedMapID != map.id else {
            throw LibraryError.failed(map.name, "it is the map that is open; open another map first")
        }
        if let buildingFolder, buildingFolder.standardizedFileURL.resolvingSymlinksInPath() == folder {
            throw LibraryError.failed(map.name, "a build is writing to it; stop the build first")
        }
        do { try FileManager.default.removeItem(at: folder) } catch {
            throw LibraryError.failed(map.name, "the files could not be deleted: \(error.localizedDescription)")
        }
        try delete(map)
    }

    /// The size of a folder with everything in it, in bytes. It reads the whole tree, so it is not called on the main actor.
    nonisolated static func size(ofFolder folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
