import GeoCore

/// The header block of a PBF file.
public struct OSMHeader: Hashable, Sendable {
    /// The bounding box of the data, if the file declares one.
    public let boundingBox: BoundingBox?

    /// Features a reader must support to read the file (for example `DenseNodes`).
    public let requiredFeatures: [String]

    /// Features a reader may use but can ignore (for example `Sort.Type_then_ID`).
    public let optionalFeatures: [String]

    /// The program that wrote the file, if declared.
    public let writingProgram: String?

    /// The source of the data, if declared.
    public let source: String?

    /// Creates a header.
    ///
    /// - Parameters:
    ///   - boundingBox: The declared bounding box, if any.
    ///   - requiredFeatures: The required features.
    ///   - optionalFeatures: The optional features.
    ///   - writingProgram: The writing program, if declared.
    ///   - source: The data source, if declared.
    public init(
        boundingBox: BoundingBox? = nil,
        requiredFeatures: [String] = [],
        optionalFeatures: [String] = [],
        writingProgram: String? = nil,
        source: String? = nil
    ) {
        self.boundingBox = boundingBox
        self.requiredFeatures = requiredFeatures
        self.optionalFeatures = optionalFeatures
        self.writingProgram = writingProgram
        self.source = source
    }
}
