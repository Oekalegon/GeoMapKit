extension MapStyle {
    /// The default style for iOS, iPadOS and macOS: every class, light colours, trails drawn on top.
    ///
    /// Roads take their real width from the `lanes` tag when zoomed in (3 m per lane,
    /// two lanes when untagged); paths and tracks keep a screen width so they stay visible.
    public static let standard = MapStyle(
        name: "Standard", background: MapColor(hex: 0xF2EFE9),
        classes: [
            .landuseUrban: ClassStyle(fill: FillStyle(color: .color(0xE6E0D8)), visibleZoom: 12...24, layer: 10),
            .landcover: ClassStyle(fill: FillStyle(color: .color(0xDDE8C8)), visibleZoom: 12...24, layer: 11),
            .forest: ClassStyle(fill: FillStyle(color: .color(0xC5DDB0)), layer: 12),
            .waterArea: ClassStyle(fill: FillStyle(color: .color(0xAAD3EA)), layer: 13),
            .building: ClassStyle(
                fill: FillStyle(color: .color(0xD9D0C9)), stroke: .line(0xBFB5AB, .constant(0.5)),
                visibleZoom: 15...24, layer: 14),
            .boundary: ClassStyle(
                stroke: .line(0x9E7CB1, ZoomValue((8, 0.8), (16, 1.5)), dash: [6, 3]), layer: 20),
            .waterLine: ClassStyle(
                stroke: .line(0x6FB3DB, ZoomValue((8, 0.6), (12, 1.2), (17, 3))),
                label: LabelStyle(size: .constant(10), color: MapColor(hex: 0x2F6F9F), priority: 20), layer: 21),
            .railway: ClassStyle(
                stroke: .line(0x777777, ZoomValue((8, 0.6), (14, 1.4)), dash: [4, 3]), layer: 22),
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
                    casing: .init(color: .color(0xBBBBBB), extraPoints: 0.6)),
                visibleZoom: 12...24, layer: 30),
            .roadMajor: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0xFDD27F),
                    width: LineWidth(
                        points: ZoomValue((8, 0.8), (12, 1.8), (16, 3.5)),
                        ground: GroundWidth(metresPerLane: 3, defaultLanes: 2)),
                    casing: .init(color: .color(0xC9A24B), extraPoints: 0.7)),
                label: LabelStyle(size: .constant(10), color: MapColor(hex: 0x555555), priority: 15), layer: 31),
            .track: ClassStyle(
                stroke: .line(0x8B5A2B, ZoomValue((12, 1.0), (16, 2.0)), dash: [6, 2]), visibleZoom: 12...24,
                layer: 40),
            .path: ClassStyle(
                stroke: .line(0xD2381C, ZoomValue((12, 1.0), (16, 2.0)), dash: [3, 2]), visibleZoom: 12...24,
                layer: 41),
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
