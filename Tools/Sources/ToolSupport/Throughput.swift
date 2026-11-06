/// File rates for tool output.
public enum Throughput {
    /// Megabytes (10^6 bytes) per second.
    ///
    /// - Parameters:
    ///   - bytes: The amount of data processed.
    ///   - duration: The time it took.
    /// - Returns: The rate, or `nil` if the duration is zero or negative.
    public static func megabytesPerSecond(bytes: Int64, duration: Duration) -> Double? {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        guard seconds > 0 else { return nil }
        return Double(bytes) / 1e6 / seconds
    }
}
