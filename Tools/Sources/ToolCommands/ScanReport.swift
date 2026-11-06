import OSMPBF

/// The result of scanning a whole file.
public struct ScanReport: Sendable {
    public let fileName: String
    public let fileSize: Int64
    public let header: OSMHeader
    public let blocks: Int
    public let nodes: Int
    public let ways: Int
    public let relations: Int
    public let decodeTime: Duration
    /// Peak heap footprint in bytes, or `nil` where unavailable.
    public let peakFootprint: Int64?
    /// Peak resident memory in bytes (includes touched pages of the mapped file).
    public let peakResident: Int64

    public init(
        fileName: String, fileSize: Int64, header: OSMHeader, blocks: Int, nodes: Int, ways: Int,
        relations: Int, decodeTime: Duration, peakFootprint: Int64?, peakResident: Int64
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.header = header
        self.blocks = blocks
        self.nodes = nodes
        self.ways = ways
        self.relations = relations
        self.decodeTime = decodeTime
        self.peakFootprint = peakFootprint
        self.peakResident = peakResident
    }
}
