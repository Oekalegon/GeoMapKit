import FeatureStore
import Foundation
import Testing

@testable import FeatureStoreBuilder

/// The names of national and state borders, taken from the relations the border ways belong to.
@Suite("Border names")
struct BorderNamesTests {
    private func names(of featureClass: FeatureClass, in world: inout SyntheticWorld) throws -> [String] {
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        let file = try FeatureStoreFile(data: result.data)
        var found: [String] = []
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: .overview) where feature.classID == featureClass.rawValue {
                found.append(feature.nameID.flatMap { file.string(at: $0) } ?? "")
            }
        }
        return Array(Set(found)).sorted()
    }

    private func border(_ world: inout SyntheticWorld, tags: [(String, String)] = []) {
        world.node(1, 0.5, 1.0); world.node(2, 1.5, 1.0); world.node(3, 2.5, 1.0)
        world.way(10, [1, 2, 3], tags)
    }

    @Test("A national border is named after the two countries, in alphabetical order, and not after the counties")
    func nationalBorder() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Sverige")])
        world.relation(51, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        world.relation(52, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "4"), ("name", "Østfold")])
        #expect(try names(of: .countryBorder, in: &world) == ["Norge – Sverige"])
    }

    @Test("A state border is named after the states, not after the country")
    func stateBorder() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "4")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "4"), ("name", "Østfold")])
        world.relation(51, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "4"), ("name", "Akershus")])
        world.relation(52, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        #expect(try names(of: .boundary, in: &world) == ["Akershus – Østfold"])
    }

    @Test("A border way with a name of its own keeps it")
    func ownName() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2"), ("name", "Riksgrensen")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        #expect(try names(of: .countryBorder, in: &world) == ["Riksgrensen"])
    }

    @Test("A border that is in no relation has no name")
    func noRelation() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2")])
        #expect(try names(of: .countryBorder, in: &world) == [""])
    }

    @Test("The same name from two relations is written once")
    func repeatedName() throws {
        var world = SyntheticWorld()
        border(&world, tags: [("boundary", "administrative"), ("admin_level", "2")])
        world.relation(50, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        world.relation(51, [(10, "outer", 1)], [("type", "boundary"), ("boundary", "administrative"), ("admin_level", "2"), ("name", "Norge")])
        #expect(try names(of: .countryBorder, in: &world) == ["Norge"])
    }
}
