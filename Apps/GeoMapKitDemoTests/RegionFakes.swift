import Foundation
import GeoCore
import Regions

/// A region with a plain outline, for tests.
///
/// `west` is where the outline starts (it is 4 degrees wide): regions that should not be neighbours are far apart, so that the plan
/// of one does not need the file of another.
func fakeRegion(_ id: String, _ name: String, parent: String?, west: Double = 3) -> SourceRegion {
    let ring = [
        Coordinate(latitude: 50, longitude: west), Coordinate(latitude: 50, longitude: west + 4),
        Coordinate(latitude: 54, longitude: west + 4), Coordinate(latitude: 54, longitude: west),
    ]
    return SourceRegion(
        id: id, name: name, parentID: parent, pbfURL: URL(string: "https://download.example.org/\(id).osm.pbf")!,
        outline: [RegionPolygon(outer: ring)])
}

/// A list of regions without a network: Europe with the Netherlands (and two provinces) and Belgium, and Africa.
struct FakeCatalog: RegionCatalog {
    var fails = false
    func index() async throws -> RegionIndex {
        if fails { throw URLError(.notConnectedToInternet) }
        return try RegionIndex(regions: [
            fakeRegion("europe", "Europe", parent: nil, west: 50),
            fakeRegion("europe/netherlands", "Netherlands", parent: "europe"),
            fakeRegion("europe/netherlands/zuid-holland", "Zuid-Holland", parent: "europe/netherlands"),
            fakeRegion("europe/netherlands/noord-brabant", "Noord-Brabant", parent: "europe/netherlands"),
            fakeRegion("europe/belgium", "België", parent: "europe", west: 20),
            fakeRegion("africa", "Africa", parent: nil, west: 80),
        ])
    }
}

/// Counts the downloads a fake network was asked for.
actor DownloadCounter {
    private(set) var count = 0
    func hit() { count += 1 }
}

/// A network that serves files of a fixed size, or waits until the download is cancelled.
struct FakeNetwork: Downloader {
    var size: Int64 = 3_000
    /// Waits for a cancel: after one chunk of a new file (a resumed file is completed).
    var waits = false
    var failsDownload = false
    var failsMetadata = false
    /// Waits (for a cancel) when asked about a file: the sizes are slow to come.
    var metadataWaits = false
    var counter: DownloadCounter?

    func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
        if failsMetadata { throw URLError(.notConnectedToInternet) }
        if metadataWaits { try await Task.sleep(for: .seconds(60)) }
        return .info(RemoteFileInfo(size: size, etag: "\"e\""))
    }

    func download(
        from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
    ) async throws -> RemoteFileInfo {
        await counter?.hit()
        if failsDownload { throw URLError(.networkConnectionLost) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let chunk = Int(size) / 3
        if waits && offset == 0 {
            try handle.write(contentsOf: Data(count: chunk))
            progress(Int64(chunk))
            try await Task.sleep(for: .seconds(60))
        }
        while try Int64(handle.offset()) < size {
            try handle.write(contentsOf: Data(count: chunk))
            progress(try Int64(handle.offset()))
        }
        return RemoteFileInfo(size: size, etag: "\"e\"")
    }
}
