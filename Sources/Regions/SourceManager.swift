import Foundation

/// Finds out which source files an area needs, tells what it would take to get them, and gets them.
///
/// The work is in two steps so that nothing big is downloaded without a yes:
///
/// 1. ``plan(for:)`` looks at the cache and asks the server small questions (the size of a missing file, whether an old file
///    has changed). It downloads nothing.
/// 2. ``fetch(_:progress:)`` downloads what the plan says, after the caller has shown the plan and been told to go on.
///
/// A file in the cache is asked about again only when it is older than the cache's time limit (30 days by default), and then
/// with its `ETag`, so an unchanged file costs one small request. A file that cannot be checked (no network) is still used,
/// and the plan says why. Downloads go to a part file, continue where an interrupted one stopped, and are put in place only
/// when they have the size the server gave.
///
/// The manager is an actor, but its calls suspend while the network works, so two calls can overlap. A region that is being
/// downloaded is claimed: a second ``fetch(_:progress:)`` that needs it fails with ``SourceError/alreadyDownloading(region:)``
/// instead of writing to the same part file. The claim holds within one process; two processes sharing a cache folder are not
/// guarded.
public actor SourceManager {
    /// The cache.
    public nonisolated let cache: SourceCache
    private let downloader: any Downloader
    /// The regions whose files are being downloaded now.
    private var active: Set<String> = []

    /// Creates a manager.
    ///
    /// - Parameters:
    ///   - cache: The cache folder.
    ///   - downloader: The network.
    public init(cache: SourceCache, downloader: any Downloader) {
        self.cache = cache
        self.downloader = downloader
    }

    /// The free space to keep beyond the files themselves, in bytes, so that a download does not fill the volume.
    public static let spareBytes: Int64 = 256 * 1024 * 1024

    private func claim(_ ids: [String]) throws {
        if let busy = ids.first(where: active.contains) { throw SourceError.alreadyDownloading(region: busy) }
        active.formUnion(ids)
    }

    /// Makes the plan for a selection of regions. Only the network questions described above are asked.
    ///
    /// - Parameter selection: The regions an area needs (see `RegionIndex.regions(covering:)`).
    /// - Returns: The plan, with one item per region in the order of the selection.
    /// - Throws: The downloader's error if the server cannot be asked about a file that is not in the cache (its size is needed),
    ///   or a file error.
    public func plan(for selection: RegionSelection) async throws -> DownloadPlan {
        var items: [PlanItem] = []
        for region in selection.regions {
            items.append(try await item(for: region))
        }
        return DownloadPlan(items: items, coveredShare: selection.coveredShare)
    }

    private func item(for region: SourceRegion) async throws -> PlanItem {
        let (status, record) = cache.status(ofRegionID: region.id)
        switch status {
        case .current:
            return PlanItem(region: region, action: .useCached, size: record?.size)
        case .stale:
            guard let record else { return PlanItem(region: region, action: .useCached, size: nil) }
            do {
                switch try await downloader.metadata(of: region.pbfURL, ifNoneMatch: record.etag) {
                case .notModified:
                    try cache.markChecked(regionID: region.id)
                    return PlanItem(region: region, action: .useCached, size: record.size)
                case .info(let info):
                    // A server that sends no `ETag`: the same size and modification time mean the same file.
                    if record.etag == nil, info.size == record.size, info.lastModified == record.lastModified, info.lastModified != nil {
                        try cache.markChecked(regionID: region.id)
                        return PlanItem(region: region, action: .useCached, size: record.size)
                    }
                    return PlanItem(
                        region: region, action: .update, size: info.size, alreadyDownloaded: resumable(region, info), remote: info)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Offline or the server is down: the old file is better than none.
                return PlanItem(region: region, action: .useCached, size: record.size, checkFailure: "\(error)")
            }
        case .missing, .damaged:
            let metadata = try await downloader.metadata(of: region.pbfURL, ifNoneMatch: nil)
            guard case .info(let info) = metadata else {
                throw SourceError.cacheUnusable("the server answered 'not modified' to a question without an ETag")
            }
            return PlanItem(region: region, action: .download, size: info.size, alreadyDownloaded: resumable(region, info), remote: info)
        }
    }

    /// The bytes of an unfinished download that belong to the file the server has now. They are only continued when the server
    /// gives an `ETag` that is the same: without one, a download starts again from the beginning.
    private func resumable(_ region: SourceRegion, _ info: RemoteFileInfo) -> Int64 {
        guard let partial = cache.partialDownload(regionID: region.id), let etag = info.etag, partial.etag == etag else { return 0 }
        return partial.bytes
    }

    /// Downloads what a plan says and returns the files to cut from.
    ///
    /// The free space is checked first. Each download goes to a part file and, if it was interrupted earlier and the server's
    /// file has not changed, continues after the bytes that are there. A file replaces the old one only when it is complete.
    ///
    /// - Parameters:
    ///   - plan: The plan, as it was shown to the user.
    ///   - progress: Called with the region's identifier, the bytes of its file held so far and its size (`nil` if unknown).
    /// - Returns: The files of all items of the plan, in the order of the plan.
    /// - Throws: ``SourceError/alreadyDownloading(region:)`` if a region is being downloaded by another call,
    ///   ``SourceError/notEnoughSpace(needed:available:)`` before anything is downloaded,
    ///   ``SourceError/incompleteDownload(region:expected:received:)`` if a file is short (the part file stays for a later
    ///   resume), the downloader's error, or a file error.
    public func fetch(_ plan: DownloadPlan, progress: @Sendable (String, Int64, Int64?) -> Void = { _, _, _ in }) async throws -> [URL] {
        let needed = plan.bytesToDownload
        if needed > 0, let available = cache.availableBytes(), available < needed + Self.spareBytes {
            throw SourceError.notEnoughSpace(needed: needed + Self.spareBytes, available: available)
        }
        let ids = plan.items.filter { $0.action != .useCached }.map(\.region.id)
        try claim(ids)
        defer { active.subtract(ids) }
        var files: [URL] = []
        for item in plan.items {
            let region = item.region
            if item.action != .useCached {
                try Task.checkCancellation()
                let keep = item.alreadyDownloaded > 0
                let part = try cache.preparePart(regionID: region.id, etag: item.remote?.etag, keepBytes: keep)
                let offset: Int64 = keep ? (cache.partialDownload(regionID: region.id)?.bytes ?? 0) : 0
                let info = try await downloader.download(
                    from: region.pbfURL, to: part, resumeFrom: offset, ifRange: keep ? item.remote?.etag : nil
                ) { progress(region.id, $0, item.size) }
                // The size the server gave with the download counts; the size of the plan is the fallback.
                var received = info
                if received.size == nil { received.size = item.size }
                try cache.install(regionID: region.id, from: region.pbfURL, info: received)
            }
            files.append(cache.fileURL(forRegionID: region.id))
        }
        return files
    }
}
