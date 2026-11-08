import Foundation
import Testing

@testable import Regions

/// The download lock against a real second process.
@Suite("Download lock across processes", .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/python3")))
struct LockAcrossProcessesTests {
    @Test("A lock held by another process is refused, and is free again when that process is killed", .timeLimit(.minutes(1)))
    func otherProcess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SourceCache(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A helper takes the same flock on the same file and says so.
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        helper.arguments = [
            "-I", "-c",
            "import fcntl, sys, time\nf = open(sys.argv[1], 'w')\nfcntl.flock(f, fcntl.LOCK_EX)\nprint('locked', flush=True)\ntime.sleep(60)",
            directory.appendingPathComponent(".download.lock").path,
        ]
        let output = Pipe()
        helper.standardOutput = output
        try helper.run()
        defer { if helper.isRunning { helper.terminate() } }
        let line = String(data: output.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        try #require(line.contains("locked"))

        #expect(throws: SourceError.cacheBusy) { try cache.lockDownloads() }

        helper.terminate()   // killed: the system gives the lock up
        helper.waitUntilExit()
        let lock = try cache.lockDownloads()
        lock.release()
    }
}
