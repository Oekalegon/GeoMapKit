import CoreGraphics
import Foundation
import ImageIO
import FeatureStore
import GeoCore
import MapStyle
import Testing

@testable import MapRender

@Suite("Core Graphics renderer")
struct CoreGraphicsRendererTests {
    private let viewport = MapViewport(center: Coordinate(latitude: 47.1, longitude: 9.5), zoom: 16, width: 100, height: 80)

    /// A scene that draws one horizontal line through the middle of the view and one filled square.
    private func scene() -> MapScene {
        let line = SceneLine(
            featureClass: .path, objectID: 1, points: [ScreenPoint(x: 0, y: 40), ScreenPoint(x: 100, y: 40)])
        let square = [ScreenPoint(x: 10, y: 10), ScreenPoint(x: 30, y: 10), ScreenPoint(x: 30, y: 30), ScreenPoint(x: 10, y: 30), ScreenPoint(x: 10, y: 10)]
        let area = SceneArea(featureClass: .waterArea, objectID: 2, rings: [square], outline: [])
        return MapScene(
            viewport: viewport, band: .detail,
            steps: [
                SceneStep(step: DrawStep(featureClass: .waterArea, part: .body), areas: [area]),
                SceneStep(step: DrawStep(featureClass: .path, part: .body), lines: [line]),
            ], cellCount: 1)
    }

    private func pixels(of png: Data) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (image.width, image.height, buffer)
    }

    private func pixel(_ image: (width: Int, height: Int, rgba: [UInt8]), x: Int, y: Int) -> [UInt8] {
        let i = (y * image.width + x) * 4
        return Array(image.rgba[i..<i + 4])
    }

    private func close(_ pixel: [UInt8], to color: MapColor) -> Bool {
        let expected = [color.red, color.green, color.blue].map { UInt8(($0 * 255).rounded()) }
        return zip(pixel.prefix(3), expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
    }

    @Test func pngHasTheRightSizeAndSignature() throws {
        let png = try CoreGraphicsRenderer().pngData(for: scene(), style: .standard, scale: 2)
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = try pixels(of: png)
        #expect(image.width == 200 && image.height == 160)
    }

    @Test func backgroundFillAndLineAreDrawnWhereTheSceneSays() throws {
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene(), style: .standard, scale: 2))
        // Background in a free corner (screen 90, 70 → pixel 180, 140).
        #expect(close(pixel(image, x: 180, y: 140), to: MapStyle.standard.background))
        // The water square (screen 20, 20 → pixel 40, 40), y down.
        let water = try #require(MapStyle.standard.style(for: .waterArea)?.fill?.color.value(atZoom: 16))
        #expect(close(pixel(image, x: 40, y: 40), to: water))
        // The path line at screen y 40 → pixel y 80.
        let path = try #require(MapStyle.standard.style(for: .path)?.stroke?.color.value(atZoom: 16))
        #expect(close(pixel(image, x: 150, y: 80), to: path))
    }

    @Test func aTranslucentCasingIsBlendedOnceWhereLinesOverlap() throws {
        let tall = MapViewport(center: Coordinate(latitude: 47.1, longitude: 9.5), zoom: 16, width: 100, height: 200)
        func line(_ id: Int64, y: Double) -> SceneLine {
            SceneLine(featureClass: .countryBorder, objectID: id, points: [ScreenPoint(x: 0, y: y), ScreenPoint(x: 100, y: y)])
        }
        // Two identical border lines at y 40 and one at y 140.
        let scene = MapScene(
            viewport: tall, band: .overview,
            steps: [
                SceneStep(step: DrawStep(featureClass: .countryBorder, part: .casing), lines: [line(1, y: 40), line(2, y: 40), line(3, y: 140)]),
                SceneStep(step: DrawStep(featureClass: .countryBorder, part: .body), lines: [line(1, y: 40), line(2, y: 40), line(3, y: 140)]),
            ], cellCount: 1)
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene, style: .standard, scale: 1))
        // Four points off the line, inside the band (6.75 points at zoom 16): the doubled line must look like the single one.
        let doubled = pixel(image, x: 50, y: 36), single = pixel(image, x: 50, y: 136)
        #expect(doubled == single)
        #expect(!close(single, to: MapStyle.standard.background), "the band is visible")
    }

    @Test func aBridgeCasingIsDrawnAroundTheDeckAndTheDeckOnTopOfIt() throws {
        let view = MapViewport(center: Coordinate(latitude: 47.1, longitude: 9.5), zoom: 16, width: 100, height: 100)
        let road = try #require(MapStyle.standard.style(for: .roadMinor))
        let bridge = try #require(road.stroke(for: .bridge))
        let casing = try #require(bridge.casing)
        let half = bridge.width.resolved(atZoom: 16, metresPerPoint: view.metresPerPoint, lanes: nil) / 2
        let extra = casing.extraPoints.value(atZoom: 16)
        let line = SceneLine(
            featureClass: .roadMinor, objectID: 1, points: [ScreenPoint(x: 0, y: 50), ScreenPoint(x: 100, y: 50)], structure: .bridge)
        let scene = MapScene(
            viewport: view, band: .detail,
            steps: [
                SceneStep(step: DrawStep(featureClass: .roadMinor, part: .casing, structure: .bridge), lines: [line]),
                SceneStep(step: DrawStep(featureClass: .roadMinor, part: .body, structure: .bridge), lines: [line]),
            ], cellCount: 1)
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene, style: .standard, scale: 1))
        let deck = bridge.color.value(atZoom: 16)
        #expect(close(pixel(image, x: 50, y: 50), to: deck), "the deck is on top")
        let inBand = Int((50 + half + extra / 2).rounded(.down))
        #expect(close(pixel(image, x: 50, y: inBand), to: casing.color.value(atZoom: 16)), "the casing shows beside the deck")
        #expect(close(pixel(image, x: 50, y: Int((50 + half + extra + 3).rounded(.up))), to: MapStyle.standard.background))
    }

    @Test func sceneIsNotFlippedVertically() throws {
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene(), style: .standard, scale: 1))
        let water = try #require(MapStyle.standard.style(for: .waterArea)?.fill?.color.value(atZoom: 16))
        #expect(close(pixel(image, x: 20, y: 20), to: water))
        #expect(!close(pixel(image, x: 20, y: 60), to: water))
    }

    @Test func invalidSizeOrScaleThrows() {
        let renderer = CoreGraphicsRenderer()
        let empty = MapScene(
            viewport: MapViewport(center: viewport.center, zoom: 10, width: 0, height: 50), band: .detail, steps: [], cellCount: 0)
        #expect(throws: MapRenderError.imageCreationFailed) { try renderer.pngData(for: empty, style: .standard) }
        #expect(throws: MapRenderError.imageCreationFailed) { try renderer.pngData(for: scene(), style: .standard, scale: 0) }
        #expect(throws: MapRenderError.imageCreationFailed) { try renderer.pngData(for: scene(), style: .standard, scale: 9) }
        #expect(throws: MapRenderError.imageCreationFailed) { try renderer.pngData(for: scene(), style: .standard, scale: .nan) }
    }

    @Test func emptySceneDrawsOnlyTheBackground() throws {
        let empty = MapScene(viewport: viewport, band: .detail, steps: [], cellCount: 0)
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: empty, style: .watch, scale: 1))
        #expect(close(pixel(image, x: 50, y: 40), to: MapStyle.watch.background))
    }

    @Test func labelMeasurementGrowsWithTextAndSize() {
        let short = CoreGraphicsRenderer.measure("Vaduz", 12)
        let long = CoreGraphicsRenderer.measure("Vaduz Rotes Haus", 12)
        let big = CoreGraphicsRenderer.measure("Vaduz", 24)
        #expect(long.width > short.width && big.width > short.width && big.height > short.height)
    }

    @Test func labelsAreDrawnUprightAtTheirPlace() throws {
        // A point with a name: the text pixels must appear to the right of the dot and not mirrored below it.
        let point = ScenePoint(featureClass: .place, objectID: 7, position: ScreenPoint(x: 50, y: 40), name: "Vaduz")
        let scene = MapScene(
            viewport: viewport, band: .detail,
            steps: [SceneStep(step: DrawStep(featureClass: .place, part: .body), points: [point])], cellCount: 1)
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene, style: .standard, scale: 2))
        let background = MapStyle.standard.background
        var inkRows = Set<Int>()
        for y in 0..<image.height {
            for x in 0..<image.width where !close(pixel(image, x: x, y: y), to: background) { inkRows.insert(y) }
        }
        // The label is centred on the anchor row (pixel row 80), so ink lies around it and none far below.
        #expect(!inkRows.isEmpty)
        #expect(inkRows.allSatisfy { abs($0 - 80) < 24 })
    }

    @Test func attributionIsDrawnInTheBottomRightCorner() throws {
        let wide = MapViewport(center: viewport.center, zoom: 16, width: 400, height: 80)
        let scene = MapScene(viewport: wide, band: .detail, steps: [], cellCount: 0, attribution: "© OpenStreetMap contributors, ODbL")
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene, style: .standard, scale: 2))
        let background = MapStyle.standard.background
        var minRow = image.height
        var maxColumn = 0
        var minColumn = image.width
        for y in 0..<image.height {
            for x in 0..<image.width where !close(pixel(image, x: x, y: y), to: background) {
                minRow = min(minRow, y)
                minColumn = min(minColumn, x)
                maxColumn = max(maxColumn, x)
            }
        }
        #expect(minRow >= image.height - 30, "ink only in the bottom rows")
        #expect(maxColumn > image.width - 12 && minColumn > image.width / 2)
    }

    /// Counts the pixels that differ from the background in the bottom-right corner of a 400x80 pt scene.
    private func creditInk(style: MapStyle) throws -> Int {
        let wide = MapViewport(center: viewport.center, zoom: 16, width: 400, height: 80)
        let scene = MapScene(viewport: wide, band: .detail, steps: [], cellCount: 0, attribution: "© OpenStreetMap contributors, ODbL")
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene, style: style, scale: 2))
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width where !close(pixel(image, x: x, y: y), to: style.background) { count += 1 }
        }
        return count
    }

    @Test func hiddenAttributionDrawsNothingAndCompactDrawsLessThanFull() throws {
        var style = MapStyle.standard
        style.attribution = .full
        let full = try creditInk(style: style)
        style.attribution = .compact
        let compact = try creditInk(style: style)
        style.attribution = .hidden
        let hidden = try creditInk(style: style)
        #expect(hidden == 0)
        #expect(compact > 0 && compact < full)
    }

    @Test func noAttributionMeansNoInk() throws {
        let scene = MapScene(viewport: viewport, band: .detail, steps: [], cellCount: 0)
        let image = try pixels(of: CoreGraphicsRenderer().pngData(for: scene, style: .standard, scale: 2))
        #expect(close(pixel(image, x: image.width - 10, y: image.height - 10), to: MapStyle.standard.background))
    }
}
