import FeatureStore
import Foundation

/// Great-circle distances on 1e-7 degree coordinates.
enum Geodesy {
    static let earthRadius = 6_371_008.8

    /// The haversine distance in metres. The error against the ellipsoid is below 0.5 %.
    static func distance(_ a: PackedPoint, _ b: PackedPoint) -> Double {
        let toRadians = Double.pi / 180 / 1e7
        let lat1 = Double(a.latitude) * toRadians, lat2 = Double(b.latitude) * toRadians
        let dLat = lat2 - lat1
        let dLon = (Double(b.longitude) - Double(a.longitude)) * toRadians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }
}
