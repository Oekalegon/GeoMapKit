#if os(macOS)
import Foundation
import Observation

/// Owns the map build of the app, so that it goes on when the picker is closed and the user works with maps meanwhile
/// (question 63, step 3d). There is one build at a time.
@MainActor
@Observable
final class MapBuildHost {
    /// The build, once the picker was opened for the first time.
    private(set) var model: MapBuildModel?
    /// Whether the picker is shown.
    var showsPicker = false
    /// The reason the picker could not be opened.
    var problem: String?

    private let make: () throws -> MapBuildModel

    /// Creates the host.
    ///
    /// - Parameter make: Makes the build model: the folders, the catalog and the entry in the library. It is called once, when first needed.
    init(make: @escaping () throws -> MapBuildModel) { self.make = make }

    /// Whether a run is going or has ended without being dismissed. Then no new run is started: the status bar shows it.
    var isBusy: Bool { model.map { $0.stage != .idle } ?? false }

    /// Whether a run is going.
    var isRunning: Bool { model?.isRunning ?? false }

    /// Opens the picker, unless a run is going or its result is still there.
    func openPicker() {
        guard !isBusy else { return }
        if model == nil {
            do { model = try make() } catch {
                problem = "The folder for the source files cannot be used: \(error)"
                return
            }
        }
        showsPicker = true
    }
}
#endif
