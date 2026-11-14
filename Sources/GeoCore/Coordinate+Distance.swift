import Foundation

extension Coordinate {
    /// The mean radius of the Earth in metres (IUGG), used for distances on the sphere.
    public static let earthRadius: Double = 6_371_008.8

    /// The great-circle distance to another coordinate in metres, by the haversine formula on a sphere of the mean Earth radius.
    ///
    /// The sphere is within 0.5 % of the ellipsoid for distances on foot or by bike, which is far less than the error of a GPS track.
    /// Both coordinates should be valid (see ``isValid``): the result for NaN or out-of-range input is not meaningful.
    ///
    /// - Parameter other: The other position.
    /// - Returns: The distance in metres, 0 or more.
    public func distance(to other: Coordinate) -> Double {
        let toRadians = Double.pi / 180
        let phi1 = latitude * toRadians, phi2 = other.latitude * toRadians
        let deltaPhi = (other.latitude - latitude) * toRadians
        let deltaLambda = (other.longitude - longitude) * toRadians
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * Self.earthRadius * asin(min(1, sqrt(a)))
    }
}
