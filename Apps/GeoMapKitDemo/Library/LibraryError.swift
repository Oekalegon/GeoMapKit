import Foundation

/// Why something in the library did not work, as a sentence for the user.
enum LibraryError: Error, LocalizedError, Equatable {
    case notAMap(String)
    case notAStyle(String, String)
    case noManifest(String)
    case exists(String)
    case missing(String)
    case staleLink(String)
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .notAMap(let name): "\(name) is not a feature store (.gmk) or a folder of blocks."
        case .notAStyle(let name, let reason): "\(name) is not a style: \(reason)"
        case .noManifest(let name): "The folder \(name) has no manifest.json."
        case .exists(let name): "There is already something called \(name)."
        case .missing(let name): "\(name) is not in the library any more."
        case .staleLink(let name): "The folder of \(name) cannot be reached any more; remove the map and add the folder again."
        case .failed(let name, let reason): "\(name): \(reason)"
        }
    }
}
