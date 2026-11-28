import Foundation

/// What building a map on the phone takes, shown before it starts.
public struct PhoneBuildPlan: Equatable, Sendable {
    public let id: UUID
    /// The source regions whose files are needed, for example "Utrecht".
    public let regionNames: [String]
    /// What would be downloaded, in bytes: the files the phone doesn't have yet, or `nil` if a server didn't say.
    public let downloadBytes: Int64?
    /// The free space on the phone in bytes, or `nil` if unknown.
    public let availableBytes: Int64?

    public init(id: UUID = UUID(), regionNames: [String], downloadBytes: Int64?, availableBytes: Int64?) {
        self.id = id
        self.regionNames = regionNames
        self.downloadBytes = downloadBytes
        self.availableBytes = availableBytes
    }
}
