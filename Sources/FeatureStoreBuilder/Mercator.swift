import Foundation

/// Web Mercator maths on 1e-7 degree coordinates.
///
/// Longitude maps linearly to x, so x stays in 1e-7 degrees. Latitude maps to y in
/// radians (the unit circle projection, so the world spans -pi to pi), which is
/// the space in which a straight line on the screen is a straight line.
enum Mercator {
    private static let radiansPerUnit = Double.pi / 180 / 1e7

    /// The projected y of a latitude in 1e-7 degrees.
    static func y(latitude: Double) -> Double {
        log(tan(.pi / 4 + latitude * radiansPerUnit / 2))
    }

    /// The latitude, in 1e-7 degrees, of a projected y.
    static func latitude(y: Double) -> Double {
        (2 * atan(exp(y)) - .pi / 2) / radiansPerUnit
    }

    /// A longitude in 1e-7 degrees as radians, the same scale as `y`.
    static func radians(longitude: Double) -> Double { longitude * radiansPerUnit }
}
