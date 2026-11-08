import CoreGraphics
import FeatureStore
import Foundation
import GeoCore
import ImageIO
import MapStyle
import Testing

@testable import MapRender

@Suite("Divided roads")
struct DividedRoadsTests {
    private func line(
        _ id: Int64, _ xs: ClosedRange<Double>, y: Double, featureClass: FeatureClass = .roadMajor, structure: Structure = .ground,
        name: String? = nil
    ) -> SceneLine {
        SceneLine(
            featureClass: featureClass, objectID: id, points: [ScreenPoint(x: xs.lowerBound, y: y), ScreenPoint(x: xs.upperBound, y: y)],
            name: name, structure: structure)
    }

    private func strips(_ lines: [SceneLine], flows: [Int], width: Double = 6, metresPerPoint: Double = 1) -> [SceneMedian] {
        DividedRoads.medians(lines: lines, flows: flows, widths: lines.map { _ in width }, metresPerPoint: metresPerPoint)
    }

    private func area(_ ring: [ScreenPoint]) -> Double {
        var sum = 0.0
        for index in ring.indices {
            let a = ring[index], b = ring[(index + 1) % ring.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    @Test("Two one-way roads side by side, flowing opposite ways, get a strip between their centre lines")
    func pair() throws {
        // The edges are 4 m apart (centres 10 m, widths 6 m). Both lines run left to right; the second is one-way against it.
        let result = strips([line(1, 0...120, y: 0), line(2, 0...120, y: 10)], flows: [1, -1])
        let strip = try #require(result.first)
        #expect(result.count == 1 && strip.featureClass == .roadMajor && strip.structure == .ground)
        #expect(abs(area(strip.ring) - 120 * 10) < 120 * 10 * 0.03, "the strip fills the space from centre line to centre line")
        #expect(strip.ring.allSatisfy { $0.y == 0 || $0.y == 10 })
        #expect(strip.divider.count >= 2 && strip.divider.allSatisfy { abs($0.y - 5) < 1e-9 }, "the divider runs halfway between the carriageways")
        #expect(abs((strip.divider.map(\.x).max() ?? 0) - 120) < 1 && (strip.divider.map(\.x).min() ?? 99) < 1, "along the whole strip")
    }

    @Test("The result does not depend on the order of the lines")
    func order() {
        let forward = strips([line(1, 0...120, y: 0), line(2, 0...120, y: 10)], flows: [1, -1])
        let backward = strips([line(2, 0...120, y: 10), line(1, 0...120, y: 0)], flows: [-1, 1])
        #expect(forward.count == 1 && backward.count == 1)
        #expect(abs(area(forward[0].ring) - area(backward[0].ring)) < 1)
    }

    @Test("Roads that flow the same way, two-way roads and other classes are not a divided road")
    func notAPair() {
        let two = [line(1, 0...120, y: 0), line(2, 0...120, y: 10)]
        #expect(strips(two, flows: [1, 1]).isEmpty, "the same direction of travel")
        #expect(strips(two, flows: [1, 0]).isEmpty && strips(two, flows: [0, 0]).isEmpty, "two-way")
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 10, featureClass: .roadMinor)], flows: [1, -1]).isEmpty)
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 10, structure: .bridge)], flows: [1, -1]).isEmpty)
        #expect(strips([line(1, 0...120, y: 0, featureClass: .path), line(2, 0...120, y: 10, featureClass: .path)], flows: [1, -1]).isEmpty)
    }

    @Test("A divider wider than 4 m leaves the two roads apart, and the decision is for the whole stretch")
    func wideDivider() {
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 9.5)], flows: [1, -1]).count == 1, "3.5 m between the edges")
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 10.5)], flows: [1, -1]).isEmpty, "4.5 m between the edges")
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 12)], flows: [1, -1]).isEmpty, "6 m, which used to be in")
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 20)], flows: [1, -1]).isEmpty, "14 m between the edges")
        // The gap counts in metres: at a coarser scale the same distance in points is a wider divider.
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 9)], flows: [1, -1], width: 6, metresPerPoint: 2).isEmpty)
    }

    @Test("A stretch whose gap wanders around the limit is one thing, not strips and gaps in turn")
    func steadyOrNot() {
        // The second carriageway wiggles between 3.5 m and 4.5 m from the first: the middle value is 4 m, the stretch is kept
        // whole, with no gap in it.
        let wiggle = SceneLine(
            featureClass: .roadMajor, objectID: 2,
            points: stride(from: 0.0, through: 120, by: 10).enumerated().map { ScreenPoint(x: $1, y: $0 % 2 == 0 ? 9.5 : 10.5) })
        #expect(strips([line(1, 0...120, y: 0), wiggle], flows: [1, -1]).count == 1)
        // A stretch with a gap of 6 m over all of it: none, whatever the samples near 4 m say.
        let edge = SceneLine(
            featureClass: .roadMajor, objectID: 2,
            points: stride(from: 0.0, through: 120, by: 10).enumerated().map { ScreenPoint(x: $1, y: $0 % 2 == 0 ? 11.9 : 12.1) })
        #expect(strips([line(1, 0...120, y: 0), edge], flows: [1, -1]).isEmpty)
    }

    @Test("Roads with different names are two roads; one without a name may be half of a named road")
    func names() {
        #expect(strips([line(1, 0...120, y: 0, name: "Kaj Munks vei"), line(2, 0...120, y: 10, name: "Kaj Munks vei")], flows: [1, -1]).count == 1)
        #expect(strips([line(1, 0...120, y: 0, name: "Kaj Munks vei"), line(2, 0...120, y: 10, name: "Storoveien")], flows: [1, -1]).isEmpty)
        #expect(strips([line(1, 0...120, y: 0, name: "Kaj Munks vei"), line(2, 0...120, y: 10)], flows: [1, -1]).count == 1)
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 10)], flows: [1, -1]).count == 1)
    }

    @Test("Only the stretch where the carriageways run side by side gets a strip")
    func partialOverlap() throws {
        let result = strips([line(1, 0...120, y: 0), line(2, 40...80, y: 10)], flows: [1, -1])
        let strip = try #require(result.first)
        #expect(result.count == 1)
        #expect((strip.ring.map(\.x).min() ?? 0) >= 36 && (strip.ring.map(\.x).max() ?? 200) <= 84, "a few points beyond the ends at most")
        // The other way round: the short one is the first line.
        let swapped = strips([line(1, 40...80, y: 10), line(2, 0...120, y: 0)], flows: [-1, 1])
        #expect(swapped.count == 1 && (swapped[0].ring.map(\.x).min() ?? 0) >= 36 && (swapped[0].ring.map(\.x).max() ?? 200) <= 84)
    }

    @Test("A stretch shorter than 20 m is the end of a way at a junction, not a divided road")
    func shortStretch() {
        #expect(strips([line(1, 0...120, y: 0), line(2, 50...58, y: 10)], flows: [1, -1]).isEmpty)
        #expect(strips([line(1, 0...120, y: 0), line(2, 50...65, y: 10)], flows: [1, -1]).isEmpty, "15 m")
        #expect(strips([line(1, 0...120, y: 0), line(2, 50...75, y: 10)], flows: [1, -1]).count == 1, "25 m")
        // At a scale of 2 m per point, 6 points are 12 m and 15 points are 30 m (the edges are 2 m apart).
        #expect(strips([line(1, 0...120, y: 0), line(2, 50...56, y: 4)], flows: [1, -1], width: 3, metresPerPoint: 2).isEmpty)
        #expect(strips([line(1, 0...120, y: 0), line(2, 50...65, y: 4)], flows: [1, -1], width: 3, metresPerPoint: 2).count == 1)
    }

    @Test("Carriageways that touch or overlap are not separated, so they are not a divided road")
    func touching() {
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 6.5)], flows: [1, -1]).isEmpty, "0.5 m between the edges")
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 4)], flows: [1, -1]).isEmpty, "overlapping")
        #expect(strips([line(1, 0...120, y: 0), line(2, 0...120, y: 7.5)], flows: [1, -1]).count == 1, "1.5 m between the edges")
    }

    @Test("The end of a divided road, where the carriageways come together, is left as it is")
    func mergingEnd() throws {
        // 4 m apart over 90 points, then the second carriageway closes in on the first: the strip stops where the gap has
        // changed by more than 1.5 m, and the merge is left as two roads.
        let merging = SceneLine(
            featureClass: .roadMajor, objectID: 2, points: [ScreenPoint(x: 0, y: 10), ScreenPoint(x: 90, y: 10), ScreenPoint(x: 120, y: 6.4)])
        let strip = try #require(strips([line(1, 0...120, y: 0), merging], flows: [1, -1]).first)
        let end = strip.ring.map(\.x).max() ?? 0
        #expect(end > 90 && end < 108, "it ends in the merge, not at its end: \(end)")
    }

    @Test("Roads that cross, or meet at an angle, are not a divided road")
    func crossing() {
        let across = SceneLine(featureClass: .roadMajor, objectID: 2, points: [ScreenPoint(x: 60, y: -50), ScreenPoint(x: 60, y: 50)])
        #expect(strips([line(1, 0...120, y: 0), across], flows: [1, -1]).isEmpty)
        let slanted = SceneLine(featureClass: .roadMajor, objectID: 2, points: [ScreenPoint(x: 0, y: 6), ScreenPoint(x: 60, y: 60)])
        #expect(strips([line(1, 0...120, y: 0), slanted], flows: [1, -1]).isEmpty)
    }

    @Test("A road that forks has no strip: its gap is not steady")
    func fork() {
        // The second carriageway leaves the first at a small angle: 6 m apart at x = 0 and 20 m at x = 120.
        let diverging = SceneLine(featureClass: .roadMajor, objectID: 2, points: [ScreenPoint(x: 0, y: 6), ScreenPoint(x: 120, y: 20)])
        #expect(strips([line(1, 0...120, y: 0), diverging], flows: [1, -1]).isEmpty)
    }

    // MARK: In the scene and the picture

    private let latitude: Int32 = 471_000_000

    private func scene(
        oneway: [String?], directions: [Bool], tags: Bool = true, featureClass: FeatureClass = .roadMajor, subclass: UInt8 = 4,
        extra: [(String, String)] = [], extraFirst: Bool = false
    ) throws -> MapScene {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 47.1, longitude: 9.5), zoom: 13))
        let west = Int32((cell.northWest.longitude * 1e7).rounded())
        for (index, value) in oneway.enumerated() {
            // The carriageways are 7 m apart (centre to centre), one every 640 units of 1e-7 degrees in latitude.
            let dy = Int32(index) * 640
            var points = [
                PackedPoint(longitude: west + 4_000, latitude: latitude + dy), PackedPoint(longitude: west + 10_000, latitude: latitude + dy),
            ]
            if !directions[index] { points.reverse() }
            var stored: [StoredTag] = []
            if tags {
                var more: [StoredTag] = []
                for (key, text) in extra { more.append(StoredTag(key: writer.intern(key), value: writer.intern(text))) }
                if extraFirst { stored += more }
                if let value { stored.append(StoredTag(key: writer.intern("oneway"), value: writer.intern(value))) }
                if !extraFirst { stored += more }
            }
            try writer.add(
                StoredFeature(
                    classID: featureClass.rawValue, subclass: subclass, kind: .line, objectType: .way, objectID: Int64(index + 1),
                    tags: stored, parts: [GeometryPart(points: points)]),
                band: .detail, cell: cell)
        }
        let file = try FeatureStoreFile(data: try writer.data())
        let centre = Coordinate(latitude: Double(latitude) / 1e7, longitude: Double(west + 7_000) / 1e7)
        return try MapSceneBuilder(file: file, style: .standard).scene(for: MapViewport(center: centre, zoom: 18, width: 400, height: 300))
    }

    private func medianCount(_ scene: MapScene) -> Int {
        scene.steps.filter { $0.step.part == .body }.reduce(0) { $0 + $1.medians.count }
    }

    @Test("The scene has a strip for two one-way ways, in the body step of their class")
    func sceneHasAStrip() throws {
        let scene = try scene(oneway: ["yes", "yes"], directions: [true, false])
        #expect(medianCount(scene) >= 1)
        #expect(scene.steps.filter { $0.step.part == .casing }.allSatisfy { $0.medians.isEmpty }, "a strip has no outline of its own")
    }

    @Test("A one-way tag that says -1 turns the flow round")
    func reverseOneway() throws {
        // Both vertex lists run the same way; the second is one-way against them.
        #expect(medianCount(try scene(oneway: ["yes", "-1"], directions: [true, true])) >= 1)
        #expect(medianCount(try scene(oneway: ["yes", "yes"], directions: [true, true])) == 0)
    }

    @Test("A motorway is one-way without a tag, unless the tag says otherwise; other roads are not")
    func impliedOneway() throws {
        let motorway = [("highway", "motorway")]
        #expect(medianCount(try scene(oneway: [nil, nil], directions: [true, false], extra: motorway)) >= 1)
        #expect(medianCount(try scene(oneway: [nil, nil], directions: [true, false], extra: [("highway", "motorway_link")])) >= 1)
        #expect(medianCount(try scene(oneway: [nil, nil], directions: [true, false], extra: motorway, extraFirst: true)) >= 1)
        #expect(medianCount(try scene(oneway: ["no", "no"], directions: [true, false], extra: motorway)) == 0)
        #expect(medianCount(try scene(oneway: [nil, nil], directions: [true, false], extra: [("highway", "trunk")])) == 0)
        #expect(medianCount(try scene(oneway: [nil, nil], directions: [true, false], extra: motorway + [("junction", "roundabout")])) == 0)
        // One carriageway tagged -1 against the implied flow of the other.
        #expect(medianCount(try scene(oneway: [nil, "-1"], directions: [true, true], extra: motorway)) >= 1)
    }

    @Test("A roundabout has no strip, whatever the order of its tags")
    func roundabout() throws {
        // The `oneway` tag comes first in the helper's order, so the `junction` tag comes after it: it must still win.
        #expect(medianCount(try scene(oneway: ["yes", "yes"], directions: [true, false], extra: [("junction", "roundabout")])) == 0)
        #expect(medianCount(try scene(oneway: ["yes", "yes"], directions: [true, false], extra: [("junction", "roundabout")], extraFirst: true)) == 0)
        #expect(medianCount(try scene(oneway: ["yes", "yes"], directions: [true, false], extra: [("junction", "circular")])) >= 1)
    }

    @Test("Two carriageways of a minor road are a divided road too, and so are two on a bridge")
    func otherClassesAndStructures() throws {
        let minor = try scene(oneway: ["yes", "yes"], directions: [true, false], featureClass: .roadMinor)
        #expect(minor.steps.contains { $0.step.featureClass == .roadMinor && !$0.medians.isEmpty })
        let bridge = try scene(oneway: ["yes", "yes"], directions: [true, false], subclass: 4 | SubclassBits.bridge)
        let bridgeSteps = bridge.steps.filter { $0.step.featureClass == .roadMajor && $0.step.part == .body }
        #expect(bridgeSteps.contains { $0.step.structure == .bridge && !$0.medians.isEmpty })
        #expect(bridgeSteps.filter { $0.step.structure == .ground }.allSatisfy { $0.medians.isEmpty }, "not on the ground")
    }

    @Test("Two carriageways in a tunnel have no strip")
    func tunnel() throws {
        #expect(medianCount(try scene(oneway: ["yes", "yes"], directions: [true, false], subclass: 4 | SubclassBits.tunnel)) == 0)
    }

    @Test("Ways that are not one-way, and a store with no tags, have no strip")
    func noTags() throws {
        #expect(medianCount(try scene(oneway: ["no", "no"], directions: [true, false])) == 0)
        #expect(medianCount(try scene(oneway: [nil, nil], directions: [true, false])) == 0)
        #expect(medianCount(try scene(oneway: ["yes", "yes"], directions: [true, false], tags: false)) == 0, "the Watch copy has no tags")
    }

    @Test("The strip is drawn in the colour of the road, with a divider line of the outline's colour halfway")
    func stripIsDrawn() throws {
        let scene = try scene(oneway: ["yes", "yes"], directions: [true, false])
        let png = try CoreGraphicsRenderer().pngData(for: scene, style: .standard, scale: 1)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func color(x: Int, y: Int) -> [UInt8] {
            Array(buffer[((y * image.width + x) * 4)..<((y * image.width + x) * 4 + 3)])
        }
        func close(_ found: [UInt8], _ expected: MapColor) -> Bool {
            let wanted = [expected.red, expected.green, expected.blue].map { UInt8(($0 * 255).rounded()) }
            return zip(found, wanted).allSatisfy { abs(Int($0) - Int($1)) <= 4 }
        }
        let style = try #require(MapStyle.standard.style(for: .roadMajor)?.stroke)
        let road = style.color.value(atZoom: 18), divider = try #require(style.casing).color.value(atZoom: 18)
        // The carriageways are 7 m apart; the view is centred on the first one, the second is above it. Halfway is half of 7 m up.
        let halfGap = 7.0 / 2 / scene.viewport.metresPerPoint
        let x = image.width / 2, middle = image.height / 2 - Int(halfGap.rounded())
        #expect(close(color(x: x, y: middle), divider), "the divider: \(color(x: x, y: middle))")
        // A little off the middle, still between the carriageways, the strip has the colour of the road.
        #expect(close(color(x: x, y: middle + 2), road), "the strip: \(color(x: x, y: middle + 2))")
    }
}
