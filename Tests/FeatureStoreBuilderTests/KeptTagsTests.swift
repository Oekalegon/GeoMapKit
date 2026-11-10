import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// The surface and difficulty of a path and the gauge of a railway are kept in every band (question 55), the other tags in the detail band only.
@Suite("Kept tags")
struct KeptTagsTests {
    private func tags(of id: Int64, class featureClass: FeatureClass, in file: FeatureStoreFile, band: ZoomBand) throws -> [[String]] {
        var result: [[String]] = []
        for cell in try file.cells() {
            for feature in try file.features(in: cell, band: band) where feature.objectID == id && feature.classID == featureClass.rawValue {
                result.append(feature.tags.map { "\(file.string(at: $0.key) ?? "?")=\(file.string(at: $0.value) ?? "?")" }.sorted())
            }
        }
        return result
    }

    @Test("A path keeps surface and sac_scale in the mid band and all its tags in the detail band")
    func pathValuesInTheMidBand() throws {
        var world = SyntheticWorld()
        world.node(900, 0.5, 0.5)
        world.node(901, 0.5, 1.5)
        world.way(900, [900, 901],
                  [("highway", "path"), ("surface", "gravel"), ("sac_scale", "hiking"), ("name", "Stien"), ("foot", "yes")])
        let file = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: try world.extract()).data)
        let mid = try tags(of: 900, class: .path, in: file, band: .mid)
        let detail = try tags(of: 900, class: .path, in: file, band: .detail)
        #expect(!mid.isEmpty && mid.allSatisfy { $0 == ["sac_scale=hiking", "surface=gravel"] }, "the values, and not the name or the foot tag")
        #expect(detail.allSatisfy { $0.contains("foot=yes") && $0.contains("surface=gravel") })
    }

    @Test("A railway keeps its gauge in the overview band, and a path without such tags keeps none")
    func railwayGaugeAndNoTags() throws {
        var world = SyntheticWorld()
        world.node(910, 0.5, 0.5)
        world.node(911, 0.5, 1.5)
        world.way(910, [910, 911], [("railway", "rail"), ("gauge", "1000"), ("name", "Bane")])
        world.node(920, 0.7, 0.5)
        world.node(921, 0.7, 1.5)
        world.way(920, [920, 921], [("highway", "path")])
        let file = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: try world.extract()).data)
        let rail = try tags(of: 910, class: .railway, in: file, band: .overview)
        #expect(!rail.isEmpty && rail.allSatisfy { $0 == ["gauge=1000"] })
        #expect(try tags(of: 920, class: .path, in: file, band: .mid).allSatisfy { $0.isEmpty })
    }
}
