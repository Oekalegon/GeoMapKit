import Foundation

/// What has to happen for one region before an area can be cut.
public struct PlanItem: Equatable, Sendable {
    /// What to do with the region's file.
    public enum Action: Equatable, Sendable {
        /// The file in the cache is current and is used as it is.
        case useCached
        /// There is no usable file: it is downloaded.
        case download
        /// The file in the cache is out of date: the new one is downloaded and replaces it when it is complete.
        case update
    }

    /// The region.
    public let region: SourceRegion
    /// What is to be done.
    public let action: Action
    /// The size of the file on the server, or `nil` if the server did not say or was not asked.
    public let size: Int64?
    /// How many bytes of it an earlier, unfinished download already holds; the download continues after them.
    public let alreadyDownloaded: Int64
    /// What the server said about the file when the plan was made, if it was asked.
    public let remote: RemoteFileInfo?
    /// The reason the server could not be asked about a file that is in the cache (the cached file is used meanwhile), or `nil`.
    public let checkFailure: String?

    /// Creates a plan item.
    public init(
        region: SourceRegion, action: Action, size: Int64?, alreadyDownloaded: Int64 = 0, remote: RemoteFileInfo? = nil,
        checkFailure: String? = nil
    ) {
        self.region = region
        self.action = action
        self.size = size
        self.alreadyDownloaded = alreadyDownloaded
        self.remote = remote
        self.checkFailure = checkFailure
    }

    /// The bytes still to be downloaded for this item, or `nil` if the size is not known. 0 when the cached file is used.
    public var bytesToDownload: Int64? {
        action == .useCached ? 0 : size.map { max($0 - alreadyDownloaded, 0) }
    }
}

/// The files an area needs and what it takes to get them. Making a plan only asks the server questions; nothing is downloaded
/// until the plan is given to ``SourceManager/fetch(_:progress:)``, which is the point at which the user is asked.
public struct DownloadPlan: Equatable, Sendable {
    /// One item per region, in the order of the selection (the preferred source first).
    public let items: [PlanItem]
    /// The share of the area that the regions' outlines cover, from the selection.
    public let coveredShare: Double

    /// Creates a plan.
    public init(items: [PlanItem], coveredShare: Double) {
        self.items = items
        self.coveredShare = coveredShare
    }

    /// Whether anything has to be downloaded.
    public var needsDownload: Bool { items.contains { $0.action != .useCached } }

    /// The bytes still to be downloaded, counting only the items whose size is known.
    public var bytesToDownload: Int64 { items.reduce(0) { $0 + ($1.bytesToDownload ?? 0) } }

    /// Whether the size of some file to download is not known, so ``bytesToDownload`` is only a lower bound.
    public var hasUnknownSizes: Bool { items.contains { $0.action != .useCached && $0.size == nil } }
}
