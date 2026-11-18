import Foundation

/// What `merge-maps` is asked to do: put the blocks of several maps in one map.
public struct MapMergeRequest: Sendable {
    /// The folders of the maps to merge: each holds `manifest.json` and its block files. At least two, or one and the output as another.
    public var inputs: [URL]
    /// The folder of the merged map. If it is one of the inputs, the others are added to that map in place: its blocks and levels stay, and
    /// only what changes is written. Otherwise it must not exist yet, or be empty.
    public var output: URL

    /// Creates a request.
    public init(inputs: [URL], output: URL) {
        self.inputs = inputs
        self.output = output
    }
}
