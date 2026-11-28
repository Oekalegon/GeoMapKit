import Foundation
import Regions

/// What a download of a map would take and where it comes from shown before it starts.
public struct MapDownloadPlan: Equatable, Sendable {
    public init(area: MapArea, source: Source) {
        self.area = area
        self.source = source
    }

    public enum Source: Equatable, Sendable {
        /// A ready-made map file on a server: small, quick.
        case hosted(HostedMap)
        /// Built on this phone from OpenStreetMap region files.
        case phoneBuild(PhoneBuildPlan)
    }

    public let area: MapArea
    public let source: Source

    /// The bytes to download, or `nil` if not known.
    public var downloadBytes: Int64? {
        switch source {
        case .hosted(let map): map.bytes
        case .phoneBuild(let plan): plan.downloadBytes
        }
    }

    public var availableBytes: Int64? {
        if case .phoneBuild(let plan) = source { return plan.availableBytes }
        return nil
    }

    /// Whether the download fits in the free space, with a margin (a built map and its sources are held at once).
    public var fits: Bool {
        guard let needed = downloadBytes, let available = availableBytes else { return true }
        return available >= needed + SourceManager.spareBytes
    }
}
