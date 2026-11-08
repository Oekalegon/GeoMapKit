import Foundation

/// An error of the network side of the source data manager.
public enum DownloadError: Error, Equatable, Sendable {
    /// The server answered with a status that is neither success nor, for a conditional question, "not modified".
    case httpStatus(Int, URL)
    /// A redirect led from `https` to a weaker scheme; it is not followed.
    case insecureRedirect(URL)
    /// The response is not an HTTP response.
    case notHTTP
    /// A partial answer starts somewhere other than where the download asked for. The text is the `Content-Range` header.
    case unexpectedRange(String)
}

extension DownloadError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .httpStatus(let status, let url): "The server answered \(status) for \(url.absoluteString)."
        case .insecureRedirect(let url): "The server redirected to \(url.absoluteString), which is not https; it was not followed."
        case .notHTTP: "The answer was not an HTTP response."
        case .unexpectedRange(let range): "The server sent a part of the file that does not continue the one held (Content-Range: \(range))."
        }
    }
}
