/// What a server says about a file.
public struct RemoteFileInfo: Equatable, Sendable {
    /// The size of the whole file in bytes, or `nil` if the server does not say.
    public var size: Int64?
    /// The `ETag` of the file, or `nil`. It changes when the file does.
    public var etag: String?
    /// The `Last-Modified` header as the server wrote it, or `nil`.
    public var lastModified: String?

    /// Creates the description of a remote file.
    public init(size: Int64? = nil, etag: String? = nil, lastModified: String? = nil) {
        self.size = size
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// The answer to a question about a remote file that may be conditional.
public enum RemoteMetadata: Equatable, Sendable {
    /// The file is the one the `ETag` of the question named.
    case notModified
    /// The current state of the file.
    case info(RemoteFileInfo)
}
