/// Builds maps from OSM source files: blocks, levels and open sea.
///
/// This is the build pipeline that the `geomapkit` command-line tool and the apps share (question 51 and the step "maps built inside
/// the apps"). It holds no platform assumption: the area, the number of parallel jobs and the memory use come from the request, so a
/// later iPhone policy only changes the request, not the pipeline. The functions are in the extensions of this type:
/// ``buildRegion(_:catalog:downloader:progress:onProgress:)``, ``buildLevels(_:progress:)`` and
/// ``fillOpenSea(folder:cacheDirectory:catalog:downloader:)``.
public enum MapBuilder {}

extension MapBuilder {
    /// The user agent for the region index when a caller names none. An app or tool should pass its own.
    public static let defaultUserAgent = "GeoMapKit"
}
