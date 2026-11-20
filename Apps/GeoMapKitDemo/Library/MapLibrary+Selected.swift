import Foundation

extension MapLibrary {
    /// The map that is selected, opened; `nil` when none is selected.
    func openSelected() throws -> OpenedMap? {
        guard let id = selectedMapID, let item = maps.first(where: { $0.id == id }) else { return nil }
        return try open(item)
    }
}
