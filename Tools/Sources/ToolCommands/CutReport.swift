import GeoCore
import MapBuilder

/// The result of cutting an area out of a file.
public struct CutReport: Sendable {
    public let fileName: String
    public let fileSize: Int64
    public let area: BoundingBox
    public let passes: [PassTiming]
    public let totalTime: Duration
    public let summary: ExtractSummary
    /// Peak heap footprint in bytes, or `nil` where unavailable.
    public let peakFootprint: Int64?
    /// Peak resident memory in bytes (includes touched pages of the mapped file).
    public let peakResident: Int64

    public init(
        fileName: String, fileSize: Int64, area: BoundingBox, passes: [PassTiming], totalTime: Duration,
        summary: ExtractSummary, peakFootprint: Int64?, peakResident: Int64
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.area = area
        self.passes = passes
        self.totalTime = totalTime
        self.summary = summary
        self.peakFootprint = peakFootprint
        self.peakResident = peakResident
    }
}
