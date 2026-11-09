import Foundation

/// A style of the user, a JSON file in the library.
struct StyleItem: Identifiable, Hashable {
    /// The name of the file in the library, with its extension: unique, and what the selection is stored as.
    let id: String
    /// What the user sees: the file name without its extension.
    var name: String
    var date: Date
}

/// Which style draws the map: one of the two that the kit has, or a style of the user.
enum StyleChoice: Hashable {
    case standard
    case watch
    case user(String)

    /// How the choice is stored: `standard`, `watch` or `user:<file name>`.
    var storedValue: String {
        switch self {
        case .standard: "standard"
        case .watch: "watch"
        case .user(let file): "user:\(file)"
        }
    }

    init?(storedValue: String) {
        switch storedValue {
        case "standard": self = .standard
        case "watch": self = .watch
        default:
            guard storedValue.hasPrefix("user:") else { return nil }
            self = .user(String(storedValue.dropFirst("user:".count)))
        }
    }
}
