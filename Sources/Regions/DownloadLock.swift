import Foundation

/// A lock on a cache folder that is held while files are downloaded into it, so that two processes (two runs of a tool, or an app
/// and a tool) never write the same part file.
///
/// The lock is a `flock` on a file in the folder, so it is released when the holder ends, whatever way it ends (a killed process
/// included). Holding it is not needed to read the cache.
public final class DownloadLock: @unchecked Sendable {
    // `@unchecked Sendable`: the descriptor is only closed once, under the lock below.
    private let guardLock = NSLock()
    private var descriptor: Int32

    init(descriptor: Int32) { self.descriptor = descriptor }

    /// Gives the lock up. Calling it again does nothing.
    public func release() {
        guardLock.lock(); defer { guardLock.unlock() }
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}

extension SourceCache {
    /// Takes the download lock of the folder.
    ///
    /// - Returns: The lock; call ``DownloadLock/release()`` when the downloads are done.
    /// - Throws: ``SourceError/cacheBusy`` if another holder has it, ``SourceError/cacheUnusable(_:)`` if the folder or the lock
    ///   file cannot be made.
    public func lockDownloads() throws -> DownloadLock {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw SourceError.cacheUnusable("cannot create \(directory.path): \(error.localizedDescription)")
        }
        let path = directory.appendingPathComponent(".download.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { throw SourceError.cacheUnusable("cannot open \(path)") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw SourceError.cacheBusy
        }
        return DownloadLock(descriptor: descriptor)
    }
}
