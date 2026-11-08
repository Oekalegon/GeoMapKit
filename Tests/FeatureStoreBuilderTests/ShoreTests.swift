import FeatureStore
import Foundation
import OSMPBF
import Testing

@testable import FeatureStoreBuilder

/// Lines where land, water and sea meet: outlines, river mouths, centre lines and the borders of parks.
@Suite("Shores, outlines and park borders")
struct ShoreTests {
    private func point(_ longitude: Double, _ latitude: Double) -> PackedPoint {
        PackedPoint(longitude: Int32(longitude * 1e7), latitude: Int32(latitude * 1e7))
    }

    // MARK: Line splitter

    @Test("A line is cut where the answer changes, and the stretches together are the line")
    func splitter() {
        let line = [point(10.0, 60.0), point(10.01, 60.0)]
        let stretches = LineSplitter.split(line, spacing: 25) { $0.point.longitude > 100_050_000 }
        #expect(stretches.count == 2)
        #expect(stretches[0].answer == false && stretches[1].answer == true)
        #expect(stretches[0].points.first == line[0] && stretches[1].points.last == line[1])
        #expect(stretches[0].points.last == stretches[1].points.first, "the stretches join")
        // The cut is within one spacing (25 m is about 0.00045 degrees of longitude at 60 degrees) of the change.
        #expect(abs(Int(stretches[0].points.last?.longitude ?? 0) - 100_050_000) < 6_000)
    }

    @Test("Removing keeps the other stretches and counts the removed ones")
    func removing() {
        let line = [point(10.0, 60.0), point(10.01, 60.0)]
        let result = LineSplitter.removing(from: [line], spacing: 25) { $0.point.longitude > 100_030_000 && $0.point.longitude < 100_060_000 }
        #expect(result.dropped == 1 && result.kept.count == 2)
        let nothing = LineSplitter.removing(from: [line], spacing: 25) { _ in true }
        #expect(nothing.kept.isEmpty && nothing.dropped == 1)
        let everything = LineSplitter.removing(from: [line], spacing: 25) { _ in false }
        #expect(everything.kept == [line] && everything.dropped == 0)
    }

    @Test("A line of one point, and a segment of no length, give nothing")
    func splitterDegenerate() {
        #expect(LineSplitter.split([point(10, 60)], spacing: 25) { _ in true }.isEmpty)
        #expect(LineSplitter.split([point(10, 60), point(10, 60)], spacing: 25) { _ in true }.isEmpty)
    }

    // MARK: Sea lookup

    @Test("A point is in the sea inside the outer ring, and not in a hole")
    func seaLookup() {
        let outer = [point(10, 60), point(11, 60), point(11, 61), point(10, 61), point(10, 60)]
        let island = [point(10.4, 60.4), point(10.6, 60.4), point(10.6, 60.6), point(10.4, 60.6), point(10.4, 60.4)]
        let lookup = SeaLookup(rings: [outer, island])
        #expect(lookup.contains(point(10.2, 60.2)))
        #expect(!lookup.contains(point(10.5, 60.5)), "the island is a hole")
        #expect(!lookup.contains(point(9.5, 60.5)) && !lookup.contains(point(10.5, 62)) && !lookup.contains(point(10.5, 59)))
        #expect(!SeaLookup(rings: []).contains(point(10, 60)))
    }

    // MARK: Segment grid

    @Test("A point near a segment is on it, and one far from it is not")
    func segmentGrid() {
        var grid = SegmentGrid()
        grid.add(points: [(x: 0, y: 0), (x: 100, y: 0)])
        #expect(grid.isNear(x: 50, y: 4, tolerance: 6))
        #expect(!grid.isNear(x: 50, y: 8, tolerance: 6))
        #expect(!grid.isNear(x: 140, y: 0, tolerance: 6))
        #expect(grid.isNear(x: 103, y: 0, tolerance: 6), "beyond the end, within the tolerance")
    }

    // MARK: The builder

    private func build(_ world: inout SyntheticWorld) throws -> (file: FeatureStoreFile, report: BuildReport) {
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        try file.verify()
        return (file, result.report)
    }

    @Test("A lake gets an outline of its own, and a river inside it no centre line")
    func lakeOutlineAndRiver() throws {
        var world = SyntheticWorld()
        let lake = world.rectangle(first: 10, 0.5, 0.5, 2.5, 1.0)
        world.way(100, lake, [("natural", "water")])
        // A river that crosses the lake and goes on at both ends, and one that is wholly in it.
        world.node(20, 0.2, 0.75); world.node(21, 2.8, 0.75)
        world.way(101, [20, 21], [("waterway", "river")])
        world.node(22, 1.0, 0.7); world.node(23, 2.0, 0.8)
        world.way(102, [22, 23], [("waterway", "stream")])
        let (_, report) = try build(&world)
        #expect(report.featuresByClass[.waterArea] == 1 && report.featuresByClass[.waterEdge] == 1)
        #expect(report.featuresByClass[.waterLine] == 1, "the river is kept where it is outside the lake; the stream is gone")
        #expect(report.waterLineStretchesInWater == 2)
    }

    @Test("A coastline through the water of a river is not drawn; the outline of the river along the sea is left to the coast")
    func riverMouth() throws {
        var world = SyntheticWorld()
        // The coast runs east at y 1.5 with land to the north; the river to the north of it touches the coast.
        world.node(1, -0.3, 1.5); world.node(2, 1.5, 1.5); world.node(3, 3.3, 1.5)
        world.way(10, [1, 2, 3], [("natural", "coastline")])
        let river = world.rectangle(first: 20, 0.5, 0.3, 2.5, 1.5)
        world.way(11, river, [("natural", "water")])
        let (_, report) = try build(&world)
        #expect(report.coastlineStretchesInRivers >= 1, "the part of the coast that lies along the river's mouth")
        #expect(report.featuresByClass[.coastline] == 1, "the rest of the coast stays")
        #expect(report.featuresByClass[.waterEdge] == 1, "the other three sides of the river")
    }

    @Test("A coastline with a lake on its sea side, or with a lake that only touches it, is kept whole")
    func coastNotInWater() throws {
        var world = SyntheticWorld()
        world.node(1, -0.3, 1.5); world.node(2, 1.5, 1.5); world.node(3, 3.3, 1.5)
        world.way(10, [1, 2, 3], [("natural", "coastline")])
        let lake = world.rectangle(first: 20, 0.5, 1.5, 2.5, 2.5)
        world.way(11, lake, [("natural", "water")])
        let (_, report) = try build(&world)
        #expect(report.coastlineStretchesInRivers == 0)
    }

    @Test("A park border is green on land and blue in the sea")
    func parkBorderSea() throws {
        var world = SyntheticWorld()
        world.node(1, -0.3, 1.5); world.node(2, 1.5, 1.5); world.node(3, 3.3, 1.5)
        world.way(10, [1, 2, 3], [("natural", "coastline")])
        let park = world.rectangle(first: 20, 0.5, 1.0, 2.5, 2.0)
        world.way(11, park, [("boundary", "protected_area"), ("name", "Park")])
        let onLand = world.rectangle(first: 30, 0.5, 0.2, 2.5, 0.8)
        world.way(12, onLand, [("leisure", "nature_reserve")])
        let (file, report) = try build(&world)
        #expect(report.featuresByClass[.parkBorder] == 2 && report.featuresByClass[.parkBorderSea] == 1)
        #expect(report.parkBorderStretchesInSea == 1)
        #expect(report.featuresByClass[.boundary] == nil)
        // Every piece is a line, never an area.
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .detail)
            where feature.classID == FeatureClass.parkBorder.rawValue || feature.classID == FeatureClass.parkBorderSea.rawValue {
                #expect(feature.kind == .line)
            }
        }
    }

    @Test("A park border without a sea is all land")
    func parkBorderWithoutSea() throws {
        var world = SyntheticWorld()
        let park = world.rectangle(first: 20, 0.5, 1.0, 2.5, 2.0)
        world.way(11, park, [("boundary", "national_park")])
        let (_, report) = try build(&world)
        #expect(report.featuresByClass[.parkBorder] == 1 && report.featuresByClass[.parkBorderSea] == nil)
    }

    @Test("The border of a protected area that is a relation of type boundary is drawn once, from its untagged ways")
    func parkBorderRelation() throws {
        var world = SyntheticWorld()
        world.node(1, 0.5, 1.0); world.node(2, 2.5, 1.0); world.node(3, 2.5, 2.0); world.node(4, 0.5, 2.0)
        world.way(11, [1, 2, 3], [])
        world.way(12, [3, 4, 1], [])
        world.relation(50, [(11, "outer", 1), (12, "outer", 1)], [("type", "boundary"), ("boundary", "protected_area"), ("name", "Park")])
        // A relation of type boundary that is not a protected area is no multipolygon and gets nothing.
        world.relation(51, [(11, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "8")])
        let (_, report) = try build(&world)
        #expect(report.featuresByClass[.parkBorder] == 1)
        #expect(report.waysSuppressed == 2 && report.waysStored == 0)
    }

    @Test("A way that is the border of a protected area and a member of its relation is drawn only with the relation")
    func parkBorderTaggedMembers() throws {
        var world = SyntheticWorld()
        let ring = world.rectangle(first: 1, 0.5, 1.0, 2.5, 2.0)
        world.way(11, ring, [("boundary", "protected_area")])
        world.relation(50, [(11, "outer", 1)], [("type", "boundary"), ("boundary", "protected_area")])
        let (_, report) = try build(&world)
        #expect(report.featuresByClass[.parkBorder] == 1)
        #expect(report.waysSuppressed == 1)
    }

    @Test("A pier is in the mid band, and the Watch copy does not have it")
    func pier() throws {
        var world = SyntheticWorld()
        world.node(1, 1.0, 1.0); world.node(2, 1.0, 1.05)
        world.way(10, [1, 2], [("man_made", "pier")])
        let (file, report) = try build(&world)
        #expect(report.featuresByClass[.pier] == 1)
        var found = 0
        for cell in try file.cells() {
            found += try file.features(in: cell, band: .mid).filter { $0.classID == FeatureClass.pier.rawValue }.count
            #expect(try file.features(in: cell, band: .overview).filter { $0.classID == FeatureClass.pier.rawValue }.isEmpty)
        }
        #expect(found >= 1)
        let watch = try FeatureStoreBuilder(profile: .watch).build(from: try world.extract())
        #expect(watch.report.featuresByClass[.pier] == nil)
    }
}
