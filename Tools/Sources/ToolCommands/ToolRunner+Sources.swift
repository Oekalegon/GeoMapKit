import Foundation
import FeatureStoreBuilder
import GeoCore
import Regions
import ToolSupport

extension ToolRunner {
    /// The name the tool gives itself to servers.
    public static let userAgent = "GeoMapKit-tools"

    /// Finds the source files an area needs and what it would take to get them. Nothing is downloaded.
    ///
    /// The regions are chosen for the area widened to whole cells (what `build` cuts). Only small questions go to the network:
    /// the region index when the copy is older than 30 days (or missing), and the size of each file that is not in the cache.
    ///
    /// - Parameters:
    ///   - area: The area.
    ///   - cacheDirectory: The cache folder, or `nil` for the default one.
    ///   - catalog: The list of regions, or `nil` for the Geofabrik index kept in the cache folder.
    ///   - downloader: The network, or `nil` for `URLSession`.
    /// - Returns: The report.
    /// - Throws: ``ToolError`` for an area that is invalid or that no region covers, and the errors of the catalog and the network.
    public static func sources(
        area: BoundingBox, cacheDirectory: URL? = nil, catalog: (any RegionCatalog)? = nil, downloader: (any Downloader)? = nil
    ) async throws -> SourcesReport {
        let (manager, plan, cutArea) = try await makePlan(area: area, cacheDirectory: cacheDirectory, catalog: catalog, downloader: downloader)
        return SourcesReport(area: cutArea, cacheDirectory: manager.cache.directory, plan: plan)
    }

    /// Downloads the source files an area needs, after the plan has been shown.
    ///
    /// - Parameters:
    ///   - area: The area.
    ///   - cacheDirectory: The cache folder, or `nil` for the default one.
    ///   - catalog: The list of regions, or `nil` for the Geofabrik index.
    ///   - downloader: The network, or `nil` for `URLSession`.
    ///   - confirmed: Whether the user said yes. Without it nothing is downloaded and the report is the plan, as from ``sources(area:cacheDirectory:catalog:downloader:)``.
    ///   - progress: Called with a region's identifier, the bytes of its file held and its size.
    /// - Returns: The report; `downloaded` says whether files were fetched.
    public static func fetch(
        area: BoundingBox, cacheDirectory: URL? = nil, catalog: (any RegionCatalog)? = nil, downloader: (any Downloader)? = nil,
        confirmed: Bool, progress: @Sendable @escaping (String, Int64, Int64?) -> Void = { _, _, _ in }
    ) async throws -> SourcesReport {
        let (manager, plan, cutArea) = try await makePlan(area: area, cacheDirectory: cacheDirectory, catalog: catalog, downloader: downloader)
        guard confirmed, plan.needsDownload else {
            return SourcesReport(area: cutArea, cacheDirectory: manager.cache.directory, plan: plan)
        }
        let clock = ContinuousClock()
        let started = clock.now
        _ = try await manager.fetch(plan, progress: progress)
        return SourcesReport(area: cutArea, cacheDirectory: manager.cache.directory, plan: plan, downloaded: true, downloadTime: clock.now - started)
    }

    /// The cached source files for an area, for a build. It never downloads.
    ///
    /// A file that the server has replaced since it was downloaded is out of date: it is refused, unless `allowStale` is set,
    /// and then it is used with a warning. A file that could not be checked because the network is down is used with a warning.
    ///
    /// - Parameters:
    ///   - area: The area (the one `build` was asked for; it is widened to whole cells like the cut).
    ///   - cacheDirectory: The cache folder, or `nil` for the default one.
    ///   - catalog: The list of regions, or `nil` for the Geofabrik index.
    ///   - downloader: The network (used to check the age of files), or `nil` for `URLSession`.
    ///   - allowStale: Whether a file that is out of date may be used.
    /// - Returns: The files, their records, the covered share and the warnings.
    /// - Throws: ``ToolError`` naming the regions that are not in the cache or are out of date, and telling what to do.
    public static func cachedSources(
        area: BoundingBox, cacheDirectory: URL? = nil, catalog: (any RegionCatalog)? = nil, downloader: (any Downloader)? = nil,
        allowStale: Bool = false
    ) async throws -> CachedSources {
        let (manager, plan, _) = try await makePlan(area: area, cacheDirectory: cacheDirectory, catalog: catalog, downloader: downloader)
        let absent = plan.items.filter { $0.action == .download }
        guard absent.isEmpty else {
            let names = absent.map { "\($0.region.name) (\($0.region.id))" }.joined(separator: ", ")
            throw ToolError(
                "The source files for this area are not all in the cache: \(names). Run 'geomapkit fetch' with the same area and --yes first.")
        }
        let outdated = plan.items.filter { $0.action == .update }
        guard outdated.isEmpty || allowStale else {
            let names = outdated.map { "\($0.region.name) (\($0.region.id))" }.joined(separator: ", ")
            throw ToolError(
                "The cached source files are out of date, the server has newer ones: \(names). Run 'geomapkit fetch' with the same area and --yes to update them, or use --allow-stale to build from the cached files.")
        }
        var warnings: [String] = []
        for item in plan.items {
            if item.action == .update, let record = manager.cache.status(ofRegionID: item.region.id).record {
                warnings.append("\(item.region.name) is older than the file on the server: using the copy downloaded \(record.downloadedAt.formatted(date: .abbreviated, time: .omitted)).")
            }
            if let failure = item.checkFailure {
                warnings.append("\(item.region.name) could not be checked against the server (\(failure)); using the cached file.")
            }
        }
        var files: [URL] = [], records: [CachedSource] = []
        for item in plan.items {
            guard let record = manager.cache.status(ofRegionID: item.region.id).record else {
                throw ToolError("The cached file of \(item.region.id) cannot be used; run 'geomapkit fetch' with --yes to download it again.")
            }
            files.append(manager.cache.fileURL(forRegionID: item.region.id))
            records.append(record)
        }
        return CachedSources(files: files, records: records, coveredShare: plan.coveredShare, warnings: warnings)
    }

    private static func makePlan(
        area: BoundingBox, cacheDirectory: URL?, catalog: (any RegionCatalog)?, downloader: (any Downloader)?
    ) async throws -> (SourceManager, DownloadPlan, BoundingBox) {
        guard area.isValid else { throw ToolError("The area is not valid") }
        let directory = try cacheDirectory ?? SourceCache.defaultDirectory()
        let network = downloader ?? URLSessionDownloader(userAgent: userAgent)
        let regions = try await (catalog ?? GeofabrikCatalog(directory: directory, downloader: network)).index()
        let cutArea = FeatureStoreBuilder.cellAlignedBox(covering: area)
        let selection = regions.regions(covering: cutArea)
        guard !selection.regions.isEmpty else {
            throw ToolError("No region of the index covers this area, so there is no source file for it.")
        }
        let manager = SourceManager(cache: SourceCache(directory: directory), downloader: network)
        return (manager, try await manager.plan(for: selection), cutArea)
    }
}
