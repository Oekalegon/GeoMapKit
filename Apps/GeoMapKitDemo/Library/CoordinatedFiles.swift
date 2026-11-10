import Foundation

/// Reads and writes files through `NSFileCoordinator`, so that a file in an iCloud folder is not read while the system writes a new version
/// into it, and the system learns of our writes. For a file in a local folder it does the same work as the plain calls.
///
/// Every call blocks until the coordinator has access (and, for a file that iCloud has not downloaded yet, the coordinator waits for the
/// download), so call these off the main thread for a folder that may be in iCloud.
enum CoordinatedFiles {
    /// The contents of a file.
    static func read(_ url: URL) throws -> Data {
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Writes a file, replacing what is there, in one step (a reader sees the old or the new contents, never half of them).
    static func write(_ data: Data, to url: URL) throws {
        var result: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            result = Result { try data.write(to: writeURL, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    /// Moves a file (a rename). The target must not exist.
    static func move(from source: URL, to target: URL) throws {
        var result: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: source, options: .forMoving, writingItemAt: target, options: .forReplacing, error: &coordinationError
        ) { from, to in
            result = Result { try FileManager.default.moveItem(at: from, to: to) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    /// Removes a file.
    static func delete(_ url: URL) throws {
        var result: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { deleteURL in
            result = Result { try FileManager.default.removeItem(at: deleteURL) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}
