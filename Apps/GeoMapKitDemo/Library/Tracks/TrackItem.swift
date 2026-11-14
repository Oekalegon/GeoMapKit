import Foundation

/// A GPX file in the library of tracks.
struct TrackItem: Identifiable, Hashable {
    /// The name of the file in the library, with its extension: unique, and what the choice of what to show is stored as.
    let id: String
    /// What the user sees: the file name without its extension.
    var name: String
    var bytes: Int64
    var date: Date
}
