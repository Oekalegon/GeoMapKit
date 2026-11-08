import GeoCore

/// The list of source regions, from the index that the data provider publishes.
///
/// The index holds the regions with their outlines and the places of their PBF files. Regions form a tree (a continent, its
/// countries, their states), and some overlap that tree: Geofabrik also lists aggregates such as the Alps. Which regions an
/// area needs is decided by ``regions(covering:samplesPerSide:maximumRegions:)``.
public struct RegionIndex: Sendable {
    /// All regions with a PBF file, in the order of the index.
    public let regions: [SourceRegion]
    private let indexByID: [String: Int]

    /// Creates an index from regions.
    ///
    /// - Parameter regions: The regions.
    /// - Throws: ``RegionError/duplicateRegion(_:)`` if two have the same ID.
    public init(regions: [SourceRegion]) throws {
        var indexByID: [String: Int] = [:]
        for (index, region) in regions.enumerated() where indexByID.updateValue(index, forKey: region.id) != nil {
            throw RegionError.duplicateRegion(region.id)
        }
        self.regions = regions
        self.indexByID = indexByID
    }

    /// The region with an identifier, or `nil`.
    ///
    /// - Parameter id: The identifier, for example `norway`.
    public func region(withID id: String) -> SourceRegion? {
        indexByID[id].map { regions[$0] }
    }

    /// Whether a region lies somewhere below another in the tree.
    ///
    /// - Parameters:
    ///   - id: The region.
    ///   - ancestorID: The region that may contain it, directly or through others.
    public func region(_ id: String, isBelow ancestorID: String) -> Bool {
        var current = region(withID: id)?.parentID
        var steps = 0
        // The loop is bounded, so a parent cycle in a bad index cannot hang it.
        while let parent = current, steps <= regions.count {
            if parent == ancestorID { return true }
            current = region(withID: parent)?.parentID
            steps += 1
        }
        return false
    }

    /// Chooses the regions whose files hold an area.
    ///
    /// The area is sampled on a grid of `samplesPerSide` × `samplesPerSide` points. The regions whose outline meets the area are
    /// taken from the smallest to the largest, and one is chosen if it covers points that no smaller chosen region covers. So
    /// an area in Norway gets the Norwegian part it lies in and not Norway or Europe, and an area on a border gets the
    /// regions on both sides. A region that has a chosen region below it is left out, because its file is the larger one
    /// for the same ground, and so are regions that add less than 1% of the points: a sliver of ground where the simplified
    /// outlines do not meet is no reason to fetch a whole country. The size of a region is the size of its outline, so
    /// an aggregate such as the Alps, larger than each of its countries, is only chosen where no country covers. If more
    /// regions are chosen than `maximumRegions`, the ones that cover most of the area are kept.
    ///
    /// - Parameters:
    ///   - box: The area. It must be valid.
    ///   - samplesPerSide: The points per side of the grid, 2 to 256. The default is 32.
    ///   - maximumRegions: The most regions to return, at least 1.
    /// - Returns: The regions, the one that covers most first, and the share of the area the returned regions cover. Empty, with a share of 0,
    ///   for an invalid box or an area no outline meets.
    public func regions(covering box: BoundingBox, samplesPerSide: Int = 32, maximumRegions: Int = 8) -> RegionSelection {
        guard box.isValid else { return RegionSelection(regions: [], coveredShare: 0) }
        let side = min(max(samplesPerSide, 2), 256)
        var points: [Coordinate] = []
        points.reserveCapacity(side * side)
        for row in 0..<side {
            for column in 0..<side {
                points.append(
                    Coordinate(
                        latitude: box.south + (box.north - box.south) * (Double(row) + 0.5) / Double(side),
                        longitude: box.west + (box.east - box.west) * (Double(column) + 0.5) / Double(side)))
            }
        }

        // The points of the area each candidate covers.
        var candidates: [(region: SourceRegion, covered: [Int])] = []
        for region in regions where !(region.boundingBox.north < box.south || region.boundingBox.south > box.north
            || region.boundingBox.east < box.west || region.boundingBox.west > box.east)
        {
            let covered = points.indices.filter { region.contains(points[$0]) }
            if !covered.isEmpty { candidates.append((region, covered)) }
        }
        candidates.sort { ($0.region.approximateArea, $0.region.id) < ($1.region.approximateArea, $1.region.id) }

        let minimumNew = max(1, Int((Double(points.count) * 0.01).rounded(.up)))
        var done = [Bool](repeating: false, count: points.count)
        var chosen: [(region: SourceRegion, covered: [Int])] = []
        for candidate in candidates {
            if chosen.contains(where: { region($0.region.id, isBelow: candidate.region.id) }) { continue }
            let new = candidate.covered.filter { !done[$0] }
            guard new.count >= minimumNew else { continue }
            for point in new { done[point] = true }
            chosen.append((candidate.region, candidate.covered))
        }
        // The region that covers most of the area is the preferred source, and the one kept when there are too many.
        chosen.sort { ($1.covered.count, $0.region.id) < ($0.covered.count, $1.region.id) }
        chosen = Array(chosen.prefix(max(maximumRegions, 1)))
        var covered = [Bool](repeating: false, count: points.count)
        for entry in chosen { for point in entry.covered { covered[point] = true } }
        return RegionSelection(
            regions: chosen.map(\.region), coveredShare: Double(covered.lazy.filter { $0 }.count) / Double(points.count))
    }
}
