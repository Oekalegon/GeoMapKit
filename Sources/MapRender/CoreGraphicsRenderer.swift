import CoreGraphics
import CoreText
import MapStyle

/// Draws a ``MapScene`` into a `CGContext` with Core Graphics and Core Text.
///
/// The context must use screen points with the origin at the top-left corner and y growing downwards (flip it
/// first, as ``pngData(for:style:scale:)`` does). The renderer keeps no state: it only turns the scene's steps into
/// path, fill and stroke calls, so it is cheap to create and safe to share.
///
/// Order within a scene: background, then every step (casings before fills, so crossing outlines join), then the
/// labels on top.
public struct CoreGraphicsRenderer: MapRenderer {
    /// Creates a renderer.
    public init() {}

    /// Draws the scene into a context in screen points (origin top-left, y down).
    ///
    /// The data credit of the scene is drawn last, in the bottom-right corner, as the style's `MapStyle.attribution` asks.
    public func draw(_ scene: MapScene, style: MapStyle, into context: CGContext) {
        let viewport = scene.viewport
        let zoom = viewport.zoom
        context.saveGState()
        defer { context.restoreGState() }
        let view = CGRect(x: 0, y: 0, width: viewport.width, height: viewport.height)
        context.clip(to: view)
        context.setFillColor(style.background.cgColor)
        context.fill(view)

        for sceneStep in scene.steps {
            guard let classStyle = style.style(for: sceneStep.step.featureClass) else { continue }
            switch sceneStep.step.part {
            case .casing:
                guard let stroke = classStyle.stroke(for: sceneStep.step.structure), let casing = stroke.casing else { continue }
                let extra = casing.extraPoints.value(atZoom: zoom)
                guard extra > 0 else { continue }
                let color = casing.color.value(atZoom: zoom)
                // A translucent casing is drawn as one group and blended once. Stroked piece by piece, the places where
                // two lines overlap or join would be blended twice and show darker.
                let translucent = color.alpha < 1
                context.saveGState()
                if translucent {
                    context.setAlpha(color.alpha)
                    context.beginTransparencyLayer(auxiliaryInfo: nil)
                }
                context.setStrokeColor(MapColor(red: color.red, green: color.green, blue: color.blue).cgColor)
                let opaque = MapColor(red: color.red, green: color.green, blue: color.blue)
                for line in sceneStep.lines {
                    let width = stroke.width.resolved(atZoom: zoom, metresPerPoint: viewport.metresPerPoint, lanes: line.lanes)
                    strokeLine(
                        line, width: width + 2 * extra, stroke: stroke, dashed: false, color: opaque, extra: extra,
                        taperLength: Self.taperLength(for: viewport), in: context)
                }
                if translucent { context.endTransparencyLayer() }
                context.restoreGState()
            case .body:
                drawBody(sceneStep, classStyle: classStyle, viewport: viewport, in: context)
            }
        }
        drawLabels(scene, style: style, in: context)
        drawAttribution(scene, display: style.attribution, in: context)
    }

    /// Draws the data credit in the bottom-right corner, small, on a light halo so it stays readable.
    ///
    /// What is drawn follows the style's `AttributionDisplay`: the full credit, a short mark, or nothing.
    private func drawAttribution(_ scene: MapScene, display: AttributionDisplay, in context: CGContext) {
        guard let text = display.text(for: scene.attribution) else { return }
        let fontSize = 8.0
        let size = Self.measure(text, fontSize)
        let origin = ScreenPoint(
            x: max(scene.viewport.width - size.width - 4, 2), y: max(scene.viewport.height - size.height - 3, 0))
        let label = PlacedLabel(
            text: text, origin: origin, width: size.width, height: size.height, fontSize: fontSize,
            style: LabelStyle(size: ZoomValue(constant: fontSize), color: MapColor(hex: 0x333333), haloWidth: 2))
        drawLabel(label, in: context)
    }

    // MARK: Body

    private func drawBody(_ step: SceneStep, classStyle: ClassStyle, viewport: MapViewport, in context: CGContext) {
        let zoom = viewport.zoom
        for area in step.areas {
            if let fill = classStyle.fill, !area.isIncomplete {
                let color = fill.color.value(atZoom: zoom)
                context.setFillColor(color.cgColor)
                context.beginPath()
                for ring in area.rings { addClosed(ring, to: context) }
                context.fillPath(using: .evenOdd)
                if classStyle.stroke == nil, color.alpha >= 1 {
                    // A hairline in the fill colour closes the seams between neighbouring cells' pieces.
                    context.setStrokeColor(color.cgColor)
                    context.setLineWidth(0.5)
                    context.setLineJoin(.round)
                    context.beginPath()
                    for ring in area.rings { addClosed(ring, to: context) }
                    context.strokePath()
                }
            }
            if let stroke = classStyle.stroke {
                context.setStrokeColor(stroke.color.value(atZoom: zoom).cgColor)
                let width = stroke.width.resolved(atZoom: zoom, metresPerPoint: viewport.metresPerPoint, lanes: nil)
                for run in area.outline { strokePath(run, width: width, stroke: stroke, dashed: true, in: context) }
            }
        }
        if let stroke = classStyle.stroke(for: step.step.structure) {
            context.setStrokeColor(stroke.color.value(atZoom: zoom).cgColor)
            let color = stroke.color.value(atZoom: zoom)
            for line in step.lines {
                let width = stroke.width.resolved(atZoom: zoom, metresPerPoint: viewport.metresPerPoint, lanes: line.lanes)
                strokeLine(
                    line, width: width, stroke: stroke, dashed: true, color: color, extra: 0,
                    taperLength: Self.taperLength(for: viewport), in: context)
            }
        }
        if let point = classStyle.point {
            let radius = point.radius.value(atZoom: zoom)
            for item in step.points {
                let rect = CGRect(x: item.position.x - radius, y: item.position.y - radius, width: 2 * radius, height: 2 * radius)
                context.setFillColor(point.color.value(atZoom: zoom).cgColor)
                context.fillEllipse(in: rect)
                if point.outlineWidth > 0 {
                    context.setStrokeColor(point.outlineColor.cgColor)
                    context.setLineWidth(point.outlineWidth)
                    context.strokeEllipse(in: rect)
                }
            }
        }
    }

    /// Strokes a line. A line that ends flat at one end or both (where a bridge or a tunnel starts) is stroked with flat
    /// caps, and the end that is not flat gets its round cap drawn as a circle, so a junction with another road stays filled.
    /// A dashed line has its own dash caps and is only given flat ends.
    ///
    /// A road with a ``SceneLine/startWidth`` or ``SceneLine/endWidth`` is stroked in short pieces whose width changes
    /// from that width to its own over the first or last stretch (``taperLength(for:)``), so a change in lane count is a
    /// gradual widening instead of a step. A dashed line is not tapered.
    private func strokeLine(
        _ line: SceneLine, width: Double, stroke: StrokeStyle, dashed: Bool, color: MapColor, extra: Double, taperLength: Double,
        in context: CGContext
    ) {
        let solid = !(dashed && !stroke.dash.isEmpty)
        if solid, line.points.count >= 2, line.startWidth != nil || line.endWidth != nil {
            strokeTapered(
                line, width: width, stroke: stroke, color: color, startWidth: line.startWidth.map { $0 + 2 * extra },
                endWidth: line.endWidth.map { $0 + 2 * extra }, taperLength: taperLength, in: context)
            return
        }
        guard line.flatStart || line.flatEnd, stroke.cap == .round else {
            strokePath(line.points, width: width, stroke: stroke, dashed: dashed, in: context)
            return
        }
        var flat = stroke
        flat.cap = .butt
        strokePath(line.points, width: width, stroke: flat, dashed: dashed, in: context)
        guard !(dashed && !stroke.dash.isEmpty), width > 0 else { return }
        context.setFillColor(color.cgColor)
        for (isFlat, end) in [(line.flatStart, line.points.first), (line.flatEnd, line.points.last)] where !isFlat {
            guard let end else { continue }
            context.fillEllipse(in: CGRect(x: end.x - width / 2, y: end.y - width / 2, width: width, height: width))
        }
    }

    /// The length of the stretch over which a road blends from one width to another: about 15 m, and not less than 8 points.
    static func taperLength(for viewport: MapViewport) -> Double {
        max(8, 15 / max(viewport.metresPerPoint, 1e-9))
    }

    private func strokeTapered(
        _ line: SceneLine, width: Double, stroke: StrokeStyle, color: MapColor, startWidth: Double?, endWidth: Double?,
        taperLength: Double, in context: CGContext
    ) {
        let points = line.points
        var cumulative = [0.0]
        for index in 1..<points.count {
            cumulative.append(cumulative[index - 1] + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y))
        }
        let total = cumulative[cumulative.count - 1]
        guard total > 0 else { return }
        let startLength = startWidth == nil ? 0 : min(taperLength, total * 0.45)
        let endLength = endWidth == nil ? 0 : min(taperLength, total * 0.45)
        func widthAt(_ distance: Double) -> Double {
            if let startWidth, startLength > 0, distance < startLength {
                return startWidth + (width - startWidth) * distance / startLength
            }
            if let endWidth, endLength > 0, distance > total - endLength {
                return endWidth + (width - endWidth) * (total - distance) / endLength
            }
            return width
        }
        // Piece boundaries: short pieces over the blends, one piece for what lies between them.
        let pieceLength = 3.0
        var bounds = [0.0]
        if startLength > 0 {
            let count = max(4, Int((startLength / pieceLength).rounded(.up)))
            bounds += (1...count).map { startLength * Double($0) / Double(count) }
        }
        if endLength > 0 {
            let coreEnd = total - endLength
            if coreEnd > bounds[bounds.count - 1] + 1e-6 { bounds.append(coreEnd) }
            let count = max(4, Int((endLength / pieceLength).rounded(.up)))
            bounds += (1...count).map { coreEnd + endLength * Double($0) / Double(count) }
        } else if bounds[bounds.count - 1] < total {
            bounds.append(total)
        }
        let overlap = 0.75
        var flat = stroke
        flat.cap = .butt
        for index in 1..<bounds.count where bounds[index] > bounds[index - 1] {
            // Each piece runs a little into its neighbours, so anti-aliasing leaves no seam between them.
            let piece = Self.slice(
                points, cumulative: cumulative, from: max(bounds[index - 1] - overlap, 0), to: min(bounds[index] + overlap, total))
            strokePath(piece, width: widthAt((bounds[index - 1] + bounds[index]) / 2), stroke: flat, dashed: false, in: context)
        }
        // The ends that are not flat get their round cap as a circle of the width they have, if the line has round caps:
        // a bridge or a tunnel has flat ends (see `ClassStyle.stroke(for:)`) and so gets none.
        guard stroke.cap == .round else { return }
        context.setFillColor(color.cgColor)
        for (isFlat, end, distance) in [(line.flatStart, points[0], 0.0), (line.flatEnd, points[points.count - 1], total)] where !isFlat {
            let diameter = widthAt(distance)
            guard diameter > 0 else { continue }
            context.fillEllipse(in: CGRect(x: end.x - diameter / 2, y: end.y - diameter / 2, width: diameter, height: diameter))
        }
    }

    /// The part of a polyline between two distances along it.
    static func slice(_ points: [ScreenPoint], cumulative: [Double], from start: Double, to end: Double) -> [ScreenPoint] {
        func point(at distance: Double) -> ScreenPoint {
            var index = 0
            while index < points.count - 2, cumulative[index + 1] < distance { index += 1 }
            let span = cumulative[index + 1] - cumulative[index]
            let t = span > 0 ? min(max((distance - cumulative[index]) / span, 0), 1) : 0
            return ScreenPoint(
                x: points[index].x + (points[index + 1].x - points[index].x) * t,
                y: points[index].y + (points[index + 1].y - points[index].y) * t)
        }
        var result = [point(at: start)]
        for index in points.indices where cumulative[index] > start && cumulative[index] < end { result.append(points[index]) }
        result.append(point(at: end))
        return result
    }

    private func strokePath(_ points: [ScreenPoint], width: Double, stroke: StrokeStyle, dashed: Bool, in context: CGContext) {
        guard points.count >= 2, width > 0 else { return }
        context.setLineWidth(width)
        context.setLineCap(stroke.cap.cgLineCap)
        context.setLineJoin(stroke.join.cgLineJoin)
        context.setLineDash(phase: 0, lengths: dashed ? stroke.dash.map { CGFloat($0) } : [])
        context.beginPath()
        context.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for point in points.dropFirst() { context.addLine(to: CGPoint(x: point.x, y: point.y)) }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    private func addClosed(_ ring: [ScreenPoint], to context: CGContext) {
        guard let first = ring.first, ring.count >= 3 else { return }
        context.move(to: CGPoint(x: first.x, y: first.y))
        for point in ring.dropFirst() { context.addLine(to: CGPoint(x: point.x, y: point.y)) }
        context.closePath()
    }

    // MARK: Labels

    private func drawLabels(_ scene: MapScene, style: MapStyle, in context: CGContext) {
        let candidates = LabelCandidates.collect(from: scene, style: style)
        let labels = LabelPlacer.place(
            candidates, viewWidth: scene.viewport.width, viewHeight: scene.viewport.height,
            padding: style.labels.padding, maximumCount: style.labels.maximumCount, measure: Self.measure)
        for label in labels { drawLabel(label, in: context) }
    }

    private func drawLabel(_ label: PlacedLabel, in context: CGContext) {
        let line = Self.line(for: label.text, fontSize: label.fontSize)
        context.saveGState()
        defer { context.restoreGState() }
        // Core Text draws upright in a y-up space; the view is y-down, so flip around the baseline.
        context.translateBy(x: label.origin.x, y: label.origin.y + Self.ascent(of: line))
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        if label.style.haloWidth > 0 {
            context.setTextDrawingMode(.stroke)
            context.setStrokeColor(label.style.haloColor.cgColor)
            context.setLineWidth(label.style.haloWidth * 2)
            context.setLineJoin(.round)
            CTLineDraw(line, context)
        }
        // CTLineDraw moves the text position to the end of the line: start the fill pass at the same place.
        context.textPosition = .zero
        context.setTextDrawingMode(.fill)
        context.setFillColor(label.style.color.cgColor)
        CTLineDraw(line, context)
    }

    static func line(for text: String, fontSize: Double) -> CTLine {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    }

    static func ascent(of line: CTLine) -> Double {
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        return Double(ascent)
    }

    static func measure(_ text: String, _ fontSize: Double) -> (width: Double, height: Double) {
        let line = line(for: text, fontSize: fontSize)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        return (Double(width), Double(ascent + descent))
    }
}

extension LineCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .butt: .butt
        case .round: .round
        case .square: .square
        }
    }
}

extension LineJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter: .miter
        case .round: .round
        case .bevel: .bevel
        }
    }
}
