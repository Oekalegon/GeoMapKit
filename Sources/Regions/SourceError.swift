import Foundation

/// An error of the source data manager.
public enum SourceError: Error, Equatable, Sendable {
    /// There is not enough free space for the files to download.
    case notEnoughSpace(needed: Int64, available: Int64)

    /// A download ended with fewer or more bytes than the server said the file has. The partial file is kept to resume from.
    case incompleteDownload(region: String, expected: Int64, received: Int64)

    /// The region is already being downloaded by this manager; a second download would write to the same part file.
    case alreadyDownloading(region: String)

    /// Another process is downloading into the same cache folder.
    case cacheBusy

    /// The cache folder cannot be used.
    case cacheUnusable(String)
}

extension SourceError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notEnoughSpace(let needed, let available):
            "Not enough free space: \(Self.size(needed)) needed (with a margin), \(Self.size(available)) available."
        case .incompleteDownload(let region, let expected, let received):
            "The download of \(region) ended after \(Self.size(received)) of \(Self.size(expected)); run it again to continue."
        case .alreadyDownloading(let region): "\(region) is already being downloaded."
        case .cacheBusy: "Another process is downloading into this cache folder; wait for it to finish."
        case .cacheUnusable(let reason): "The cache folder cannot be used: \(reason)."
        }
    }

    private static func size(_ bytes: Int64) -> String { ByteCountFormatStyle(style: .file).format(bytes) }
}
