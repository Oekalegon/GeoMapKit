import Foundation

/// Reads an OpenStreetMap PBF file block by block.
///
/// The file is memory-mapped, and each data block is decoded, handed to the
/// caller and released, so memory use does not grow with the size of the file.
/// All sizes in the file are untrusted and checked (see ``PBFError``).
///
/// ```swift
/// let reader = try PBFReader(url: fileURL)
/// try reader.forEachBlock { block in
///     for way in block.ways where way.tagValue(forKey: "highway") != nil { /* ... */ }
/// }
/// ```
public struct PBFReader: Sendable {
    private let container: PBFContainer

    /// Opens a PBF file by memory-mapping it.
    ///
    /// - Parameter url: The file URL.
    /// - Throws: An error if the file cannot be read.
    public init(url: URL) throws {
        self.init(data: try Data(contentsOf: url, options: .alwaysMapped))
    }

    /// Reads PBF data that is already in memory.
    ///
    /// - Parameter data: The complete contents of a PBF file.
    public init(data: Data) {
        self.container = PBFContainer(data)
    }

    /// Reads the header block, which must be the first blob in the file.
    ///
    /// - Returns: The decoded header.
    /// - Throws: ``PBFError/missingHeader`` if the file does not start with a
    ///   header, ``PBFError/unsupportedRequiredFeature(_:)`` if the file needs a
    ///   feature this reader lacks, or another ``PBFError`` if the data is malformed.
    public func header() throws -> OSMHeader {
        var header: OSMHeader?
        try container.forEachBlob { type, payload in
            guard type == "OSMHeader" else { throw PBFError.missingHeader }
            header = try HeaderBlockDecoder.decode(payload)
            return false
        }
        guard let header else { throw PBFError.missingHeader }
        return header
    }

    /// Decodes every data block in the file and passes it to `body`.
    ///
    /// The header is validated first. Blobs of unknown types are skipped.
    ///
    /// - Parameters:
    ///   - kinds: The object kinds to decode. Other kinds are skipped without being
    ///     decoded, which makes passes that need only one kind much cheaper. Blocks
    ///     are still decompressed.
    ///   - body: Called once per data block, in file order.
    /// - Throws: ``PBFError`` if the file is malformed, or whatever `body` throws.
    public func forEachBlock(kinds: OSMObjectKinds = .all, _ body: (OSMBlock) throws -> Void) throws {
        var sawHeader = false
        try container.forEachBlob { type, payload in
            if !sawHeader {
                guard type == "OSMHeader" else { throw PBFError.missingHeader }
                _ = try HeaderBlockDecoder.decode(payload)
                sawHeader = true
            } else if type == "OSMData" {
                try body(PrimitiveBlockDecoder.decode(payload, kinds: kinds))
            }
            return true
        }
        guard sawHeader else { throw PBFError.missingHeader }
    }
}
