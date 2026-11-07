import Foundation

/// The finished file and the report of how it was made.
public struct BuildResult: Sendable {
    /// The feature store file, ready to write to disk or open with `FeatureStoreFile`.
    public let data: Data
    /// What was stored, skipped and counted.
    public let report: BuildReport
}
