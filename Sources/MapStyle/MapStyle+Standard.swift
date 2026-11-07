extension MapStyle {
    /// The default style for iOS, iPadOS and macOS: every class, light colours, trails drawn on top.
    ///
    /// Roads take their real width from the `lanes` tag when zoomed in (3 m per lane,
    /// two lanes when untagged) and an outline (casing) that thickens as you zoom in; paths and tracks keep a screen width so they stay visible.
    public static let standard = MapStyle(
        name: "Standard", background: MapColor(hex: 0xF2EFE9),
        classes: [
            // The sea, under everything else; the coastline is a fine line on its edge.
            .sea: ClassStyle(fill: FillStyle(color: .color(0xAAD3EA)), layer: 9),
            .coastline: ClassStyle(stroke: .line(0x6FA8C8, ZoomValue((8, 0.5), (16, 1.2))), layer: 14),
            // A road that is an area (a yard, a square): filled like a road, with a thin outline, over the land cover and under the buildings and roads.
            .roadArea: ClassStyle(
                fill: FillStyle(color: .color(0xFFFFFF)), stroke: .line(0xB0B0B0, .constant(0.5)), visibleZoom: 14...24, layer: 13),
            .landuseUrban: ClassStyle(fill: FillStyle(color: .color(0xE6E0D8)), visibleZoom: 12...24, layer: 10),
            .landcover: ClassStyle(fill: FillStyle(color: .color(0xDDE8C8)), visibleZoom: 12...24, layer: 11),
            .forest: ClassStyle(fill: FillStyle(color: .color(0xC5DDB0)), layer: 12),
            .waterArea: ClassStyle(fill: FillStyle(color: .color(0xAAD3EA)), layer: 13),
            .building: ClassStyle(
                fill: FillStyle(color: .color(0xD9D0C9)), stroke: .line(0xBFB5AB, .constant(0.5)),
                visibleZoom: 15...24, layer: 14),
            .boundary: ClassStyle(
                stroke: .line(0x9E7CB1, ZoomValue((8, 0.8), (16, 1.5)), dash: [6, 3]), layer: 20),
            // A national border: the boundary line on a wide, solid, transparent band of the same colour.
            .countryBorder: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0x9E7CB1), width: LineWidth(points: ZoomValue((8, 0.8), (16, 1.5))), dash: [6, 3],
                    casing: .init(color: ZoomValue(constant: MapColor(hex: 0x9E7CB1, alpha: 115.0 / 255)), extraPoints: ZoomValue((8, 2), (12, 3), (16, 6)))),
                layer: 20),
            .waterLine: ClassStyle(
                stroke: .line(0x6FB3DB, ZoomValue((8, 0.6), (12, 1.2), (17, 3))),
                label: LabelStyle(size: .constant(10), color: MapColor(hex: 0x2F6F9F), priority: 20), layer: 21,
                tunnel: TunnelStyle(opacity: 0.6, dash: [3, 2])),
            .railway: ClassStyle(
                stroke: .line(0x777777, ZoomValue((8, 0.6), (14, 1.4))), layer: 22,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((10, 0.4), (16, 1.2)))),
                tunnel: TunnelStyle(opacity: 0.4, dash: [2, 3])),
            .powerLine: ClassStyle(
                stroke: .line(0x9A9A9A, .constant(0.6)), visibleZoom: 13...24, layer: 23),
            .aerialway: ClassStyle(
                stroke: .line(0x555555, .constant(0.8), dash: [2, 3]), visibleZoom: 12...24, layer: 24),
            .piste: ClassStyle(
                stroke: .line(0x4F7FD6, ZoomValue((12, 1.0), (16, 2.0)), dash: [5, 3]), visibleZoom: 12...24,
                layer: 25),
            .roadMinor: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0xFFFFFF),
                    width: LineWidth(
                        points: ZoomValue((12, 0.8), (16, 2.5)),
                        ground: GroundWidth(metresPerLane: 3, defaultLanes: 2)),
                    casing: .init(color: .color(0xAAAAAA), extraPoints: ZoomValue((13, 0), (15, 0.6), (18, 1.2)))),
                visibleZoom: 12...24, layer: 30, casingLayer: 29,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.6), (16, 1.8)))),
                tunnel: TunnelStyle(opacity: 0.5, dash: [5, 3])),
            .roadMajor: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0xFDD27F),
                    width: LineWidth(
                        points: ZoomValue((8, 0.8), (12, 1.8), (16, 3.5)),
                        ground: GroundWidth(metresPerLane: 3, defaultLanes: 2)),
                    casing: .init(color: .color(0xB8862E), extraPoints: ZoomValue((10, 0.3), (14, 0.7), (18, 1.5)))),
                label: LabelStyle(size: .constant(10), color: MapColor(hex: 0x555555), priority: 15), layer: 31, casingLayer: 29,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.6), (16, 1.8)))),
                tunnel: TunnelStyle(opacity: 0.5, dash: [5, 3])),
            // Sidewalks and crossings: part of the street, so fainter and thinner than the paths a runner chooses.
            .pavement: ClassStyle(
                stroke: .line(0xE4B5A9, ZoomValue((15, 0.5), (18, 1.2))), visibleZoom: 15...24, layer: 38),
            .cliff: ClassStyle(
                stroke: .line(0x8C8279, ZoomValue((13, 0.8), (17, 1.6))), visibleZoom: 13...24, layer: 26),
            .track: ClassStyle(
                stroke: .line(0x8B5A2B, ZoomValue((12, 1.0), (16, 2.0)), dash: [6, 2]), visibleZoom: 12...24,
                layer: 40,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.5), (16, 1.2)))),
                tunnel: TunnelStyle(opacity: 0.45)),
            .path: ClassStyle(
                stroke: .line(0xD2381C, ZoomValue((12, 1.0), (16, 2.0)), dash: [3, 2]), visibleZoom: 12...24,
                layer: 41,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.5), (16, 1.2)))),
                tunnel: TunnelStyle(opacity: 0.45)),
            .barrier: ClassStyle(stroke: .line(0x8A8A8A, .constant(0.6)), visibleZoom: 16...24, layer: 45),
            .tree: ClassStyle(
                point: PointStyle(radius: .constant(2), color: .color(0x7DB36B), outlineWidth: 0),
                visibleZoom: 17...24, layer: 50),
            .roadPoint: ClassStyle(
                point: PointStyle(radius: .constant(2), color: .color(0x888888), outlineWidth: 0),
                visibleZoom: 17...24, layer: 51),
            .transportStop: ClassStyle(
                point: PointStyle(radius: .constant(3), color: .color(0x2E6DB4)),
                label: LabelStyle(size: .constant(9), color: MapColor(hex: 0x2E6DB4), priority: 5),
                visibleZoom: 16...24, layer: 52),
            .poi: ClassStyle(
                point: PointStyle(radius: .constant(3), color: .color(0x7A7A7A)),
                label: LabelStyle(size: .constant(9), color: MapColor(hex: 0x555555), priority: 5),
                visibleZoom: 16...24, layer: 53),
            .poiAnchor: ClassStyle(
                point: PointStyle(radius: ZoomValue((15, 3), (17, 5)), color: .color(0x1E88E5)),
                label: LabelStyle(size: .constant(10), color: MapColor(hex: 0x1565C0), priority: 30),
                visibleZoom: 15...24, layer: 54),
            .peak: ClassStyle(
                point: PointStyle(radius: ZoomValue((12, 2.5), (15, 4)), color: .color(0x8D6E63)),
                label: LabelStyle(size: ZoomValue((12, 10), (15, 12)), color: MapColor(hex: 0x5D4037), priority: 40),
                visibleZoom: 12...24, layer: 60),
            .place: ClassStyle(
                label: LabelStyle(
                    size: ZoomValue((8, 11), (14, 15)), color: MapColor(hex: 0x222222), haloWidth: 2.5, priority: 50),
                layer: 61),
        ])
}
