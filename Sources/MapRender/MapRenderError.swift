/// Why a map could not be put together.
public enum MapRenderError: Error, Equatable, Sendable {
    /// The store file holds no geometry band at all.
    case noBands
}
