import Foundation

/// The network, as far as the source data manager needs it, so that tests use a fake and the app a `URLSession`.
///
/// An implementation identifies the app to the server, follows redirects, treats any status other than success as an
/// error, and never reads the whole file into memory.
public protocol Downloader: Sendable {
    /// Asks what a file is, without downloading it (an HTTP `HEAD`).
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - etag: The `ETag` of the copy that is held, or `nil`. With it the request is conditional: `If-None-Match`.
    /// - Returns: ``RemoteMetadata/notModified`` if the server says the held copy is current, else the file's description.
    func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata

    /// Downloads a file, or the rest of it, appending to a local file.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - file: The local file the bytes are appended to. It holds `offset` bytes already when `offset` is above 0.
    ///   - offset: How many bytes the local file already holds: the request asks for the rest (`Range`).
    ///   - etag: The `ETag` of the file those bytes came from (`If-Range`). If the server's file has changed, or it does not
    ///     support ranges, it sends the whole file, and the implementation empties `file` first.
    ///   - progress: Called with the number of bytes the local file holds as they arrive.
    /// - Returns: What the server said about the file, with its full size.
    func download(
        from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
    ) async throws -> RemoteFileInfo
}
