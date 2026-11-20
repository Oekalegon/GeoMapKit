/// Something that was not imported, and why.
public struct ImportFailure: Sendable, Equatable {
    /// The request it came from (a file name).
    public let source: String
    /// The activity, or `nil` for a failure of the whole source (a file that cannot be read).
    public let activityID: String?
    /// The reason, in words.
    public let message: String
}
