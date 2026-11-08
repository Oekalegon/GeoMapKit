import CoreGraphics
import FeatureStore
import Foundation
import ImageIO
import GeoCore
import MapStyle
import Testing

@testable import MapRender

/// Names written along lines.
@Suite("Labels along lines")
struct LineLabelTests {
    private let style = LabelStyle(size: ZoomValue(constant: 10), color: .black, priority: 5)

    /// Every character is 6 points wide and 10 high.
    private let measure: (String, Double) -> (width: Double, height: Double) = { text, _ in (6 * Double(text.count), 10) }

    private func line(_ points: [(Double, Double)]) -> LineLabelCandidate { line(1, "Main street", points) }

    private func line(_ id: Int64, _ points: [(Double, Double)]) -> LineLabelCandidate { line(id, "Main street", points) }

    private func line(_ text: String, _ points: [(Double, Double)]) -> LineLabelCandidate { line(1, text, points) }

    private func line(_ id: Int64, _ text: String, _ points: [(Double, Double)], priority: Int = 5) -> LineLabelCandidate {
        LineLabelCandidate(
            objectID: id, text: text, points: points.map { ScreenPoint(x: $0.0, y: $0.1) }, fontSize: 10,
            style: LabelStyle(size: ZoomValue(constant: 10), color: .black, priority: priority))
    }

    /// A line whose name goes beside it, as that of a border does.
    private func border(_ text: String, _ points: [(Double, Double)]) -> LineLabelCandidate {
        LineLabelCandidate(
            objectID: 1, text: text, points: points.map { ScreenPoint(x: $0.0, y: $0.1) }, fontSize: 10,
            style: LabelStyle(size: ZoomValue(constant: 10), color: .black, haloWidth: 0, placement: .besideLine))
    }

    /// The distance from the line to the middle of the text beside it: half the font size and 1 point.
    private let lift = 6.0

    private func place(
        _ lines: [LineLabelCandidate], points: [LabelCandidate] = [], maximumCount: Int? = nil, width: Double = 400
    ) -> [PlacedLabel] {
        LabelPlacer.place(
            points, lines: lines, viewWidth: width, viewHeight: 300, maximumCount: maximumCount, measure: measure)
    }

    // MARK: Beside the line

    @Test("The names of a border go on its two sides: on a line to the east the left name above it, the right one below")
    func bothSides() throws {
        let labels = place([border("North\nSouth", [(20, 100), (380, 100)])])
        let north = try #require(labels.first { $0.text == "North" }), south = try #require(labels.first { $0.text == "South" })
        #expect(north.glyphs.allSatisfy { abs($0.position.y - (100 - lift)) < 1e-9 && abs($0.angle) < 1e-9 }, "above the line")
        #expect(south.glyphs.allSatisfy { abs($0.position.y - (100 + lift)) < 1e-9 && abs($0.angle) < 1e-9 }, "below the line")
        #expect(labels.count == 2)
        for label in labels {
            let first = try #require(label.glyphs.first), last = try #require(label.glyphs.last)
            #expect(abs((first.position.x + last.position.x) / 2 - 200) < 1e-9, "both centred on the same place")
        }
    }

    @Test("On a line to the west the left name is below it, so each name stays on the side of its region")
    func reversedLine() throws {
        let labels = place([border("North\nSouth", [(380, 100), (20, 100)])])
        let north = try #require(labels.first { $0.text == "North" }), south = try #require(labels.first { $0.text == "South" })
        #expect(north.glyphs.allSatisfy { abs($0.position.y - (100 + lift)) < 1e-9 })
        #expect(south.glyphs.allSatisfy { abs($0.position.y - (100 - lift)) < 1e-9 })
        #expect(north.glyphs.map(\.position.x) == north.glyphs.map(\.position.x).sorted(), "still read from left to right")
    }

    @Test("On a vertical line the text reads upwards and the sides are west and east")
    func verticalSides() throws {
        // To the north the left of the line is the west.
        var labels = place([border("West\nEast", [(200, 290), (200, 10)])])
        var west = try #require(labels.first { $0.text == "West" }), east = try #require(labels.first { $0.text == "East" })
        #expect(west.glyphs.allSatisfy { abs($0.position.x - (200 - lift)) < 1e-9 && abs($0.angle + .pi / 2) < 1e-9 })
        #expect(east.glyphs.allSatisfy { abs($0.position.x - (200 + lift)) < 1e-9 })
        // To the south the left of the line is the east.
        labels = place([border("West\nEast", [(200, 10), (200, 290)])])
        west = try #require(labels.first { $0.text == "West" })
        east = try #require(labels.first { $0.text == "East" })
        #expect(west.glyphs.allSatisfy { abs($0.position.x - (200 + lift)) < 1e-9 })
        #expect(east.glyphs.allSatisfy { abs($0.position.x - (200 - lift)) < 1e-9 })
    }

    @Test("A slanted line has the names on either side, turned with it")
    func slantedSides() throws {
        // Rising to the north-east: the left of the line is the north-west.
        let labels = place([border("Up\nDown", [(20, 250), (300, 50)])])
        let up = try #require(labels.first { $0.text == "Up" }), down = try #require(labels.first { $0.text == "Down" })
        let angle = Foundation.atan2(-200.0, 280.0)
        for label in labels { #expect(label.glyphs.allSatisfy { abs($0.angle - angle) < 1e-9 }) }
        // The middle of the line is at (160, 150); the names sit a lift away from it, on its two sides.
        func middle(_ label: PlacedLabel) -> ScreenPoint {
            ScreenPoint(
                x: label.glyphs.map(\.position.x).reduce(0, +) / Double(label.glyphs.count),
                y: label.glyphs.map(\.position.y).reduce(0, +) / Double(label.glyphs.count))
        }
        let a = middle(up), b = middle(down)
        #expect(abs(hypot(a.x - 160, a.y - 150) - lift) < 1e-6 && abs(hypot(b.x - 160, b.y - 150) - lift) < 1e-6)
        #expect(a.x < b.x && a.y < b.y, "up is the north-west side")
    }

    @Test("A name with no sides is written above the line, not on it")
    func unsided() throws {
        let label = try #require(place([border("Norge – Sverige", [(20, 100), (380, 100)])]).first)
        #expect(label.text == "Norge – Sverige")
        #expect(label.glyphs.allSatisfy { abs($0.position.y - (100 - lift)) < 1e-9 })
    }

    @Test("A border with a region on one side only has one name")
    func oneSidedName() throws {
        let labels = place([border("Norge\n", [(20, 100), (380, 100)])])
        #expect(labels.map(\.text) == ["Norge"])
        #expect(labels.first?.glyphs.allSatisfy { abs($0.position.y - (100 - lift)) < 1e-9 } == true)
    }

    @Test("The names of both sides are placed together or not at all")
    func together() {
        // 'North' and 'South' need 30 points each; the line is 25 long.
        #expect(place([border("North\nSouth", [(100, 100), (125, 100)])]).isEmpty)
        // Two names, so the count limit of one leaves none.
        #expect(place([border("North\nSouth", [(20, 100), (380, 100)])], maximumCount: 1).isEmpty)
    }

    @Test("A border does not run over a point label")
    func beside() {
        // A symbol with a label just above the middle of the line.
        let symbol = LabelCandidate(
            objectID: 9, text: "Hut", anchor: ScreenPoint(x: 200, y: 92), symbolRadius: 30, fontSize: 10,
            style: LabelStyle(size: ZoomValue(constant: 10), color: .black, priority: 50))
        let labels = place([border("North\nSouth", [(20, 100), (380, 100)])], points: [symbol])
        for label in labels where label.text == "North" || label.text == "South" {
            for glyph in label.glyphs { #expect(hypot(glyph.position.x - 200, glyph.position.y - 92) > 30) }
        }
    }

    // MARK: Placement

    @Test("A name runs along a straight line, centred on it, one glyph per character")
    func straightLine() throws {
        let label = try #require(place([line([(20, 100), (380, 100)])]).first)
        #expect(label.glyphs.count == "Main street".count)
        #expect(label.glyphs.map(\.text).joined() == "Main street")
        for glyph in label.glyphs {
            #expect(abs(glyph.position.y - 100) < 1e-9 && abs(glyph.angle) < 1e-9)
        }
        // Centred on the middle of the line, and the letters follow each other without gaps.
        let first = try #require(label.glyphs.first), last = try #require(label.glyphs.last)
        #expect(abs((first.position.x + last.position.x) / 2 - 200) < 1e-9)
        #expect(abs(first.position.x - 170) < 1e-9, "the first of 11 letters, 6 points each (66 in all), centred on 200")
    }

    @Test("Text is never upside down: a line drawn right to left is read from its other end")
    func readsLeftToRight() throws {
        let label = try #require(place([line([(380, 100), (20, 100)])]).first)
        #expect(label.glyphs.map(\.text).joined() == "Main street")
        let xs = label.glyphs.map(\.position.x)
        #expect(xs == xs.sorted(), "the letters go from left to right")
        #expect(label.glyphs.allSatisfy { abs($0.angle) < 1e-9 })
    }

    @Test("A slanted line gives slanted text, within a quarter turn of horizontal")
    func slanted() throws {
        let rising = try #require(place([line([(20, 250), (300, 50)])]).first)
        let expected = Foundation.atan2(-200.0, 280.0)
        #expect(rising.glyphs.allSatisfy { abs($0.angle - expected) < 1e-9 })
        let falling = try #require(place([line([(300, 50), (20, 250)])]).first)
        #expect(falling.glyphs.allSatisfy { abs($0.angle - expected) < 1e-9 }, "the direction of the line does not matter")
        for label in [rising, falling] { #expect(label.glyphs.allSatisfy { abs($0.angle) <= .pi / 2 }) }
    }

    @Test("On a vertical line the text reads upwards")
    func vertical() throws {
        for points in [[(200.0, 10.0), (200.0, 290.0)], [(200.0, 290.0), (200.0, 10.0)]] {
            let label = try #require(place([line(points)]).first)
            #expect(label.glyphs.allSatisfy { abs($0.angle + .pi / 2) < 1e-9 })
            let ys = label.glyphs.map(\.position.y)
            #expect(ys == ys.sorted(by: >), "the first letter is at the bottom")
        }
    }

    @Test("A line shorter than the name gets none")
    func tooShort() {
        #expect(place([line([(100, 100), (140, 100)])]).isEmpty)
    }

    @Test("A name that would turn a corner goes to a straight stretch of the line instead, or is dropped")
    func corner() throws {
        // A right angle in the middle of a line that is straight for 150 points on either side of it.
        let bent = line([(50, 100), (200, 100), (200, 250)])
        let label = try #require(place([bent]).first)
        let xs = label.glyphs.map(\.position.x), ys = label.glyphs.map(\.position.y)
        #expect(label.glyphs.allSatisfy { abs($0.angle) < 1e-9 } || label.glyphs.allSatisfy { abs($0.angle + .pi / 2) < 1e-9 })
        #expect(Set(ys).count == 1 || Set(xs).count == 1, "all letters on one of the two straight stretches")
        // A wiggle that has no straight stretch long enough has no label.
        let zigzag = line([(20, 100), (50, 130), (80, 100), (110, 130), (140, 100), (170, 130)])
        #expect(place([zigzag]).isEmpty)
    }

    @Test("A long line carries the name again, far enough from the first")
    func repeats() {
        let labels = place([line([(-1000, 100), (2400, 100)])], width: 1200)
        #expect(labels.count >= 3)
        let centres = labels.map { ($0.glyphs.map(\.position.x).reduce(0, +)) / Double($0.glyphs.count) }
        for (a, b) in zip(centres.sorted(), centres.sorted().dropFirst()) { #expect(b - a >= 200) }
        #expect(labels.allSatisfy { $0.glyphs.allSatisfy { $0.position.x >= 0 && $0.position.x <= 1200 } }, "only inside the view")
    }

    @Test("The same name does not repeat within 200 points: two ways of one street carry it once")
    func sameNameApart() {
        let labels = place([line(1, [(20, 100), (180, 100)]), line(2, [(170, 100), (300, 100)])])
        #expect(labels.count == 1)
        let different = place([line(1, "Aaa", [(20, 100), (180, 100)]), line(2, "Bbb", [(200, 100), (380, 100)])])
        #expect(different.count == 2)
    }

    @Test("A name does not run over a point label, and a higher priority name wins a crossing")
    func collisions() throws {
        let symbol = LabelCandidate(
            objectID: 9, text: "Café", anchor: ScreenPoint(x: 200, y: 100), symbolRadius: 3, fontSize: 10,
            style: LabelStyle(size: ZoomValue(constant: 10), color: .black, priority: 50))
        let over = place([line([(20, 100), (380, 100)])], points: [symbol])
        #expect(over.contains { $0.glyphs.isEmpty } && !over.contains { label in
            label.glyphs.contains { abs($0.position.x - 200) < 10 && abs($0.position.y - 100) < 10 }
        })
        let crossing = place([
            line(1, "Alpha road", [(20, 150), (380, 150)], priority: 10),
            line(2, "Beta road", [(200, 20), (200, 280)], priority: 20),
        ])
        #expect(crossing.first?.text == "Beta road")
        // Whatever was placed, no letter of one label touches a letter of another.
        let alpha = crossing.filter { $0.text == "Alpha road" }.flatMap(\.glyphs)
        let beta = crossing.filter { $0.text == "Beta road" }.flatMap(\.glyphs)
        for a in alpha {
            for b in beta { #expect(hypot(a.position.x - b.position.x, a.position.y - b.position.y) > 6) }
        }
    }

    @Test("Line labels count towards the most labels allowed")
    func maximum() {
        let labels = place([line(1, "Aaa", [(20, 50), (380, 50)]), line(2, "Bbb", [(20, 150), (380, 150)])], maximumCount: 1)
        #expect(labels.count == 1)
    }

    @Test("Letters outside the view are not placed: a line leaving the view is labelled where it is visible")
    func partlyOutside() throws {
        let label = try #require(place([line([(-600, 100), (150, 100)])]).first)
        #expect(label.glyphs.allSatisfy { $0.position.x >= 0 && $0.position.x <= 150 })
    }

    @Test("Character widths from the measurement set the spacing of the letters")
    func characterOffsets() throws {
        let offsets: (String, Double) -> [Double] = { text, _ in
            var result = [0.0]
            for character in text { result.append(result.last! + (character == "i" ? 2 : 8)) }
            return result
        }
        let label = try #require(
            LabelPlacer.place(
                [], lines: [line("ii", [(20, 100), (380, 100)])], viewWidth: 400, viewHeight: 300, characterOffsets: offsets,
                measure: { _, _ in (4, 10) }
            ).first)
        #expect(label.glyphs.map(\.width) == [2, 2])
        // A wrong number of offsets falls back to even spacing.
        let wrong = try #require(
            LabelPlacer.place(
                [], lines: [line("abc", [(20, 100), (380, 100)])], viewWidth: 400, viewHeight: 300,
                characterOffsets: { _, _ in [0, 1] }, measure: { _, _ in (30, 10) }
            ).first)
        #expect(wrong.glyphs.map(\.width) == [10, 10, 10])
    }

    // MARK: Path

    @Test("A polyline is cut at the edge of the view")
    func clipping() throws {
        let bounds = ScreenBounds(width: 100, height: 100, margin: 0)
        let runs = LabelPath.runs(of: [ScreenPoint(x: -50, y: 50), ScreenPoint(x: 150, y: 50)], in: bounds)
        #expect(runs.count == 1 && runs.first?.length == 100)
        // A line that leaves and comes back is two runs.
        let loop = LabelPath.runs(
            of: [ScreenPoint(x: 10, y: 50), ScreenPoint(x: 10, y: 200), ScreenPoint(x: 90, y: 200), ScreenPoint(x: 90, y: 50)],
            in: bounds)
        #expect(loop.count == 2)
        #expect(LabelPath.runs(of: [ScreenPoint(x: 200, y: 0), ScreenPoint(x: 300, y: 0)], in: bounds).isEmpty)
    }

    @Test("A degenerate line has no path")
    func degenerate() {
        #expect(LabelPath([ScreenPoint(x: 1, y: 1)]) == nil)
        #expect(LabelPath([ScreenPoint(x: 1, y: 1), ScreenPoint(x: 1, y: 1)]) == nil)
    }

    // MARK: Collecting

    private func scene(zoom: Double, name: String?, in featureClass: FeatureClass = .roadMinor) -> MapScene {
        let viewport = MapViewport(
            center: Coordinate(latitude: 60, longitude: 10), zoom: zoom, width: 400, height: 300)
        let road = SceneLine(
            featureClass: featureClass, objectID: 7, points: [ScreenPoint(x: 0, y: 100), ScreenPoint(x: 400, y: 100)], name: name)
        return MapScene(
            viewport: viewport, band: .detail,
            steps: [SceneStep(step: DrawStep(featureClass: featureClass, part: .body), lines: [road])], cellCount: 1)
    }

    @Test("Named lines of a class with a label style are collected, in the zoom range of the label")
    func collecting() {
        let style = MapStyle.standard
        #expect(LabelCandidates.collectLines(from: scene(zoom: 17, name: "Storgata"), style: style).map(\.text) == ["Storgata"])
        #expect(LabelCandidates.collectLines(from: scene(zoom: 13, name: "Storgata"), style: style).isEmpty, "too far out")
        #expect(LabelCandidates.collectLines(from: scene(zoom: 17, name: nil), style: style).isEmpty)
        #expect(LabelCandidates.collectLines(from: scene(zoom: 17, name: ""), style: style).isEmpty)
        #expect(LabelCandidates.collectLines(from: scene(zoom: 17, name: "Barrier", in: .barrier), style: style).isEmpty)
    }

    @Test("Roads, paths, rivers and borders have labels in the standard style, and the Watch style has none for lines")
    func standardStyleLabels() {
        for featureClass in [FeatureClass.roadMajor, .roadMinor, .roadService, .path, .track, .waterLine, .boundary, .countryBorder] {
            #expect(MapStyle.standard.style(for: featureClass)?.label != nil, "\(featureClass)")
        }
        for featureClass in [FeatureClass.roadMajor, .roadMinor, .path, .waterLine, .boundary, .countryBorder] {
            #expect(MapStyle.watch.style(for: featureClass)?.label == nil, "\(featureClass)")
        }
    }

    @Test("Border names are small, beside the border, and have no halo; street names are on the street")
    func borderLabelStyle() throws {
        for featureClass in [FeatureClass.boundary, .countryBorder] {
            let label = try #require(MapStyle.standard.style(for: featureClass)?.label)
            #expect(label.placement == .besideLine && label.haloWidth == 0, "\(featureClass)")
            for zoom in [6.0, 9, 12, 16, 20] { #expect(label.size.value(atZoom: zoom) <= 8, "\(featureClass) at \(zoom)") }
        }
        #expect(MapStyle.standard.style(for: .roadMinor)?.label?.placement == .onLine)
    }

    // MARK: Drawing

    /// The number of dark pixels (the label text is dark grey; the road is white with a light grey outline) in a PNG.
    private func darkPixels(in png: Data) throws -> Int {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: buffer.count, by: 4).filter { buffer[$0] < 0x80 && buffer[$0 + 1] < 0x80 && buffer[$0 + 2] < 0x80 }.count
    }

    @Test("The renderer draws the name along the road, upright and turned with the line, and nothing without a name")
    func drawn() throws {
        for points in [[(20.0, 150.0), (380.0, 150.0)], [(20.0, 250.0), (380.0, 50.0)]] {
            func render(_ name: String?) throws -> Int {
                var scene = scene(zoom: 17, name: name)
                scene.steps[0].lines[0].points = points.map { ScreenPoint(x: $0.0, y: $0.1) }
                return try darkPixels(in: CoreGraphicsRenderer().pngData(for: scene, style: .standard, scale: 2))
            }
            let without = try render(nil)
            let with = try render("Storgata")
            #expect(without == 0)
            #expect(with > 100, "the letters are drawn")
        }
    }
}
