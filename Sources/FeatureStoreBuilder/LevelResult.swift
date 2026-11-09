import Foundation

/// A level block as a file, with what went into it.
public struct LevelResult: Sendable {
    /// The store file.
    public let data: Data
    /// What was read and written.
    public let report: LevelReport
}
