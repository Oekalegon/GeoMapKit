import FeatureStore
import Foundation
import GeoCore

/// A flat projection to metres.
///
/// East-west distances are scaled by the cosine of the latitude of each point, so two points that are near each other get
/// distances that are right to a percent or better at any latitude; the shapes are slightly bent over a large area, which
/// does not matter for asking whether two things are 15 metres apart. It is not meant for anything that is stored.
struct LocalMetres {
    private let metresPerDegree = Geodesy.earthRadius * Double.pi / 180

    /// Creates the projection.
    init() {}

    /// The position of a point in metres east and north of the origin of longitude and latitude.
    func project(_ point: PackedPoint) -> (x: Double, y: Double) {
        let latitude = Double(point.latitude) / 1e7
        return (Double(point.longitude) / 1e7 * metresPerDegree * cos(latitude * Double.pi / 180), latitude * metresPerDegree)
    }
}
