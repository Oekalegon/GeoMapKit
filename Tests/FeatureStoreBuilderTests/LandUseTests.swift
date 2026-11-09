import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// `landUse` (rule table 19): the land use that no class takes is stored, with the value of its tag in every band it is in.
@Suite("Land use")
struct LandUseTests {
    private func features(of id: Int64, in file: FeatureStoreFile, band: ZoomBand) throws -> [(StoredFeature, [String])] {
        var result: [(StoredFeature, [String])] = []
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: band) where feature.objectID == id && feature.classID == FeatureClass.landUse.rawValue {
                result.append((feature, feature.tags.map { "\(file.string(at: $0.key) ?? "?")=\(file.string(at: $0.value) ?? "?")" }))
            }
        }
        return result
    }

    @Test("A landfill is stored from the mid band with landuse=landfill in the mid and the detail band, and not in the overview band")
    func valueInEveryBand() throws {
        var world = SyntheticWorld()
        world.way(800, world.rectangle(first: 800, 0.3, 0.3, 1.7, 1.7), [("landuse", "landfill"), ("name", "De Berg"), ("operator", "Gemeente")])
        let file = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: try world.extract()).data)
        #expect(try features(of: 800, in: file, band: .overview).isEmpty, "a landUse feature starts at the mid band")
        let mid = try features(of: 800, in: file, band: .mid)
        let detail = try features(of: 800, in: file, band: .detail)
        #expect(!mid.isEmpty && !detail.isEmpty)
        #expect(mid.allSatisfy { $0.1 == ["landuse=landfill"] }, "only the value in the mid band")
        #expect(detail.allSatisfy { $0.1.contains("landuse=landfill") && $0.1.contains("operator=Gemeente") }, "all the tags in the detail band")
        #expect(mid.allSatisfy { $0.0.nameID != nil }, "the name is kept")
    }

    @Test("A dune is landUse with natural=dune, and the Watch copy has neither")
    func duneAndWatch() throws {
        var world = SyntheticWorld()
        world.way(810, world.rectangle(first: 810, 0.3, 0.3, 1.7, 1.7), [("natural", "dune")])
        let extract = try world.extract()
        let full = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: extract).data)
        #expect(try features(of: 810, in: full, band: .mid).allSatisfy { $0.1 == ["natural=dune"] })
        let watch = try FeatureStoreFile(data: try FeatureStoreBuilder(profile: .watch).build(from: extract).data)
        #expect(try watch.cells().flatMap { try watch.features(in: $0, band: .mid) }.allSatisfy { $0.objectID != 810 })
    }
}
