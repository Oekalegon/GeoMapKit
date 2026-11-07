extension MapStyle {
    /// The reduced, high-contrast style for the Watch.
    ///
    /// It draws only the classes of the Watch profile (see "Feature classes" in the
    /// architecture document) and only from zoom 12, because the Watch holds the mid
    /// and detail bands. Lines are thicker than in ``standard`` and have no casing and no
    /// dashes, and only places are labelled, so a small screen in sunlight stays readable and each
    /// stroke is one cheap path. Hidden classes simply have no entry.
    public static let watch = MapStyle(
        name: "Watch", background: MapColor(hex: 0x000000),
        classes: [
            .landcover: ClassStyle(fill: FillStyle(color: .color(0x1E2A18)), visibleZoom: 12...24, layer: 10),
            .forest: ClassStyle(fill: FillStyle(color: .color(0x203A22)), visibleZoom: 12...24, layer: 11),
            .waterArea: ClassStyle(fill: FillStyle(color: .color(0x123A5C)), visibleZoom: 12...24, layer: 12),
            .waterLine: ClassStyle(
                stroke: .line(0x3D8FD1, ZoomValue((12, 1.2), (17, 3))), visibleZoom: 12...24, layer: 20),
            .railway: ClassStyle(stroke: .line(0x888888, .constant(1.5)), visibleZoom: 12...24, layer: 21),
            .powerLine: ClassStyle(stroke: .line(0x555555, .constant(1)), visibleZoom: 14...24, layer: 22),
            .aerialway: ClassStyle(stroke: .line(0xBBBBBB, .constant(1.2)), visibleZoom: 12...24, layer: 23),
            .piste: ClassStyle(stroke: .line(0x5A8DEE, .constant(1.5)), visibleZoom: 12...24, layer: 24),
            .roadMinor: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0xCCCCCC),
                    width: LineWidth(
                        points: ZoomValue((12, 1.5), (16, 3)),
                        ground: GroundWidth(metresPerLane: 3, defaultLanes: 2))),
                visibleZoom: 12...24, layer: 30),
            .roadMajor: ClassStyle(
                stroke: StrokeStyle(
                    color: .color(0xFFC857),
                    width: LineWidth(
                        points: ZoomValue((12, 2), (16, 4)),
                        ground: GroundWidth(metresPerLane: 3, defaultLanes: 2))),
                visibleZoom: 12...24, layer: 31),
            .track: ClassStyle(stroke: .line(0xC98B4E, ZoomValue((12, 1.8), (16, 3))), visibleZoom: 12...24, layer: 40),
            .path: ClassStyle(stroke: .line(0xFF5A3C, ZoomValue((12, 2), (16, 3.5))), visibleZoom: 12...24, layer: 41),
            .poiAnchor: ClassStyle(
                point: PointStyle(radius: .constant(4), color: .color(0x4FC3F7), outlineColor: .black),
                visibleZoom: 14...24, layer: 50),
            .peak: ClassStyle(
                point: PointStyle(radius: .constant(4), color: .color(0xBCAAA4), outlineColor: .black),
                visibleZoom: 12...24, layer: 51),
            .place: ClassStyle(
                label: LabelStyle(
                    size: .constant(13), color: .white, haloColor: .black, haloWidth: 2, priority: 50),
                visibleZoom: 12...24, layer: 60),
        ])
}
