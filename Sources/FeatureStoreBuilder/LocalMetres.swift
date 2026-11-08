import FeatureStore
import Foundation
import GeoCore

/// A flat projection to metres around the middle latitude of an area.
///
/// Good to about a percent over the half degree an extract covers, which is enough to ask whether two things are 15 metres
/// apart. It is not meant for anything that is stored.
struct LocalMetres {
    private let metresPerDegreeLongitude: Double
    private let metresPerDegreeLatitude = Geodesy.earthRadius * Double.pi / 180

    /// - Parameter box: The area; the projection is exact at its middle latitude.
    init(around box: BoundingBox) {
        metresPerDegreeLongitude = Geodesy.earthRadius * Double.pi / 180 * cos((box.south + box.north) / 2 * Double.pi / 180)
    }

    /// The position of a point in metres east and north of the origin of longitude and latitude.
    func project(_ point: PackedPoint) -> (x: Double, y: Double) {
        (Double(point.longitude) / 1e7 * metresPerDegreeLongitude, Double(point.latitude) / 1e7 * metresPerDegreeLatitude)
    }
}
