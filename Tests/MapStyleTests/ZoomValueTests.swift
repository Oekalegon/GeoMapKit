import Testing

@testable import MapStyle

@Suite("ZoomValue")
struct ZoomValueTests {
    @Test func constantValueIsTheSameEverywhere() {
        let value = ZoomValue<Double>(constant: 2)
        #expect(value.value(atZoom: -3) == 2)
        #expect(value.value(atZoom: 12) == 2)
        #expect(value.value(atZoom: 30) == 2)
    }

    @Test func interpolatesLinearlyAndClampsOutsideTheStops() {
        let value = ZoomValue((12, 1.0), (16, 3.0))
        #expect(value.value(atZoom: 8) == 1)
        #expect(value.value(atZoom: 12) == 1)
        #expect(value.value(atZoom: 14) == 2)
        #expect(value.value(atZoom: 13.5) == 1.75)
        #expect(value.value(atZoom: 16) == 3)
        #expect(value.value(atZoom: 20) == 3)
    }

    @Test func stopsMayBeGivenOutOfOrder() {
        let value = ZoomValue((16, 3.0), (12, 1.0), (14, 1.5))
        #expect(value.stops.map(\.zoom) == [12, 14, 16])
        #expect(value.value(atZoom: 15) == 2.25)
    }

    @Test func laterStopWinsAtEqualZoom() {
        let value = ZoomValue((12, 1.0), (12, 5.0), (14, 7.0))
        #expect(value.stops.count == 2)
        #expect(value.value(atZoom: 12) == 5)
    }

    @Test func nanZoomGivesTheFirstValue() {
        #expect(ZoomValue((12, 1.0), (16, 3.0)).value(atZoom: .nan) == 1)
    }

    @Test func colorsInterpolateComponentWise() {
        let value = ZoomValue((0, MapColor.black), (10, MapColor.white))
        let mid = value.value(atZoom: 5)
        #expect(mid.red == 0.5 && mid.green == 0.5 && mid.blue == 0.5 && mid.alpha == 1)
    }

    @Test func colorComponentsAreClamped() {
        let color = MapColor(red: 2, green: -1, blue: .nan, alpha: 5)
        #expect(color == MapColor(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(MapColor(hex: 0xFF8000).green == Double(0x80) / 255)
    }
}
