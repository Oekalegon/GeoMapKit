import FeatureStore
import Foundation
import GeoCore
import OSMPBF
import Testing

@testable import FeatureStoreBuilder

/// The marker and the name of a shop, a church or a hut that is mapped as an outline sit at a point inside it.
@Suite("Area points")
struct AreaPointTests {
    private func features(of featureClass: FeatureClass, in world: inout SyntheticWorld) throws -> [StoredFeature] {
        let file = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: try world.extract()).data)
        var found: [StoredFeature] = []
        for cell in try file.cells() {
            found += try file.features(in: cell, band: .detail).filter { $0.classID == featureClass.rawValue }
        }
        return found
    }

    private func square(_ world: inout SyntheticWorld, tags: [(String, String)]) {
        world.way(100, world.rectangle(first: 10, 0.5, 0.5, 1.5, 1.5), tags)
    }

    @Test("A building that is a shop has a poi point with its name, and is still a building")
    func namedShop() throws {
        var world = SyntheticWorld()
        square(&world, tags: [("building", "retail"), ("shop", "supermarket"), ("name", "Delhaize")])
        let points = try features(of: .poi, in: &world).filter { $0.kind == .point }
        #expect(points.count == 1 && points[0].objectID == 100)
        #expect(try features(of: .building, in: &world).count > 0, "the outline stays")
        let result = try FeatureStoreBuilder().build(from: try world.extract())
        #expect(result.report.areaPoints == 1)
    }

    @Test("The point is inside the outline")
    func inside() throws {
        var world = SyntheticWorld()
        square(&world, tags: [("building", "church"), ("amenity", "place_of_worship"), ("name", "Sint-Pieter")])
        let point = try #require(try features(of: .poi, in: &world).first { $0.kind == .point }?.parts.first?.points.first)
        // The outline is a rectangle: its bounding box is the box of the points of the pieces that it was cut into.
        let outline = try features(of: .building, in: &world).flatMap(\.parts).flatMap(\.points)
        let minLon = try #require(outline.map(\.longitude).min()), maxLon = try #require(outline.map(\.longitude).max())
        let minLat = try #require(outline.map(\.latitude).min()), maxLat = try #require(outline.map(\.latitude).max())
        #expect(point.longitude > minLon && point.longitude < maxLon && point.latitude > minLat && point.latitude < maxLat)
        // And in the middle, not at an edge.
        #expect(abs(Double(point.longitude) - Double(minLon + maxLon) / 2) < Double(maxLon - minLon) * 0.1)
        #expect(abs(Double(point.latitude) - Double(minLat + maxLat) / 2) < Double(maxLat - minLat) * 0.1)
    }

    @Test("A shop with no name gets no point, a hut or a shelter gets one with no name")
    func unnamed() throws {
        var shop = SyntheticWorld()
        square(&shop, tags: [("building", "retail"), ("shop", "supermarket")])
        #expect(try features(of: .poi, in: &shop).filter { $0.kind == .point }.isEmpty, "a dot with nothing to say")
        var shelter = SyntheticWorld()
        square(&shelter, tags: [("building", "yes"), ("amenity", "shelter")])
        let points = try features(of: .poiAnchor, in: &shelter).filter { $0.kind == .point }
        #expect(points.count == 1, "the outline itself is of the class too, as an area; the marker is the point")
    }

    @Test("An outline that is a poi itself (a hospital with no building tag) gets its point too")
    func poiOutline() throws {
        var world = SyntheticWorld()
        square(&world, tags: [("amenity", "hospital"), ("name", "AZ Sint-Jan")])
        #expect(try features(of: .poi, in: &world).contains { $0.kind == .point })
    }

    @Test("A lake that is a marina gets no point: its name is written in the water")
    func water() throws {
        var world = SyntheticWorld()
        square(&world, tags: [("natural", "water"), ("leisure", "marina"), ("name", "Kempisch dok")])
        #expect(try features(of: .poi, in: &world).filter { $0.kind == .point }.isEmpty)
    }

    @Test("A closed line, and a way that is no area, get no point")
    func notAnArea() throws {
        var world = SyntheticWorld()
        world.node(1, 0.5, 0.5); world.node(2, 1.5, 0.5)
        world.way(100, [1, 2], [("amenity", "bench"), ("name", "X")])
        #expect(try features(of: .poi, in: &world).filter { $0.kind == .point }.isEmpty)
    }

    @Test("A multipolygon that is a shop gets a point")
    func multipolygon() throws {
        var world = SyntheticWorld()
        world.way(100, world.rectangle(first: 10, 0.5, 0.5, 1.5, 1.5), [])
        world.relation(200, [(100, "outer", 1)], [("type", "multipolygon"), ("building", "retail"), ("shop", "mall"), ("name", "Mall")])
        let points = try features(of: .poi, in: &world).filter { $0.kind == .point }
        #expect(points.count == 1 && points[0].objectID == 200)
    }

    @Test("The point class is the first point class of the rule table, whatever class comes before it")
    func pointClass() {
        let classifier = FeatureClassifier()
        let shop = ClassifierTagArray([OSMTag(key: "building", value: "retail"), OSMTag(key: "shop", value: "supermarket")])
        #expect(classifier.pointClass(shop)?.featureClass == .poi && classifier.pointClass(shop)?.kind == .point)
        let hut = ClassifierTagArray([OSMTag(key: "building", value: "yes"), OSMTag(key: "amenity", value: "shelter")])
        #expect(classifier.pointClass(hut)?.featureClass == .poiAnchor)
        #expect(classifier.pointClass(ClassifierTagArray([OSMTag(key: "building", value: "yes")])) == nil)
    }
}
