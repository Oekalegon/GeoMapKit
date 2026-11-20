import Foundation

/// Why the store could not do what it was asked.
public enum TrackStoreError: Error, Equatable, Sendable, LocalizedError {
    /// The database could not be opened or made, with the message of SQLite.
    case cannotOpen(String)
    /// The database was made by a newer version of the package (its `user_version` is higher than this one knows).
    case newerVersion(found: Int, supported: Int)
    /// SQLite refused a statement, with its message. The change that was being made is rolled back.
    case sqlite(String)
    /// A value in the database cannot be read (the tags of an activity that are not valid), with what it was. The store is not changed.
    case damaged(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let reason): "The database cannot be opened: \(reason)"
        case .newerVersion(let found, let supported): "The database is of version \(found); this app reads up to \(supported)."
        case .sqlite(let message): "The database reported: \(message)"
        case .damaged(let what): "The database is damaged: \(what)."
        }
    }
}
