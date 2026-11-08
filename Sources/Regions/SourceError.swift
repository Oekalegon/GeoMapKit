/// An error of the source data manager.
public enum SourceError: Error, Equatable, Sendable {
    /// There is not enough free space for the files to download.
    case notEnoughSpace(needed: Int64, available: Int64)

    /// A download ended with fewer or more bytes than the server said the file has. The partial file is kept to resume from.
    case incompleteDownload(region: String, expected: Int64, received: Int64)

    /// The cache folder cannot be used.
    case cacheUnusable(String)
}
