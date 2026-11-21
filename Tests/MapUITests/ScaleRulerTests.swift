import Foundation
import GeoCore
import MapRender
import SwiftUI
import Testing

@testable import MapUI

@Suite("Scale ruler")
struct ScaleRulerTests {
    @Test("A point at zoom 0 on the equator is the world's circumference over 256, and the scale grows with the latitude")
    func metresPerPoint() {
        let equator = ScaleRuler.metresPerPoint(latitude: 0, zoom: 0)
        #expect(abs(equator - 2 * .pi * Coordinate.earthRadius / 256) < 1e-6)
        #expect(abs(ScaleRuler.metresPerPoint(latitude: 0, zoom: 3) - equator / 8) < 1e-6)
        // At 60° N a point is half as long on the ground (cos 60° = 0.5).
        #expect(abs(ScaleRuler.metresPerPoint(latitude: 60, zoom: 5) / ScaleRuler.metresPerPoint(latitude: 0, zoom: 5) - 0.5) < 1e-9)
        // Past the Mercator limit and non-finite values are brought in, not NaN.
        #expect(ScaleRuler.metresPerPoint(latitude: 90, zoom: 5).isFinite && ScaleRuler.metresPerPoint(latitude: .nan, zoom: 5).isFinite)
    }

    @Test("The metric ruler is the largest 1, 2 or 5 that fits, in metres or kilometres, and is never wider than the maximum")
    func metric() throws {
        // Zoom 15 at the equator: 4.78 m per point, so 120 points are 573 m: the ruler is 500 m.
        let ruler = try #require(ScaleRuler.make(latitude: 0, zoom: 15, maximumWidth: 120, units: .metric))
        #expect(ruler.label == "500 m" && ruler.distance == 500)
        #expect(abs(ruler.length - 500 / ScaleRuler.metresPerPoint(latitude: 0, zoom: 15)) < 1e-9 && ruler.length <= 120)
        let far = try #require(ScaleRuler.make(latitude: 0, zoom: 8, maximumWidth: 120, units: .metric))
        #expect(far.label == "50 km")
        #expect(far.length <= 120 && far.length > 120 / 2.5)
        #expect(try #require(ScaleRuler.make(latitude: 60, zoom: 12, maximumWidth: 100, units: .metric)).label.hasSuffix("km"))
    }

    @Test("Whatever the zoom and latitude, the bar fits and is at least 40% of the maximum width (the next number is at most 2.5 times larger)")
    func fits() throws {
        for units in ScaleRulerUnits.allCases {
            for latitude in stride(from: -80.0, through: 80, by: 20) {
                for zoom in stride(from: 3.0, through: 20, by: 0.7) {
                    guard let ruler = ScaleRuler.make(latitude: latitude, zoom: zoom, maximumWidth: 120, units: units) else { continue }
                    #expect(ruler.length <= 120 + 1e-9 && ruler.length >= 120 / 2.5 - 1e-9, "\(units) \(latitude) \(zoom): \(ruler.length) \(ruler.label)")
                }
            }
        }
    }

    @Test("The imperial ruler is in feet below a quarter of a mile and in miles above, with a quarter and a half")
    func imperial() throws {
        // Zoom 18 at the equator: 0.597 m per point, 120 points are 71.6 m, 235 ft: 200 ft.
        let feet = try #require(ScaleRuler.make(latitude: 0, zoom: 18, maximumWidth: 120, units: .imperial))
        #expect(feet.label == "200 ft" && abs(feet.length - 200 * 0.3048 / ScaleRuler.metresPerPoint(latitude: 0, zoom: 18)) < 1e-9)
        // Zoom 15: 573 m = 0.356 mi: a quarter of a mile.
        #expect(try #require(ScaleRuler.make(latitude: 0, zoom: 15, maximumWidth: 120, units: .imperial)).label == "0.25 mi")
        // Zoom 14: 1.15 km = 0.71 mi: half a mile. Zoom 13: 2.29 km = 1.4 mi: 1 mi.
        #expect(try #require(ScaleRuler.make(latitude: 0, zoom: 14, maximumWidth: 120, units: .imperial)).label == "0.5 mi")
        #expect(try #require(ScaleRuler.make(latitude: 0, zoom: 13, maximumWidth: 120, units: .imperial)).label == "1 mi")
    }

    @Test("There is no ruler when even 1 m does not fit, or the numbers are not finite")
    func none() {
        #expect(ScaleRuler.make(latitude: 0, zoom: 20, maximumWidth: 5, units: .metric) == nil)
        #expect(ScaleRuler.make(latitude: 0, zoom: 10, maximumWidth: 0, units: .metric) == nil)
        #expect(ScaleRuler.make(latitude: 0, zoom: 10, maximumWidth: .infinity, units: .metric) == nil)
    }

    @Test("The ruler of a view uses the latitude of the place where it is drawn, also for a turned map")
    func viewport() throws {
        let view = MapViewport(center: Coordinate(latitude: 60, longitude: 10), zoom: 12, width: 600, height: 800)
        let ruler = try #require(ScaleRuler.make(in: view, maximumWidth: 120, units: .metric))
        let place = view.coordinate(at: ScreenPoint(x: 71, y: 788))
        #expect(ruler == ScaleRuler.make(latitude: place.latitude, zoom: 12, maximumWidth: 120, units: .metric))
        #expect(place.latitude < 60)
        // Turned by 90° the lower left corner is on another side of the map: a different latitude, so a different ruler place.
        let turned = MapViewport(center: Coordinate(latitude: 60, longitude: 10), zoom: 12, width: 600, height: 800, bearing: 90)
        let turnedPlace = turned.coordinate(at: ScreenPoint(x: 71, y: 788))
        #expect(abs(turnedPlace.latitude - place.latitude) > 0.001)
        #expect(ScaleRuler.make(in: turned, maximumWidth: 120, units: .metric) == ScaleRuler.make(latitude: turnedPlace.latitude, zoom: 12, maximumWidth: 120, units: .metric))
    }

    @Test("The visibility: hidden never, always always, and after moving while moving and for the delay after")
    func visibility() {
        let after = ScaleRulerVisibility.afterMoving(delay: .seconds(2))
        #expect(!ScaleRulerVisibility.hidden.isShown(moving: true, idleFor: .zero))
        #expect(ScaleRulerVisibility.always.isShown(moving: false, idleFor: .seconds(100)))
        #expect(after.isShown(moving: true, idleFor: .seconds(100)))
        #expect(after.isShown(moving: false, idleFor: .seconds(1)))
        #expect(!after.isShown(moving: false, idleFor: .seconds(2)))
        #expect(after.delay == .seconds(2) && ScaleRulerVisibility.always.delay == nil && ScaleRulerVisibility.hidden.delay == nil)
    }

    @Test("The settings keep the width sensible, and a map has no ruler unless the app asks")
    func settings() {
        #expect(ScaleRulerSettings(visibility: .always, maximumWidth: 1).maximumWidth == 20)
        #expect(ScaleRulerSettings(visibility: .always, maximumWidth: .nan).maximumWidth == 120)
        #expect(ScaleRulerSettings.hidden.visibility == .hidden && EnvironmentValues().mapScaleRuler == .hidden)
        #expect(ScaleRulerUnits.preferred(for: Locale(identifier: "en_US")) == .imperial)
        #expect(ScaleRulerUnits.preferred(for: Locale(identifier: "nl_NL")) == .metric)
    }
}
