/// Which copy of the data the builder produces.
public enum BuildProfile: Sendable {
    /// Everything: all classes, all bands, all tags and the relation table. For iOS and macOS.
    case full
    /// The Watch copy: only the classes the fixed Watch profile includes, only the mid and detail bands,
    /// only the `name` tag, and no relation table. Provisional; the corridor cut in the Watch step may refine it.
    case watch
}
