import FeatureStore
import Foundation
import Testing

@testable import FeatureStoreBuilder

@Suite("Multipolygon assembly")
struct MultipolygonAssemblerTests {
    let block = Block()

    /// A node table: ID to a point at block fractions.
    private func nodes(_ spec: [Int64: (Double, Double)]) -> [Int64: PackedPoint] {
        spec.mapValues { block.point($0.0, $0.1) }
    }

    private func member(_ id: Int64, _ role: MultipolygonRole, _ nodeIDs: [Int64], _ table: [Int64: PackedPoint]) -> MultipolygonMember {
        let points = nodeIDs.compactMap { table[$0] }
        return MultipolygonMember(wayID: id, role: role, nodeIDs: nodeIDs, points: points.count == nodeIDs.count ? points : nil)
    }

    /// A square of four corner nodes numbered from `first`, from fractions (x0, y0) to (x1, y1).
    private func squareNodes(first: Int64, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Int64: (Double, Double)] {
        [first: (x0, y0), first + 1: (x1, y0), first + 2: (x1, y1), first + 3: (x0, y1)]
    }

    private func area(_ ring: [PackedPoint]) -> Double { projectedArea(ring) }

    private func signed(_ ring: [PackedPoint]) -> Double {
        var sum = 0.0
        for (a, b) in zip(ring, ring.dropFirst()) {
            sum += Double(a.longitude) * Mercator.y(latitude: Double(b.latitude)) - Double(b.longitude) * Mercator.y(latitude: Double(a.latitude))
        }
        return sum
    }

    @Test("A closed outer way is one polygon")
    func singleClosedWay() throws {
        let table = nodes(squareNodes(first: 1, 1, 1, 2, 2))
        let result = MultipolygonAssembler.assemble(members: [member(10, .outer, [1, 2, 3, 4, 1], table)], relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 1 && result.outlines.isEmpty)
        #expect(result.polygons[0].outer.count == 5 && result.polygons[0].inners.isEmpty)
        #expect(result.report == AssemblyReport())
    }

    @Test("Open ways that meet end to end form a ring, whatever their direction")
    func joinedWays() throws {
        let table = nodes(squareNodes(first: 1, 1, 1, 2, 2))
        // The second way is reversed, the third is listed first.
        let members = [
            member(30, .outer, [4, 1], table), member(10, .outer, [1, 2, 3], table), member(20, .outer, [4, 3], table),
        ]
        let result = MultipolygonAssembler.assemble(members: members, relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 1)
        #expect(Set(result.polygons[0].outer) == Set(table.values))
        #expect(result.polygons[0].outer.first == result.polygons[0].outer.last)
        // The member order does not change the result.
        #expect(MultipolygonAssembler.assemble(members: members.reversed(), relationIsComplete: true) == result)
    }

    @Test("A hole belongs to the outer ring that contains it, and the winding is normalized")
    func hole() throws {
        var spec = squareNodes(first: 1, 0.5, 0.5, 2.5, 2.5)
        spec.merge(squareNodes(first: 11, 1, 1, 2, 2)) { a, _ in a }
        let table = nodes(spec)
        // The outer is given clockwise and the inner counter-clockwise, to see them reversed.
        let outerWay = member(10, .outer, [1, 4, 3, 2, 1], table)
        let innerWay = member(20, .inner, [11, 12, 13, 14, 11], table)
        let result = MultipolygonAssembler.assemble(members: [innerWay, outerWay], relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 1 && result.polygons[0].inners.count == 1)
        #expect(signed(result.polygons[0].outer) > 0 && signed(result.polygons[0].inners[0]) < 0)
        #expect(area(result.polygons[0].inners[0]) < area(result.polygons[0].outer))
        #expect(result.polygons[0].rings.count == 2)
    }

    @Test("An island inside a hole is its own polygon, and holes go to the smallest outer ring")
    func island() {
        var spec = squareNodes(first: 1, 0.2, 0.2, 2.8, 2.8)       // outer lake shore
        spec.merge(squareNodes(first: 11, 0.6, 0.6, 2.4, 2.4)) { a, _ in a }  // hole
        spec.merge(squareNodes(first: 21, 1.2, 1.2, 1.8, 1.8)) { a, _ in a }  // island
        spec.merge(squareNodes(first: 31, 1.4, 1.4, 1.6, 1.6)) { a, _ in a }  // pond in the island
        let table = nodes(spec)
        let members = [
            member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .inner, [11, 12, 13, 14, 11], table),
            member(30, .outer, [21, 22, 23, 24, 21], table), member(40, .inner, [31, 32, 33, 34, 31], table),
        ]
        let result = MultipolygonAssembler.assemble(members: members, relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 2)
        let counts = result.polygons.map { ($0.outer, $0.inners.count) }
        let lake = counts.max { area($0.0) < area($1.0) }!
        let islandPolygon = counts.min { area($0.0) < area($1.0) }!
        #expect(lake.1 == 1 && islandPolygon.1 == 1)
        #expect(area(result.polygons.first { $0.outer == islandPolygon.0 }!.inners[0]) < area(islandPolygon.0))
    }

    @Test("Several outer rings give several polygons")
    func severalOuters() {
        var spec = squareNodes(first: 1, 0.2, 0.2, 1, 1)
        spec.merge(squareNodes(first: 11, 1.5, 1.5, 2.5, 2.5)) { a, _ in a }
        let table = nodes(spec)
        let result = MultipolygonAssembler.assemble(
            members: [member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .outer, [11, 12, 13, 14, 11], table)],
            relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 2)
    }

    @Test("An empty role counts as outer, other roles and duplicates are skipped")
    func roles() {
        let table = nodes(squareNodes(first: 1, 1, 1, 2, 2))
        let way = member(10, .outer, [1, 2, 3, 4, 1], table)
        #expect(MultipolygonRole(osmRole: "") == .outer && MultipolygonRole(osmRole: "outer") == .outer)
        #expect(MultipolygonRole(osmRole: "inner") == .inner && MultipolygonRole(osmRole: "outline") == .ignored)
        let skipped = member(11, .ignored, [1, 2], table)
        let result = MultipolygonAssembler.assemble(members: [way, way, skipped], relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 1 && result.report.duplicateMembers == 1)
    }

    @Test("An unclosed ring makes the relation incomplete and gives outlines, not polygons")
    func unclosed() {
        let table = nodes(squareNodes(first: 1, 1, 1, 2, 2))
        let result = MultipolygonAssembler.assemble(members: [member(10, .outer, [1, 2, 3, 4], table)], relationIsComplete: true)
        #expect(!result.isComplete && result.polygons.isEmpty && result.outlines.count == 1)
        #expect(result.report.unclosedChains == 1)
    }

    @Test("A closed ring is still only an outline when the relation is incomplete")
    func allOrNothing() {
        var spec = squareNodes(first: 1, 1, 1, 2, 2)
        spec.merge(squareNodes(first: 11, 0.2, 0.2, 0.6, 0.6)) { a, _ in a }
        let table = nodes(spec)
        let members = [member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .outer, [11, 12], table)]
        let result = MultipolygonAssembler.assemble(members: members, relationIsComplete: true)
        #expect(!result.isComplete && result.polygons.isEmpty && result.outlines.count == 2)
    }

    @Test("A missing member or the extract's incomplete flag makes it incomplete")
    func missingMember() {
        let table = nodes(squareNodes(first: 1, 1, 1, 2, 2))
        let closed = member(10, .outer, [1, 2, 3, 4, 1], table)
        let missing = MultipolygonMember(wayID: 20, role: .inner, nodeIDs: [], points: nil)
        let withMissing = MultipolygonAssembler.assemble(members: [closed, missing], relationIsComplete: true)
        #expect(!withMissing.isComplete && withMissing.report.missingMembers == 1 && withMissing.outlines.count == 1)
        let flagged = MultipolygonAssembler.assemble(members: [closed], relationIsComplete: false)
        #expect(!flagged.isComplete && flagged.polygons.isEmpty)
        // A missing node shows up as missing points.
        let partial = MultipolygonMember(wayID: 30, role: .outer, nodeIDs: [1, 2, 99], points: nil)
        #expect(!MultipolygonAssembler.assemble(members: [partial], relationIsComplete: true).isComplete)
    }

    @Test("A relation without an outer way is incomplete")
    func noOuter() {
        let table = nodes(squareNodes(first: 1, 1, 1, 2, 2))
        let result = MultipolygonAssembler.assemble(members: [member(10, .inner, [1, 2, 3, 4, 1], table)], relationIsComplete: true)
        #expect(!result.isComplete && result.polygons.isEmpty)
        #expect(!MultipolygonAssembler.assemble(members: [], relationIsComplete: true).isComplete)
    }

    @Test("An inner ring that no outer ring contains is ignored and counted")
    func orphanInner() {
        var spec = squareNodes(first: 1, 0.2, 0.2, 1, 1)
        spec.merge(squareNodes(first: 11, 2, 2, 2.5, 2.5)) { a, _ in a }
        let table = nodes(spec)
        let result = MultipolygonAssembler.assemble(
            members: [member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .inner, [11, 12, 13, 14, 11], table)],
            relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 1 && result.polygons[0].inners.isEmpty)
        #expect(result.report.orphanInnerRings == 1)
    }

    @Test("Degenerate rings are dropped and counted")
    func degenerate() {
        var spec = squareNodes(first: 1, 1, 1, 2, 2)
        spec[11] = (0.5, 0.5); spec[12] = (0.6, 0.5); spec[13] = (0.7, 0.5)  // three collinear points
        let table = nodes(spec)
        let result = MultipolygonAssembler.assemble(
            members: [member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .inner, [11, 12, 13, 11], table), member(21, .inner, [11, 12], table)],
            relationIsComplete: true)
        // The collinear ring has no area; the two-node way is an unclosed chain, so the relation is incomplete.
        #expect(result.report.degenerateRings >= 1)
        #expect(!result.isComplete)
        let onlyFlat = MultipolygonAssembler.assemble(
            members: [member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .inner, [11, 12, 13, 11], table)], relationIsComplete: true)
        #expect(onlyFlat.isComplete && onlyFlat.polygons[0].inners.isEmpty && onlyFlat.report.degenerateRings == 1)
    }

    @Test("Where three ways meet, the lowest way ID is taken first and the result does not depend on input order")
    func junction() {
        // A ring 1-2-3-4 where way 50 also leaves node 2 towards a dead end.
        var spec = squareNodes(first: 1, 1, 1, 2, 2)
        spec[9] = (0.5, 0.5)
        let table = nodes(spec)
        let members = [
            member(10, .outer, [1, 2], table), member(50, .outer, [2, 9], table), member(20, .outer, [2, 3], table),
            member(30, .outer, [3, 4], table), member(40, .outer, [4, 1], table),
        ]
        let a = MultipolygonAssembler.assemble(members: members, relationIsComplete: true)
        let b = MultipolygonAssembler.assemble(members: members.reversed(), relationIsComplete: true)
        #expect(a == b)
        // The dead-end way is left over as a chain, so the relation counts as incomplete rather than guessing.
        #expect(!a.isComplete && a.report.unclosedChains == 1)
    }

    @Test("Old-style tags are adopted only for exactly one outer way and a relation with only a type")
    func oldStyleTags() {
        #expect(MultipolygonAssembler.adoptsOuterWayTags(relationKeys: ["type"], outerWayCount: 1))
        #expect(MultipolygonAssembler.adoptsOuterWayTags(relationKeys: [], outerWayCount: 1))
        #expect(!MultipolygonAssembler.adoptsOuterWayTags(relationKeys: ["type", "natural"], outerWayCount: 1))
        #expect(!MultipolygonAssembler.adoptsOuterWayTags(relationKeys: ["type"], outerWayCount: 2))
        #expect(!MultipolygonAssembler.adoptsOuterWayTags(relationKeys: ["type"], outerWayCount: 0))
    }

    @Test("Assembled polygons clip to cells and keep their area")
    func clipsToCells() {
        var spec = squareNodes(first: 1, 0.5, 0.5, 2.5, 2.5)
        spec.merge(squareNodes(first: 11, 1, 1, 2, 2)) { a, _ in a }
        let table = nodes(spec)
        let result = MultipolygonAssembler.assemble(
            members: [member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .inner, [11, 12, 13, 14, 11], table)],
            relationIsComplete: true)
        // Even-odd fill: the area of the pieces of the outer ring minus the pieces of the hole equals the polygon's.
        let polygon = result.polygons[0]
        let outerPieces = CellSplitter.split(ring: polygon.outer).reduce(0) { $0 + area($1.piece.points) }
        let holePieces = CellSplitter.split(ring: polygon.inners[0]).reduce(0) { $0 + area($1.piece.points) }
        let expected = area(polygon.outer) - area(polygon.inners[0])
        #expect(abs((outerPieces - holePieces) - expected) < expected * 1e-4)
    }

    @Test("A hole that touches the outer ring at a vertex still belongs to it")
    func touchingHole() {
        var spec = squareNodes(first: 1, 1, 1, 2, 2)
        spec[11] = (1, 1)  // same position as node 1, but a different node
        spec[12] = (1.4, 1.2); spec[13] = (1.2, 1.4)
        var table = nodes(spec)
        table[11] = table[1]
        let result = MultipolygonAssembler.assemble(
            members: [member(10, .outer, [1, 2, 3, 4, 1], table), member(20, .inner, [11, 12, 13, 11], table)],
            relationIsComplete: true)
        #expect(result.isComplete && result.polygons[0].inners.count == 1 && result.report.orphanInnerRings == 0)
    }

    @Test("Hundreds of holes in one large outer ring are all assigned")
    func manyHoles() {
        var table: [Int64: PackedPoint] = [:]
        let outerNodes: [Int64] = [1, 2, 3, 4]
        for (id, spec) in squareNodes(first: 1, 0.1, 0.1, 2.9, 2.9) { table[id] = block.point(spec.0, spec.1) }
        var members = [member(1, .outer, outerNodes + [1], table)]
        var next: Int64 = 100
        for row in 0..<15 {
            for column in 0..<15 {
                let x = 0.2 + Double(column) * 0.18, y = 0.2 + Double(row) * 0.18
                for (id, spec) in squareNodes(first: next, x, y, x + 0.1, y + 0.1) { table[id] = block.point(spec.0, spec.1) }
                members.append(member(next, .inner, [next, next + 1, next + 2, next + 3, next], table))
                next += 4
            }
        }
        let result = MultipolygonAssembler.assemble(members: members, relationIsComplete: true)
        #expect(result.isComplete && result.polygons.count == 1)
        #expect(result.polygons[0].inners.count == 225 && result.report.orphanInnerRings == 0)
    }
}
