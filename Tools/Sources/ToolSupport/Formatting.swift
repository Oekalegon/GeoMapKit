import Foundation

/// Human-readable numbers for tool output.
public enum Formatting {
    /// A byte count such as `3.5 MB` (decimal units, as file managers show them).
    public static func bytes(_ count: Int64) -> String {
        let units = ["B", "kB", "MB", "GB", "TB"]
        var value = Double(count)
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return unit == 0 ? "\(count) B" : String(format: "%.1f %@", value, units[unit])
    }

    /// A duration in seconds such as `0.23 s`.
    public static func seconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2f s", seconds)
    }

    /// A count with thousands separators, such as `358,095`.
    public static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
