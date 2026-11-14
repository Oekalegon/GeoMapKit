import Foundation

/// A value that an app attaches to an activity as a tag: its sport, where it came from, a name, a rating, any encoded payload.
///
/// The package gives tags no meaning. The app chooses the keys and the values, and filters by them; the package stores and returns them
/// as they are. Anything that is not one of the simple cases goes in `data`, encoded by the app.
public enum TagValue: Sendable, Hashable, Codable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
}
