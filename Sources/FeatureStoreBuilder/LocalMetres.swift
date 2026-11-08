import FeatureStore
import Foundation
import GeoCore

/// A flat projection to metres around one latitude.
///
/// Longitude is scaled by the cosine of one reference latitude (the middle of the area), latitude by the length of a degree.
/// The projection is a plain scaling of both axes, so it keeps directions and straight lines: a step north is a step north at
/// any longitude. East-west distances are wrong by the ratio of the cosines of the latitude of the point and the reference, which
/// is below half a percent within 30 km of the reference at 60 degrees. (An earlier version scaled by the cosine of each
/// point's own latitude. That shears the plane in proportion to the longitude, so 100 m north at 25 degrees east also moved
/// 37 m east.) It is not meant for anything that is stored.
struct LocalMetres {
    private let metresPerDegree = Geodesy.earthRadius * Double.pi / 180
    private let longitudeScale: Double

    /// Creates the projection around a latitude.
    ///
    /// - Parameter referenceLatitude: The latitude, in degrees, at which east-west distances are exact.
    init(referenceLatitude: Double) {
        longitudeScale = metresPerDegree * cos(referenceLatitude * Double.pi / 180)
    }

    /// Creates the projection around the middle of a box.
    init(around box: BoundingBox) {
        self.init(referenceLatitude: (box.south + box.north) / 2)
    }

    /// The position of a point in metres east and north of the origin of longitude and latitude.
    func project(_ point: PackedPoint) -> (x: Double, y: Double) {
        (Double(point.longitude) / 1e7 * longitudeScale, Double(point.latitude) / 1e7 * metresPerDegree)
    }
}
