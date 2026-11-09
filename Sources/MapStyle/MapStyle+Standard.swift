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
            .landuseUrban: ClassStyle(fill: FillStyle(color: .color(0xE6E0D8)), visibleZoom: 9...24, layer: 10),
            .landcover: ClassStyle(fill: FillStyle(color: .color(0xDDE8C8)), visibleZoom: 10...24, layer: 11),
            // Ground that is not vegetation (rule table 18): bare rock, scree and sand in a grey beige, wetland in a bluish green, and
            // glaciers white with a light blue border (on the layer of the forest, above it, because a glacier lies over the land cover).
            .bareGround: ClassStyle(fill: FillStyle(color: .color(0xDEDAD2)), visibleZoom: 10...24, layer: 11),
            // Sand and beaches in a light yellow, on the layer of the forest (and above it): open sand lies between woods (inland dunes), and a
            // forest polygon that covers it must not hide it.
            .sand: ClassStyle(fill: FillStyle(color: .color(0xF3E9BF)), visibleZoom: 10...24, layer: 12),
            .wetland: ClassStyle(fill: FillStyle(color: .color(0xC4DDD6)), visibleZoom: 10...24, layer: 11),
            .glacier: ClassStyle(
                fill: FillStyle(color: .color(0xFFFFFF)), stroke: .line(0x7FB5DC, ZoomValue((9, 0.8), (16, 1.5))), visibleZoom: 9...24, layer: 12),
            // Military land, an area to keep out of: a dashed red outline and a faint red tint (26 of 255, a value that survives the JSON round trip). The tint is translucent and drawn above the
            // water, so a military area at sea (a radar sector, a firing range) shows the water and the land under it.
            .militaryArea: ClassStyle(
                fill: FillStyle(color: .color(0xD03030, alpha: 26.0 / 255)),
                stroke: .line(0xC02020, ZoomValue((9, 0.8), (16, 1.5)), dash: [6, 3]), visibleZoom: 9...24, layer: 16),
            .forest: ClassStyle(fill: FillStyle(color: .color(0xC5DDB0)), layer: 12),
            .waterArea: ClassStyle(fill: FillStyle(color: .color(0xAAD3EA)), layer: 13),
            // Buildings from zoom 14 as a fill, which shows where a town is built; the outline fades in by zoom 15.
            .building: ClassStyle(
                fill: FillStyle(color: .color(0xD9D0C9)),
                stroke: StrokeStyle(
                    color: ZoomValue((14.5, MapColor(hex: 0xBFB5AB, alpha: 0)), (15, MapColor(hex: 0xBFB5AB))),
                    width: LineWidth(points: .constant(0.5))),
                visibleZoom: 14...24, layer: 14),
            // The names of the two regions a border separates are written small along it, each on the side of its region.
            .boundary: ClassStyle(
                stroke: .line(0x9E7CB1, ZoomValue((8, 0.8), (16, 1.5)), dash: [6, 3]),
                label: LabelStyle(
                    size: ZoomValue((9, 5.5), (14, 6.5)), color: MapColor(hex: 0x7B5A91), haloWidth: 0, priority: 22,
                    visibleZoom: 9...24, placement: .besideLine),
                layer: 20),
            // The border of a national park or a nature reserve: dark green on land, dark blue in the sea.
            .parkBorder: ClassStyle(
                stroke: .line(0x2E6B34, ZoomValue((8, 0.8), (16, 1.5)), dash: [6, 3]), layer: 20),
            .parkBorderSea: ClassStyle(
                stroke: .line(0x2A5C9A, ZoomValue((8, 0.8), (16, 1.5)), dash: [6, 3]), layer: 20),
            // The outline of a lake, a fjord or a wide river, in the colour of the coastline; the stretches on a coast are left
            // out when the file is built, so that no line runs across a river mouth.
            .waterEdge: ClassStyle(stroke: .line(0x6FA8C8, ZoomValue((8, 0.5), (16, 1.2))), layer: 14),
            // Piers and breakwaters: white like the streets, with a fine grey casing; a filled area is white too.
            .pier: ClassStyle(
                fill: FillStyle(color: .color(0xFFFFFF)),
                stroke: StrokeStyle(
                    color: .color(0xFFFFFF), width: LineWidth(points: ZoomValue((14, 0.8), (18, 3))),
                    casing: .init(color: .color(0xBBBBBB), extraPoints: ZoomValue((14, 0), (15, 0.3), (18, 0.8)))),
                visibleZoom: 14...24, layer: 15),
            // A national border: the boundary line on a wide, solid, transparent band of the same colour.
            .countryBorder: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0x9E7CB1), width: LineWidth(points: ZoomValue((8, 0.8), (16, 1.5))), dash: [6, 3],
                    casing: .init(color: ZoomValue(constant: MapColor(hex: 0x9E7CB1, alpha: 115.0 / 255)), extraPoints: ZoomValue((8, 2), (12, 3), (16, 6)))),
                label: LabelStyle(
                    size: ZoomValue((6, 5.5), (10, 6.5), (14, 7.5)), color: MapColor(hex: 0x7B5A91), haloWidth: 0, priority: 24,
                    visibleZoom: 6...24, placement: .besideLine),
                layer: 20),
            .waterLine: ClassStyle(
                stroke: .line(0x6FB3DB, ZoomValue((8, 0.6), (12, 1.2), (17, 3))),
                label: LabelStyle(size: .constant(10), color: MapColor(hex: 0x2F6F9F), priority: 20, visibleZoom: 11...24), layer: 21,
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
                label: LabelStyle(
                    size: ZoomValue((15, 8.5), (18, 10)), color: MapColor(hex: 0x555555), priority: 10, visibleZoom: 15...24),
                visibleZoom: 12...24, layer: 30, casingLayer: 29,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.6), (16, 1.8)))),
                tunnel: TunnelStyle(opacity: 0.5, dash: [5, 3])),
            // Service roads (driveways, parking aisles, yard roads): runnable like a street but finer, so a dense area is not a
            // tangle of white lines. They are in the mid band with the streets, and show with them from zoom 12.
            .roadService: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0xFFFFFF),
                    width: LineWidth(
                        points: ZoomValue((12, 0.5), (16, 1.6)),
                        ground: GroundWidth(metresPerLane: 3, defaultLanes: 1)),
                    casing: .init(color: .color(0xBBBBBB), extraPoints: ZoomValue((14, 0), (15, 0.4), (18, 1)))),
                label: LabelStyle(size: .constant(8), color: MapColor(hex: 0x666666), priority: 6, visibleZoom: 17...24),
                visibleZoom: 12...24, layer: 30, casingLayer: 29,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.5), (16, 1.4)))),
                tunnel: TunnelStyle(opacity: 0.5, dash: [4, 3])),
            .roadMajor: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0xFDD27F),
                    width: LineWidth(
                        points: ZoomValue((8, 0.8), (12, 1.8), (16, 3.5)),
                        ground: GroundWidth(metresPerLane: 3, defaultLanes: 2)),
                    casing: .init(color: .color(0xB8862E), extraPoints: ZoomValue((10, 0.3), (14, 0.7), (18, 1.5)))),
                label: LabelStyle(size: .constant(10), color: MapColor(hex: 0x555555), priority: 15, visibleZoom: 12...24),
                layer: 31, casingLayer: 29,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.6), (16, 1.8)))),
                tunnel: TunnelStyle(opacity: 0.5, dash: [5, 3])),
            // Sidewalks and crossings: part of the street, so fainter and thinner than the paths a runner chooses.
            .pavement: ClassStyle(
                stroke: .line(0xE4B5A9, ZoomValue((15, 0.5), (18, 1.2))), visibleZoom: 15...24, layer: 38),
            .cliff: ClassStyle(
                stroke: .line(0x8C8279, ZoomValue((13, 0.8), (17, 1.6))), visibleZoom: 13...24, layer: 26),
            .track: ClassStyle(
                stroke: .line(0x8B5A2B, ZoomValue((12, 1.0), (16, 2.0)), dash: [6, 2]),
                label: LabelStyle(size: .constant(8.5), color: MapColor(hex: 0x6B4420), priority: 8, visibleZoom: 15...24),
                visibleZoom: 12...24, layer: 40,
                bridge: BridgeStyle(casing: .init(color: .color(0x4F4F4F), extraPoints: ZoomValue((12, 0.5), (16, 1.2)))),
                tunnel: TunnelStyle(opacity: 0.45)),
            .path: ClassStyle(
                stroke: .line(0xD2381C, ZoomValue((12, 1.0), (16, 2.0)), dash: [3, 2]),
                label: LabelStyle(size: .constant(8.5), color: MapColor(hex: 0xA02A14), priority: 8, visibleZoom: 16...24),
                visibleZoom: 12...24, layer: 41,
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
