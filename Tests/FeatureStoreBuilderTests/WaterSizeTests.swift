import FeatureStore
import Testing

@testable import FeatureStoreBuilder

/// Which water areas the overview band holds: not the ditches and canals of a polder, not the ponds.
@Suite("Water size")
struct WaterSizeTests {
    /// A rectangle of `width` × `length` metres at 52° N, as a closed ring.
    private func rectangle(width: Double, length: Double) -> [PackedPoint] {
        let latitude = 52.0
        let dLon = Int32(length / (111_320 * 0.6157) * 1e7), dLat = Int32(width / 110_574 * 1e7)
        let lon: Int32 = 50_000_000, lat = Int32(latitude * 1e7)
        return [
            PackedPoint(longitude: lon, latitude: lat), PackedPoint(longitude: lon + dLon, latitude: lat),
            PackedPoint(longitude: lon + dLon, latitude: lat + dLat), PackedPoint(longitude: lon, latitude: lat + dLat),
            PackedPoint(longitude: lon, latitude: lat),
        ]
    }

    private let water = Classification(featureClass: .waterArea, subclass: 1, kind: .area, minimumBand: .overview, showsOnWatch: true)

    @Test func aDitchAFewMetresWideAndKilometresLongIsSmall() {
        #expect(WaterSize.isSmall([rectangle(width: 6, length: 4_000)]))
        #expect(WaterSize.adjusted(water, rings: [rectangle(width: 6, length: 4_000)]).minimumBand == .mid)
    }

    @Test func aCanalOfThirtyMetresIsSmallAndARiverOfTwoHundredIsNot() {
        #expect(WaterSize.isSmall([rectangle(width: 30, length: 8_000)]))
        #expect(!WaterSize.isSmall([rectangle(width: 200, length: 8_000)]))
    }

    @Test func aPondIsSmallAndALakeIsNot() {
        #expect(WaterSize.isSmall([rectangle(width: 100, length: 150)]), "1.5 hectares")
        #expect(!WaterSize.isSmall([rectangle(width: 600, length: 800)]), "48 hectares")
    }

    @Test func onlyWaterAreasInTheOverviewBandAreMoved() {
        let ditch = [rectangle(width: 5, length: 3_000)]
        let mid = Classification(featureClass: .waterArea, subclass: 1, kind: .area, minimumBand: .detail, showsOnWatch: false)
        #expect(WaterSize.adjusted(mid, rings: ditch).minimumBand == .detail, "a lower band is never raised to mid")
        let forest = Classification(featureClass: .forest, subclass: 0, kind: .area, minimumBand: .overview, showsOnWatch: true)
        #expect(WaterSize.adjusted(forest, rings: ditch) == forest)
        #expect(WaterSize.adjusted(water, rings: ditch).showsOnWatch && WaterSize.adjusted(water, rings: ditch).subclass == 1)
    }

    @Test func aRingWithNoLengthIsSmall() {
        #expect(WaterSize.isSmall([]))
    }
}

@Suite("Park size")
struct ParkSizeTests {
    private func square(sideKilometres: Double) -> [PackedPoint] {
        let dLon = Int32(sideKilometres * 1000 / (111_320 * 0.6157) * 1e7), dLat = Int32(sideKilometres * 1000 / 110_574 * 1e7)
        let lon: Int32 = 50_000_000, lat: Int32 = 520_000_000
        return [
            PackedPoint(longitude: lon, latitude: lat), PackedPoint(longitude: lon + dLon, latitude: lat),
            PackedPoint(longitude: lon + dLon, latitude: lat + dLat), PackedPoint(longitude: lon, latitude: lat + dLat),
            PackedPoint(longitude: lon, latitude: lat),
        ]
    }

    @Test func aSmallReserveIsSmallAndANationalParkIsNot() {
        #expect(ParkSize.isSmall([square(sideKilometres: 3)]), "9 km²")
        #expect(!ParkSize.isSmall([square(sideKilometres: 8)]), "64 km²")
    }

    @Test func anOutlineThatIsNotClosedIsKeptBecauseItsSizeIsNotKnown() {
        #expect(!ParkSize.isSmall([Array(square(sideKilometres: 1).dropLast())]))
        #expect(!ParkSize.isSmall([]))
    }
}
