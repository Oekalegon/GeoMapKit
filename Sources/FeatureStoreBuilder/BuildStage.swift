/// A stage of ``FeatureStoreBuilder/build(from:writing:progress:)``, reported to its `progress` closure when it starts and, in the stage
/// that takes most of the time, while it runs.
public enum BuildStage: Int, CaseIterable, Sendable {
    /// Preparing the sea of the cells.
    case sea
    /// Storing the relations (areas, borders, routes).
    case relations
    /// Storing the ways: about four fifths of the time of a build (measured on a block of Franche-Comté: 15.6 s of 19.4 s).
    case ways
    /// Storing the nodes.
    case nodes
    /// Storing the sea and writing the file data.
    case writing
}
