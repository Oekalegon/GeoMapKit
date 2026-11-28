/// Where a download or build is, for a progress bar.
public struct MapDownloadProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Downloading the map file, or the OpenStreetMap data it is built from.
        case downloading
        /// Building the map from the data, on the phone.
        case building
    }

    public var phase: Phase
    /// How far the phase is, 0 to 1, or `nil` when it isn't known.
    public var fraction: Double?

    public init(phase: Phase, fraction: Double?) {
        self.phase = phase
        self.fraction = fraction
    }
}
