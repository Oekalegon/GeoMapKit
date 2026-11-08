import Foundation

/// A ``Downloader`` that uses `URLSession`.
///
/// It names the app to the server in the `User-Agent` header (Geofabrik asks for this), asks for the file as it is (no
/// compression, so sizes and ranges mean bytes of the file), follows redirects but never from `https` to a weaker scheme, and
/// writes what arrives to the local file as it arrives, so a file of a gigabyte or more is never held in memory. A download
/// can be cancelled with the task that runs it.
public struct URLSessionDownloader: Downloader {
    private let userAgent: String
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration

    /// Creates a downloader.
    ///
    /// - Parameters:
    ///   - userAgent: The name sent to the server, for example `MyApp/1.0`. Say what the app is; do not put personal data in it.
    ///   - configuration: Makes the configuration of the sessions; a test passes one with its own `URLProtocol`. The default is
    ///     the standard configuration with a 60 second timeout per request.
    public init(
        userAgent: String = "GeoMapKit",
        configuration: @escaping @Sendable () -> URLSessionConfiguration = {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            return configuration
        }
    ) {
        self.userAgent = userAgent
        makeConfiguration = configuration
    }

    public func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let session = URLSession(configuration: makeConfiguration())
        defer { session.finishTasksAndInvalidate() }
        let redirects = RedirectGuard()
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request, delegate: redirects)
        } catch {
            if let refused = redirects.refused { throw DownloadError.insecureRedirect(refused) }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw DownloadError.notHTTP }
        switch http.statusCode {
        case 304: return .notModified
        case 200: return .info(Self.info(of: http, size: Self.contentLength(http)))
        default: throw Self.failure(for: http, url: url)
        }
    }

    public func download(
        from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void
    ) async throws -> RemoteFileInfo {
        // Bytes can only be continued when it is known which version of the file they came from.
        let start = (offset > 0 && etag != nil) ? offset : 0
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if start > 0, let etag {
            request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
            request.setValue(etag, forHTTPHeaderField: "If-Range")
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        if start > 0 { try handle.seekToEnd() } else { try handle.truncate(atOffset: 0) }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        // The delegate keeps `progress` while the download runs; the call does not return before the download has ended.
        return try await withoutActuallyEscaping(progress) { escapable in
            let stream = StreamingDownload(handle: handle, requestedOffset: start, progress: escapable)
            let session = URLSession(configuration: makeConfiguration(), delegate: stream, delegateQueue: queue)
            defer { session.finishTasksAndInvalidate() }
            let task = session.dataTask(with: request)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    stream.start(task, continuation)
                }
            } onCancel: {
                task.cancel()
            }
        }
    }

    fileprivate static func info(of response: HTTPURLResponse, size: Int64?) -> RemoteFileInfo {
        RemoteFileInfo(
            size: size, etag: response.value(forHTTPHeaderField: "ETag"), lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
    }

    fileprivate static func contentLength(_ response: HTTPURLResponse) -> Int64? {
        response.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// The error for a response that is not a success: a redirect to a weaker scheme that was refused, or the status.
    fileprivate static func failure(for response: HTTPURLResponse, url: URL) -> DownloadError {
        if (300..<400).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location"),
            let target = URL(string: location, relativeTo: url), target.scheme?.lowercased() != "https"
        {
            return .insecureRedirect(target)
        }
        return .httpStatus(response.statusCode, url)
    }
}

/// Refuses a redirect from `https` to another scheme and remembers where it led.
///
/// `@unchecked Sendable`: `refused` is only read and written under the lock.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var target: URL?

    /// The weaker address a redirect led to, if one was refused.
    var refused: URL? { lock.lock(); defer { lock.unlock() }; return target }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if request.url?.scheme?.lowercased() == "https" {
            completionHandler(request)
        } else {
            lock.lock(); target = request.url; lock.unlock()
            completionHandler(nil)
            task.cancel()
        }
    }
}

/// Writes a response to a file as it arrives and finishes a continuation with what the server said.
///
/// `@unchecked Sendable`: the session calls the delegate on one serial queue (`maxConcurrentOperationCount` is 1), so the
/// download state is only touched from that queue; `start` runs on the caller's thread, so the continuation and the result that
/// may arrive before it are kept under a lock, and the continuation is resumed exactly once.
private final class StreamingDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let handle: FileHandle
    private let requestedOffset: Int64
    /// Dropped when the download ends, so that nothing keeps the caller's closure alive after the call returns.
    private var progress: (@Sendable (Int64) -> Void)?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RemoteFileInfo, Error>?
    /// The end of the download, if it came before `start` stored the continuation (a task cancelled before it ran).
    private var pending: Result<RemoteFileInfo, Error>?
    private var info = RemoteFileInfo()
    private var written: Int64
    private var failure: Error?

    init(handle: FileHandle, requestedOffset: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.handle = handle
        self.requestedOffset = requestedOffset
        self.progress = progress
        written = requestedOffset
    }

    func start(_ task: URLSessionDataTask, _ continuation: CheckedContinuation<RemoteFileInfo, Error>) {
        lock.lock()
        if let pending {
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
        task.resume()
    }

    /// Ends the download: resumes the continuation, or keeps the result for `start` if it has not stored one yet.
    private func finish(_ result: Result<RemoteFileInfo, Error>) {
        lock.lock()
        guard let waiting = continuation else {
            if pending == nil { pending = result }
            lock.unlock()
            return
        }
        continuation = nil
        lock.unlock()
        waiting.resume(with: result)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if request.url?.scheme?.lowercased() == "https" {
            completionHandler(request)
        } else {
            failure = DownloadError.insecureRedirect(request.url ?? response.url ?? URL(fileURLWithPath: "/"))
            completionHandler(nil)
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard failure == nil else { return completionHandler(.cancel) }
        guard let http = response as? HTTPURLResponse else {
            failure = DownloadError.notHTTP
            return completionHandler(.cancel)
        }
        switch http.statusCode {
        case 200:
            // The whole file, whatever was asked: start the local file again.
            do {
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
            } catch {
                failure = error
                return completionHandler(.cancel)
            }
            written = 0
            info = URLSessionDownloader.info(of: http, size: URLSessionDownloader.contentLength(http))
        case 206:
            // `Content-Range: bytes START-END/TOTAL`: it must continue where the local file ends.
            let range = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            let parts = range.replacingOccurrences(of: "bytes ", with: "").split(separator: "/")
            let first = parts.first?.split(separator: "-").first.flatMap { Int64($0) }
            guard first == requestedOffset else {
                failure = DownloadError.unexpectedRange(range)
                return completionHandler(.cancel)
            }
            info = URLSessionDownloader.info(of: http, size: parts.count == 2 ? Int64(parts[1]) : nil)
        default:
            failure = URLSessionDownloader.failure(for: http, url: http.url ?? URL(fileURLWithPath: "/"))
            return completionHandler(.cancel)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            failure = error
            dataTask.cancel()
            return
        }
        written += Int64(data.count)
        progress?(written)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        progress = nil
        if let failure {
            finish(.failure(failure))
        } else if let error {
            finish(.failure(error))
        } else {
            finish(.success(info))
        }
    }
}
