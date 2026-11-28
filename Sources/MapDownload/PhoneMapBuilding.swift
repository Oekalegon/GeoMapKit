import Foundation

/// Builds a map for an area on the phone from OpenStreetMap data: the fallback when no ready-made map exists.
public protocol PhoneMapBuilding: Sendable {
    /// Finds the source files the area needs and what they would take, downloading nothing.
    func plan(for area: MapArea) async throws -> PhoneBuildPlan

    /// Downloads what the plan needs and builds the map into a new folder.
    ///
    /// - Parameters:
    ///   - plan: A plan this builder made.
    ///   - area: The area the plan was made for.
    ///   - folder: The folder for the map's blocks and manifest; it is created.
    ///   - progress: Called as the work goes on, from any thread.
    /// - Throws: `CancellationError` when the task is cancelled; the files already downloaded are kept for another try.
    func build(_ plan: PhoneBuildPlan, for area: MapArea, into folder: URL, progress: @escaping @Sendable (MapDownloadProgress) -> Void) async throws
}
