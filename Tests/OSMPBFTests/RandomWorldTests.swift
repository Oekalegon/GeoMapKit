import Foundation
import Testing
import GeoCore
import PBFTestSupport
@testable import OSMPBF

/// A small deterministic random number generator, so a failing world can be reproduced from its seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct WorldNode { var id: Int64; var latitude: Int64; var longitude: Int64; var tags: [String: String] }
private struct WorldWay { var id: Int64; var nodeIDs: [Int64]; var tags: [String: String] }
private struct WorldMember { var type: OSMMemberType; var id: Int64; var role: String }
private struct WorldRelation { var id: Int64; var members: [WorldMember]; var tags: [String: String] }

/// A random world plus an independent, deliberately simple reference cut, to check the
/// cutter and the compact extract against plain dictionaries and sets.
private struct World {
    static let keys = ["highway", "name", "surface", "amenity", "natural", "access"]
    static let values = ["path", "track", "a", "b", "gravel", "yes", "cafe", "peak", "Färchaneggweg", "日本語"]
    static let roles = ["", "outer", "inner", "stop"]

    var nodes: [WorldNode] = []
    var ways: [WorldWay] = []
    var relations: [WorldRelation] = []
    var box = BoundingBox(south: 0, west: 0, north: 1, east: 1)

    init(seed: UInt64) {
        var random = SplitMix64(state: seed)
        func tags(maximum: Int) -> [String: String] {
            var result: [String: String] = [:]
            for key in World.keys.shuffled(using: &random).prefix(Int.random(in: 0...maximum, using: &random)) {
                result[key] = World.values.randomElement(using: &random)
            }
            return result
        }
        for index in 0..<Int.random(in: 60...140, using: &random) {
            nodes.append(WorldNode(
                id: 1000 + Int64(index),
                latitude: Int64((Double.random(in: 46...49, using: &random) * 1e7).rounded()),
                longitude: Int64((Double.random(in: 8...11, using: &random) * 1e7).rounded()),
                tags: Int.random(in: 0..<5, using: &random) == 0 ? tags(maximum: 3) : [:]
            ))
        }
        for index in 0..<Int.random(in: 15...40, using: &random) {
            let ids = nodes.map(\.id).shuffled(using: &random).prefix(Int.random(in: 2...6, using: &random))
            ways.append(WorldWay(id: 5000 + Int64(index), nodeIDs: Array(ids), tags: tags(maximum: 3)))
        }
        for index in 0..<Int.random(in: 4...12, using: &random) {
            var members: [WorldMember] = []
            for _ in 0..<Int.random(in: 1...5, using: &random) {
                let role = World.roles.randomElement(using: &random) ?? ""
                switch Int.random(in: 0..<10, using: &random) {
                case 0: members.append(WorldMember(type: .way, id: 9_000_000, role: role))     // not in the file
                case 1: members.append(WorldMember(type: .node, id: 9_000_001, role: role))    // not in the file
                case 2...4: members.append(WorldMember(type: .node, id: nodes.randomElement(using: &random)?.id ?? 0, role: role))
                default: members.append(WorldMember(type: .way, id: ways.randomElement(using: &random)?.id ?? 0, role: role))
                }
            }
            relations.append(WorldRelation(id: 7000 + Int64(index), members: members, tags: tags(maximum: 2)))
        }
        let south = Double.random(in: 46...48.2, using: &random)
        let west = Double.random(in: 8...10.2, using: &random)
        box = BoundingBox(south: south, west: west, north: south + 0.8, east: west + 0.8)
    }

    /// The file: nodes in two blocks, then ways, then relations, with tags in an arbitrary (not sorted) order.
    var pbf: Data {
        let strings = [""] + World.keys + World.values + World.roles.dropFirst()
        func index(_ string: String) -> Int { strings.firstIndex(of: string) ?? 0 }
        func pairs(_ tags: [String: String]) -> [(key: UInt64, value: UInt64)] {
            tags.map { (key: UInt64(index($0.key)), value: UInt64(index($0.value))) }
        }
        var builder = PBFFileBuilder()
        builder.appendBlob(type: "OSMHeader", payload: PBFFileBuilder.headerPayload())
        let half = nodes.count / 2
        for slice in [Array(nodes[..<half]), Array(nodes[half...])] where !slice.isEmpty {
            builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
                strings: strings,
                dense: PBFFileBuilder.denseNodes(
                    ids: slice.map(\.id), latitudes: slice.map(\.latitude), longitudes: slice.map(\.longitude),
                    tags: slice.map { node in node.tags.map { (key: Int32(index($0.key)), value: Int32(index($0.value))) } }
                )
            ))
        }
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: strings, ways: ways.map { PBFFileBuilder.way(id: $0.id, nodeIDs: $0.nodeIDs, tags: pairs($0.tags)) }
        ))
        builder.appendBlob(type: "OSMData", payload: PBFFileBuilder.primitiveBlock(
            strings: strings,
            relations: relations.map { relation in
                PBFFileBuilder.relation(
                    id: relation.id,
                    members: relation.members.map { (id: $0.id, role: Int32(index($0.role)), type: UInt64($0.type.rawValue)) },
                    tags: pairs(relation.tags)
                )
            }
        ))
        return builder.file
    }

    struct Expected {
        var nodeIDs: [Int64]
        var wayIDs: [Int64]
        var relationIDs: [Int64]
        var complete: [Int64: Bool]
        var missingNodes: Int
    }

    /// The reference cut, written with plain sets and dictionaries.
    func expected() -> Expected {
        func coordinate(_ node: WorldNode) -> Coordinate {
            Coordinate(latitude: Double(node.latitude) / 1e7, longitude: Double(node.longitude) / 1e7)
        }
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let waysByID = Dictionary(uniqueKeysWithValues: ways.map { ($0.id, $0) })
        let inside = Set(nodes.filter { box.contains(coordinate($0)) }.map(\.id))
        var keptWays = Set(ways.filter { $0.nodeIDs.contains(where: inside.contains) }.map(\.id))
        let touching = relations.filter { relation in
            relation.members.contains { member in
                switch member.type {
                case .node: inside.contains(member.id)
                case .way: keptWays.contains(member.id)
                case .relation: false
                }
            }
        }
        // Completion: every member way that exists in the file is kept too.
        for relation in touching {
            for member in relation.members where member.type == .way && waysByID[member.id] != nil {
                keptWays.insert(member.id)
            }
        }
        var referenced = Set<Int64>()
        for id in keptWays { referenced.formUnion(waysByID[id]?.nodeIDs ?? []) }
        for relation in touching { for member in relation.members where member.type == .node { referenced.insert(member.id) } }

        let keptNodes = Set(nodes.filter { (inside.contains($0.id) && !$0.tags.isEmpty) || referenced.contains($0.id) }.map(\.id))
        var complete: [Int64: Bool] = [:]
        for relation in touching {
            complete[relation.id] = relation.members.allSatisfy { member in
                switch member.type {
                case .node: keptNodes.contains(member.id)
                case .way: keptWays.contains(member.id)
                case .relation: true
                }
            }
        }
        _ = nodesByID
        return Expected(
            nodeIDs: keptNodes.sorted(), wayIDs: keptWays.sorted(), relationIDs: touching.map(\.id).sorted(),
            complete: complete, missingNodes: referenced.filter { nodesByID[$0] == nil }.count
        )
    }
}

@Suite("Random worlds against a reference cut")
struct RandomWorldTests {
    @Test("The compact extract equals a plain dictionary-based reference on 60 random worlds", arguments: 0..<60)
    func matchesReference(seed: Int) throws {
        let world = World(seed: UInt64(seed))
        let expected = world.expected()
        let extract = try AreaCutter().cut(PBFReader(data: world.pbf), to: world.box)

        #expect(extract.nodes.ids == expected.nodeIDs, "seed \(seed): node IDs")
        #expect(extract.ways.ids == expected.wayIDs, "seed \(seed): way IDs")
        #expect(extract.relations.ids == expected.relationIDs, "seed \(seed): relation IDs")
        #expect(extract.missingNodeCount == expected.missingNodes, "seed \(seed): missing nodes")

        let nodesByID = Dictionary(uniqueKeysWithValues: world.nodes.map { ($0.id, $0) })
        for position in extract.nodes.indices {
            let source = try #require(nodesByID[extract.nodes.ids[position]])
            #expect(extract.nodes.coordinate(at: position)
                == Coordinate(latitude: Double(source.latitude) / 1e7, longitude: Double(source.longitude) / 1e7))
            #expect(extract.nodes.tags(at: position).dictionary == source.tags, "seed \(seed): node \(source.id) tags")
        }
        let waysByID = Dictionary(uniqueKeysWithValues: world.ways.map { ($0.id, $0) })
        for position in extract.ways.indices {
            let source = try #require(waysByID[extract.ways.ids[position]])
            #expect(Array(extract.ways.nodeIDs(at: position)) == source.nodeIDs, "seed \(seed): way \(source.id) nodes")
            #expect(extract.ways.tags(at: position).dictionary == source.tags, "seed \(seed): way \(source.id) tags")
            // Every way in the extract has all its nodes.
            for id in source.nodeIDs { #expect(extract.nodes.index(ofID: id) != nil, "seed \(seed): way \(source.id) node \(id)") }
        }
        let relationsByID = Dictionary(uniqueKeysWithValues: world.relations.map { ($0.id, $0) })
        for position in extract.relations.indices {
            let source = try #require(relationsByID[extract.relations.ids[position]])
            let element = extract.relations[position]
            #expect(element.relation.members == source.members.map { OSMMember(type: $0.type, id: $0.id, role: $0.role) },
                    "seed \(seed): relation \(source.id) members")
            #expect(element.relation.tags == source.tags, "seed \(seed): relation \(source.id) tags")
            #expect(element.isComplete == expected.complete[source.id], "seed \(seed): relation \(source.id) completeness")
        }
    }

    @Test("The random worlds really exercise the interesting cases")
    func worldsAreNotVacuous() throws {
        var withRelations = 0, withIncomplete = 0, withOutsideNodes = 0, withCompletedWays = 0, withMissing = 0
        for seed in 0..<60 {
            let world = World(seed: UInt64(seed))
            let extract = try AreaCutter().cut(PBFReader(data: world.pbf), to: world.box)
            if !extract.relations.isEmpty { withRelations += 1 }
            if extract.relations.indices.contains(where: { !extract.relations.isComplete(at: $0) }) { withIncomplete += 1 }
            if extract.nodes.indices.contains(where: { !world.box.contains(extract.nodes.coordinate(at: $0)) }) { withOutsideNodes += 1 }
            if extract.missingNodeCount > 0 { withMissing += 1 }
            // A way kept only through a relation has no node inside the box.
            let insideIDs = Set(extract.nodes.indices.filter { world.box.contains(extract.nodes.coordinate(at: $0)) }.map { extract.nodes.ids[$0] })
            if extract.ways.indices.contains(where: { !extract.ways.nodeIDs(at: $0).contains(where: insideIDs.contains) }) { withCompletedWays += 1 }
        }
        #expect(withRelations >= 20)
        #expect(withIncomplete >= 5)
        #expect(withOutsideNodes >= 20)
        #expect(withMissing >= 5)
        #expect(withCompletedWays >= 5)
    }
}
