import Foundation
import GeoCore
import Testing

@testable import Regions

/// The cache folder: records, the time limit, damaged files and unfinished downloads.
@Suite("SourceCache")
struct SourceCacheTests {
    private func makeCache(clock: TestClock = TestClock(), space: Int64? = 1_000_000_000) throws -> (SourceCache, URL, TestClock) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-cache-\(UUID().uuidString)")
        return (SourceCache(directory: directory, now: { clock.now }, availableCapacity: { _ in space }), directory, clock)
    }

    private let url = URL(string: "https://download.example.org/europe/norway-latest.osm.pbf")!

    /// Puts a file of `bytes` into the cache the way a download does.
    private func store(_ cache: SourceCache, id: String = "norway", bytes: Int = 1000, etag: String? = "\"v1\"") throws {
        let part = try cache.preparePart(regionID: id, etag: etag, keepBytes: false)
        try Data(repeating: 7, count: bytes).write(to: part)
        try cache.install(regionID: id, from: url, info: RemoteFileInfo(size: Int64(bytes), etag: etag, lastModified: "Mon"))
    }

    @Test("A file that is installed is current, with a record of where it came from")
    func install() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(cache.status(ofRegionID: "norway").status == .missing)
        try store(cache)
        let (status, record) = cache.status(ofRegionID: "norway")
        guard case .current = status else { Issue.record("not current: \(status)"); return }
        #expect(record?.url == url && record?.size == 1000 && record?.etag == "\"v1\"" && record?.lastModified == "Mon")
        #expect(try Data(contentsOf: cache.fileURL(forRegionID: "norway")).count == 1000)
        #expect(!FileManager.default.fileExists(atPath: cache.partURL("norway").path), "the part file became the file")
        #expect(cache.list().map(\.regionID) == ["norway"])
    }

    @Test("A file is current for 30 days after it was checked and stale after, and a check starts the time again")
    func timeLimit() throws {
        let (cache, directory, clock) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store(cache)
        clock.advance(days: 29)
        guard case .current = cache.status(ofRegionID: "norway").status else { Issue.record("not current at 29 days"); return }
        clock.advance(days: 2)
        guard case .stale = cache.status(ofRegionID: "norway").status else { Issue.record("not stale at 31 days"); return }
        try cache.markChecked(regionID: "norway")
        guard case .current = cache.status(ofRegionID: "norway").status else { Issue.record("not current after a check"); return }
        // The download date is kept, the check date moves.
        let record = try #require(cache.status(ofRegionID: "norway").record)
        #expect(record.checkedAt > record.downloadedAt)
    }

    @Test("A file the record does not match, a missing file and an unreadable record are damaged, not trusted")
    func damaged() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store(cache)
        try Data(repeating: 1, count: 10).write(to: cache.fileURL(forRegionID: "norway"))
        guard case .damaged = cache.status(ofRegionID: "norway").status else { Issue.record("a file of another size is not damaged"); return }
        try FileManager.default.removeItem(at: cache.fileURL(forRegionID: "norway"))
        guard case .damaged = cache.status(ofRegionID: "norway").status else { Issue.record("a missing file is not damaged"); return }
        try store(cache)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("norway.osm.pbf.json"))
        guard case .damaged = cache.status(ofRegionID: "norway").status else { Issue.record("a bad record is not damaged"); return }
        #expect(cache.list().isEmpty, "a record that cannot be read is not listed")
    }

    @Test("A download whose size is not the server's is not installed, and the part file stays for a resume")
    func incomplete() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let part = try cache.preparePart(regionID: "norway", etag: "\"v1\"", keepBytes: false)
        try Data(repeating: 7, count: 400).write(to: part)
        #expect(throws: SourceError.incompleteDownload(region: "norway", expected: 1000, received: 400)) {
            try cache.install(regionID: "norway", from: url, info: RemoteFileInfo(size: 1000, etag: "\"v1\""))
        }
        #expect(cache.status(ofRegionID: "norway").status == .missing)
        #expect(cache.partialDownload(regionID: "norway")?.bytes == 400 && cache.partialDownload(regionID: "norway")?.etag == "\"v1\"")
    }

    @Test("A new file replaces the old one in one step, and an old file survives until then")
    func replace() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store(cache, bytes: 1000)
        let part = try cache.preparePart(regionID: "norway", etag: "\"v2\"", keepBytes: false)
        try Data(repeating: 9, count: 600).write(to: part)
        #expect(try Data(contentsOf: cache.fileURL(forRegionID: "norway")).count == 1000, "the old file is there while the new one is partial")
        try cache.install(regionID: "norway", from: url, info: RemoteFileInfo(size: 600, etag: "\"v2\""))
        #expect(try Data(contentsOf: cache.fileURL(forRegionID: "norway")).count == 600)
        #expect(cache.status(ofRegionID: "norway").record?.etag == "\"v2\"")
    }

    @Test("Remove deletes the file, the record and an unfinished download")
    func remove() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store(cache)
        _ = try cache.preparePart(regionID: "norway", etag: nil, keepBytes: false)
        try cache.remove(regionID: "norway")
        #expect(cache.status(ofRegionID: "norway").status == .missing)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("An identifier cannot name a file outside the folder")
    func safeNames() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = cache.fileURL(forRegionID: "../../etc/passwd")
        #expect(path.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path)
        #expect(path.lastPathComponent == "%2E%2E%2F%2E%2E%2Fetc%2Fpasswd.osm.pbf")
        #expect(cache.fileURL(forRegionID: "a/b") != cache.fileURL(forRegionID: "a_b"), "different ids, different files")
        #expect(cache.fileURL(forRegionID: "baden-wuerttemberg").lastPathComponent == "baden-wuerttemberg.osm.pbf")
    }

    @Test("The list is ordered by region, and a part file with an unreadable note has no ETag")
    func listAndPart() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store(cache, id: "sweden")
        try store(cache, id: "norway")
        try store(cache, id: "finland")
        #expect(cache.list().map(\.regionID) == ["finland", "norway", "sweden"])
        let part = try cache.preparePart(regionID: "denmark", etag: "\"v1\"", keepBytes: false)
        try Data(repeating: 1, count: 300).write(to: part)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("denmark.osm.pbf.part.json"))
        #expect(cache.partialDownload(regionID: "denmark")?.bytes == 300 && cache.partialDownload(regionID: "denmark")?.etag == nil)
    }

    @Test("The download lock is held by one holder at a time, and is free again after release")
    func downloadLock() throws {
        let (cache, directory, _) = try makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try cache.lockDownloads()
        #expect(throws: SourceError.cacheBusy) { try cache.lockDownloads() }
        first.release()
        first.release()
        let second = try cache.lockDownloads()
        second.release()
        // A lock that is dropped without release is given up too.
        _ = try cache.lockDownloads()
        let third = try cache.lockDownloads()
        third.release()
    }

    @Test("The errors read as sentences, with sizes written the way the tools write them")
    func messages() {
        #expect("\(SourceError.incompleteDownload(region: "sweden", expected: 949_756_885, received: 0))" == "The download of sweden ended after 0 bytes of 949.8 MB; run it again to continue.")
        #expect("\(SourceError.notEnoughSpace(needed: 2_500_000_000, available: 12_345))".contains("2.5 GB needed (with a margin), 12.3 KB available"))
        #expect("\(SourceError.alreadyDownloading(region: "norway"))" == "norway is already being downloaded.")
        #expect("\(SourceError.notEnoughSpace(needed: 1_500_000_000, available: 300_000_000))".contains("needed (with a margin)"))
        let url = URL(string: "https://example.org/a.pbf")!
        #expect("\(DownloadError.httpStatus(404, url))" == "The server answered 404 for https://example.org/a.pbf.")
        #expect("\(DownloadError.insecureRedirect(URL(string: "http://example.org/a")!))".contains("not https"))
        #expect("\(RegionError.duplicateRegion("x"))" == "The region index lists x twice.")
    }

    @Test("The default folder is in the application support folder and the free space can be asked")
    func defaults() throws {
        #expect(try SourceCache.defaultDirectory().path.hasSuffix("GeoMapKit/Sources"))
        #expect(SourceCache.systemAvailableCapacity(FileManager.default.temporaryDirectory) ?? 0 > 0)
    }
}
