import FeatureStore
import GeoCore
import OSMPBF

/// Turns classified features into stored pieces: per band, simplified, clipped to cells, and written.
struct FeatureEmitter {
    var writer: FeatureStoreWriter
    var report = BuildReport()
    let profile: BuildProfile
    let columns: ClosedRange<Int>?
    let rows: ClosedRange<Int>?
    let zoom = 13

    init(writer: FeatureStoreWriter, profile: BuildProfile, columns: ClosedRange<Int>?, rows: ClosedRange<Int>?) {
        self.writer = writer
        self.profile = profile
        self.columns = columns
        self.rows = rows
    }

    /// Whether a cell lies fully inside the cut area, and so is written.
    func isWritten(_ tile: TileID) -> Bool {
        guard let columns, let rows else { return false }
        return columns.contains(tile.x) && rows.contains(tile.y)
    }

    /// The tags kept in every band, by class (the values only, and only where the feature has them).
    ///
    /// A style selects by tag with `StyleVariant`; the lower bands hold no tags but these, so only these can be selected by at zoom 14 and
    /// below. They are the surface and the difficulty of the paths, tracks and roads a runner chooses between, and the kind of railway.
    static let keptTags: [FeatureClass: [String]] = [
        .path: ["surface", "smoothness", "sac_scale", "mtb:scale", "trail_visibility", "tracktype"],
        .track: ["tracktype", "surface", "smoothness", "sac_scale", "mtb:scale", "trail_visibility"],
        .roadMajor: ["surface"],
        .roadMinor: ["surface", "smoothness"],
        .roadService: ["surface"],
        .railway: ["gauge", "electrified", "usage", "service"],
    ]

    mutating func emit(_ spec: FeatureSpec) throws {
        let classification = spec.classification
        if profile == .watch && !classification.showsOnWatch {
            report.featuresSkippedByProfile += 1
            return
        }
        report.featuresByClass[classification.featureClass, default: 0] += 1

        let nameID = (ClassifierTagArray(spec.tags).value(forKey: "name") ?? spec.fallbackName).map { writer.intern($0) }
        var tags: [StoredTag] = []
        if profile == .full {
            tags = spec.tags.map { StoredTag(key: writer.intern($0.key), value: writer.intern($0.value)) }
        }
        // A `landUse` feature keeps the value of its tag in every band (a style selects by it), and a place its `population`; other
        // classes have their tags in the detail band only.
        var valueTags: [StoredTag] = []
        if classification.featureClass == .landUse {
            let tagArray = ClassifierTagArray(spec.tags)
            for key in ["landuse", "natural"] {
                if let value = tagArray.value(forKey: key) { valueTags.append(StoredTag(key: writer.intern(key), value: writer.intern(value))) }
            }
        }
        // A place keeps its `population` in every band: the style ranks the names of places by it (question 52).
        if classification.featureClass == .place,
            let population = ClassifierTagArray(spec.tags).value(forKey: "population"), PlacePopulation.population(population) != nil
        {
            valueTags.append(StoredTag(key: writer.intern("population"), value: writer.intern(population)))
        }
        // The tags a style may select by (question 55: the surface and difficulty of a path, the gauge of a track) are kept in every band,
        // as values only, so a style that colours paths by surface does it at zoom 12 as well as at zoom 15.
        // The Watch copy has no variants in its style, so it does not carry them.
        let tagArray = ClassifierTagArray(spec.tags)
        for key in profile == .full ? (Self.keptTags[classification.featureClass] ?? []) : [] {
            if let value = tagArray.value(forKey: key) { valueTags.append(StoredTag(key: writer.intern(key), value: writer.intern(value))) }
        }
        for band in ZoomBand.allCases where band >= classification.minimumBand && band <= spec.lastBand {
            if profile == .watch && band == .overview { continue }
            try emit(spec, band: band, nameID: nameID, tags: band == .detail ? tags : valueTags)
        }
    }

    private mutating func emit(_ spec: FeatureSpec, band: ZoomBand, nameID: UInt32?, tags: [StoredTag]) throws {
        let classification = spec.classification
        let tolerance = GeometrySimplifier.tolerance(for: band)

        func feature(
            kind: FeatureKind, flags: FeatureFlags, offset: UInt32, parts: [GeometryPart]
        ) -> StoredFeature {
            StoredFeature(
                classID: classification.featureClass.rawValue, subclass: classification.subclass, kind: kind,
                objectType: spec.objectType, objectID: spec.objectID, flags: flags.union(spec.extraFlags),
                offsetAlongLine: offset, nameID: nameID, tags: tags, parts: parts)
        }

        switch spec.geometry {
        case .point(let point):
            guard let cell = CellRect.tile(owning: point, zoom: zoom), isWritten(cell) else {
                if band == .detail { report.piecesOutsideCells += 1 }
                return
            }
            try writer.add(
                feature(kind: .point, flags: [], offset: 0, parts: [GeometryPart(points: [point])]), band: band, cell: cell)

        case .lines(let lines):
            for line in lines {
                let simplified = tolerance.map { GeometrySimplifier.simplify(line: line, tolerance: $0) } ?? line
                for (cell, piece) in CellSplitter.split(line: simplified, zoom: zoom) {
                    guard isWritten(cell) else {
                        if band == .detail { report.piecesOutsideCells += 1 }
                        continue
                    }
                    try writer.add(
                        feature(kind: .line, flags: piece.flags, offset: piece.offsetCentimetres,
                            parts: [GeometryPart(points: piece.points)]),
                        band: band, cell: cell)
                }
            }

        case .rings(let rings):
            var partsByCell: [TileID: [GeometryPart]] = [:]
            for ring in rings {
                let simplified: [PackedPoint]?
                if let tolerance { simplified = GeometrySimplifier.simplify(ring: ring, tolerance: tolerance) } else { simplified = ring }
                guard let simplified else {
                    // Too small for this band (a shed at the 5 m of the mid band): counted, so the loss is visible.
                    if band == .mid { report.ringsTooSmallForMid += 1 }
                    continue
                }
                for (cell, piece) in CellSplitter.split(ring: simplified, zoom: zoom) {
                    guard isWritten(cell) else {
                        if band == .detail { report.piecesOutsideCells += 1 }
                        continue
                    }
                    partsByCell[cell, default: []].append(piece.part)
                }
            }
            for cell in partsByCell.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                guard let parts = Self.withoutCancellingSquares(partsByCell[cell] ?? [], in: cell), !parts.isEmpty else { continue }
                try writer.add(feature(kind: .area, flags: [], offset: 0, parts: parts), band: band, cell: cell)
            }
        }
    }

    /// Removes the pairs of parts that are the whole cell square.
    ///
    /// The fill rule is even-odd, so an outer ring that covers the cell and a hole that covers it too cancel: the cell
    /// holds nothing of the area. Storing both would cost bytes in every band, and the renderer would fill the square
    /// twice and leave a faint seam along the cell border where anti-aliasing does not cancel exactly. This happens for
    /// every cell inside an island in the sea. An odd number leaves one square.
    static func withoutCancellingSquares(_ parts: [GeometryPart], in cell: TileID) -> [GeometryPart]? {
        let rect = CellRect(tile: cell)
        let corners: Set<PackedPoint> = [
            PackedPoint(longitude: rect.west, latitude: rect.north), PackedPoint(longitude: rect.east, latitude: rect.north),
            PackedPoint(longitude: rect.east, latitude: rect.south), PackedPoint(longitude: rect.west, latitude: rect.south),
        ]
        func isSquare(_ part: GeometryPart) -> Bool { part.points.count == 5 && Set(part.points) == corners }
        let squares = parts.filter(isSquare)
        guard squares.count >= 2 else { return parts }
        var result = parts.filter { !isSquare($0) }
        if squares.count % 2 == 1 { result.append(squares[0]) }
        return result
    }
}
