import FeatureStore

/// What one coarse level of a set of blocks holds (question 50).
///
/// A level serves the zooms above `topZoom - 1` up to `topZoom`. Its cells have the storage zoom `topZoom + 2`, so a view
/// at those zooms touches about the same number of cells at every level, and it has one band, whose geometry is
/// simplified for the top of the range.
public struct LevelSpec: Sendable, Equatable {
    /// The highest zoom the level serves, 1 to 10.
    public let topZoom: Int
    /// The classes the level holds: the classes the style shows at the top zoom.
    public let classes: Set<UInt8>

    /// Whether the level holds a feature of a class and subclass. The classes are those the style shows at the top zoom; of the major
    /// roads a coarse level holds only the main ones, because a country of secondary and tertiary roads is a grey tangle at the
    /// scale of a province, and every one of them costs bytes: from the top zoom 9 all of them, 8 the motorways, trunk, primary and
    /// secondary roads, 7 and 6 the first three, 5 and below the motorways and trunk roads. The links go from the top zoom 8 on.
    ///
    /// - Parameters:
    ///   - classID: The raw class ID.
    ///   - subclass: The subclass byte (the bridge and tunnel bits are ignored).
    public func holds(classID: UInt8, subclass: UInt8) -> Bool {
        guard classes.contains(classID) else { return false }
        guard classID == FeatureClass.roadMajor.rawValue else { return true }
        // Only the grades the classifier knows are left out; a road with another or no grade stays.
        let value = SubclassBits.value(of: subclass)
        let links: ClosedRange<UInt8> = 9...13
        switch topZoom {
        case 9...: return true
        case 8: return value != 5 && !links.contains(value)
        case 6...7: return !(4...5).contains(value) && !links.contains(value)
        default: return !(3...5).contains(value) && !links.contains(value)
        }
    }

    /// The zoom of the cells of the level, `topZoom + 2`.
    public var storageZoom: Int { topZoom + 2 }

    /// One pixel of a 256-pixel tile at the top zoom, in projected radians.
    var pixel: Double { 2 * .pi / (256 * Double(1 << topZoom)) }
    /// The Douglas–Peucker tolerance: half a pixel at the top zoom.
    var tolerance: Double { 0.5 * pixel }
    /// A feature whose bounding box is smaller than three pixels is left out.
    var minimumExtent: Double { 3 * pixel }
    /// A line that is part of a network that is big enough (see `minimumExtent`) is left out when it is itself shorter than half a
    /// pixel: the ways of a road are cut at every junction, and a country has more of them than a level can hold. The hole it leaves
    /// in a road is under half a pixel at the top zoom.
    var minimumChainExtent: Double { 0.5 * pixel }
    /// A water area whose mean width (2 × area ÷ perimeter) is under half a pixel is a canal or a ditch, a line and not a surface: it is
    /// left out, with its outline. The bounding box is no test for this, because a ditch is kilometres long.
    var minimumWaterWidth: Double { 0.5 * pixel }
    /// A water area smaller than 8 square pixels (a pond, not a lake) is left out, with its outline.
    var minimumWaterArea: Double { 8 * pixel * pixel }

    /// - Parameters:
    ///   - topZoom: The highest zoom the level serves (1 to 10).
    ///   - classes: The raw class IDs the level holds.
    /// - Throws: ``LevelError/invalidTopZoom(_:)`` for a zoom outside 1 to 10.
    public init(topZoom: Int, classes: Set<UInt8>) throws {
        guard StoreManifest.Level.topZooms.contains(topZoom) else { throw LevelError.invalidTopZoom(topZoom) }
        self.topZoom = topZoom
        self.classes = classes
    }
}
