import Foundation

/// Opens a block file of a manifest and checks it against what the manifest says (base blocks and level blocks alike).
enum BlockOpening {
    /// - Parameters:
    ///   - file: The path of the file, relative to `directory`.
    ///   - bytes: The size the manifest records.
    ///   - directory: The folder of the manifest.
    ///   - storageZoom: The zoom of the cells the file must hold.
    ///   - manifest: The manifest, for the format version and the rule table.
    ///   - bands: The bands the manifest lists for these blocks; a file may hold fewer (a file only has the bands with a feature).
    /// - Throws: ``StoreSetError`` for a file outside the folder, missing, unreadable or not what the manifest says.
    static func open(file name: String, bytes: Int64, in directory: URL, storageZoom: Int, manifest: StoreManifest, bands: [Int]) throws -> FeatureStoreFile {
        let url = directory.appendingPathComponent(name)
        // A block must be inside the folder even when a link in it points elsewhere.
        let folder = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(folder + "/") else {
            throw StoreSetError.blockMismatch(file: name, reason: "the file is not inside the folder of the manifest")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw StoreSetError.blockMissing(name) }
        let file: FeatureStoreFile
        do {
            file = try FeatureStoreFile(contentsOf: url)
        } catch {
            throw StoreSetError.blockMismatch(file: name, reason: "it is not a readable store file (\(error))")
        }
        guard file.storageZoom == storageZoom else {
            throw StoreSetError.blockMismatch(file: name, reason: "storage zoom \(file.storageZoom), the manifest says \(storageZoom)")
        }
        guard file.formatVersion == manifest.formatVersion, file.classifierVersion == manifest.classifierVersion else {
            throw StoreSetError.blockMismatch(
                file: name,
                reason: "format \(file.formatVersion) and rule table \(file.classifierVersion), the manifest says \(manifest.formatVersion) and \(manifest.classifierVersion)")
        }
        // A file only has the bands that hold a feature, so a sparse block (sea, bare land) has fewer than the manifest lists;
        // a band the manifest does not list means another build. (This no longer separates profiles: a Watch block with the mid and
        // detail bands passes in a full manifest; the other checks and the producer, which replaces a manifest of another profile, remain.)
        guard Set(file.bands.map { Int($0.rawValue) }).isSubset(of: bands) else {
            throw StoreSetError.blockMismatch(file: name, reason: "it holds bands that the manifest does not list")
        }
        // The manifest says which build each block is from; a file of another size is another build, or a half-written one.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? -1
        guard size == bytes else {
            throw StoreSetError.blockMismatch(file: name, reason: "the file has \(size) bytes, the manifest says \(bytes)")
        }
        return file
    }
}
