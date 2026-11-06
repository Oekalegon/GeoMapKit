#if canImport(CoreLocation)
import CoreLocation

/// Conversions to and from CoreLocation, for apps that use MapKit or CoreLocation.
///
/// `GeoCore` keeps its own ``Coordinate`` so the core stays free of Apple
/// frameworks; this file compiles away where CoreLocation is unavailable.
extension Coordinate {
    /// Creates a coordinate from a CoreLocation coordinate.
    ///
    /// - Parameter coordinate: The CoreLocation coordinate, in degrees. Not validated.
    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The same position as a CoreLocation coordinate.
    public var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
#endif
