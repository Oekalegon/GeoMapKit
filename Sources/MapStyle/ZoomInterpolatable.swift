/// A style value that can be blended between two zoom stops.
public protocol ZoomInterpolatable: Sendable {
    /// Returns the value `fraction` of the way from `self` to `other`.
    ///
    /// - Parameter fraction: 0 gives `self`, 1 gives `other`. The caller keeps it in 0...1.
    func interpolated(to other: Self, fraction: Double) -> Self
}

extension Double: ZoomInterpolatable {
    public func interpolated(to other: Double, fraction: Double) -> Double {
        self + (other - self) * fraction
    }
}
