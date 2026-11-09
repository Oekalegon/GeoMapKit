import Foundation

/// A map in the library: a store file that was copied into the app, or a folder of blocks (or a very big file) that the app links to.
struct MapItem: Identifiable, Hashable {
    enum Kind: Hashable {
        /// One `.gmk` file, held in the app's own folder.
        case file
        /// A folder with a `manifest.json` and block files, which stays where it is (it can be several gigabytes).
        case blocks
        /// One `.gmk` file that is too big to copy (see `MapLibrary.copyLimit`): it stays where it is.
        case linkedFile
    }

    /// The name of the file in the library, with its extension: unique, and what the selection is stored as.
    let id: String
    /// What the user sees: the file name without its extension.
    var name: String
    let kind: Kind
    /// The size of the file, or `nil` for a linked folder.
    var bytes: Int64?
    var date: Date
}
