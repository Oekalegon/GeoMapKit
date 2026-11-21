import Observation

/// Decides when a scale ruler that shows after moving is on screen: it appears with a change of the map and goes away a delay after the
/// last one.
///
/// While a gesture is going on the ruler only stays shown and nothing is scheduled; the end of the gesture starts the one wait. A change that
/// no gesture made (the app sets the zoom) starts the wait at once. A new change cancels the wait that is going on, so the ruler goes
/// away only after the last change. There is no repeating timer: one sleeping task at most.
@MainActor
@Observable
final class ScaleRulerPresenter {
    /// Whether a ruler that shows after moving is shown now. It does not matter for the other visibilities.
    private(set) var isShown = false

    @ObservationIgnored private var hide: Task<Void, Never>?
    @ObservationIgnored private var moving = false
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    /// Creates a presenter.
    ///
    /// - Parameter sleep: Waits for a time; tests give their own, so that no real time passes.
    init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// The map changed, or a gesture began or ended.
    ///
    /// - Parameters:
    ///   - visibility: The setting. Other than ``ScaleRulerVisibility/afterMoving(delay:)`` it cancels what is going on and does nothing else.
    ///   - moving: Whether a gesture is going on now.
    func changed(visibility: ScaleRulerVisibility, moving: Bool) {
        hide?.cancel()
        hide = nil
        self.moving = moving
        guard let delay = visibility.delay else {
            isShown = false
            return
        }
        if !isShown { isShown = true }
        guard !moving else { return }
        hide = Task { [sleep] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            isShown = visibility.isShown(moving: self.moving, idleFor: delay)
        }
    }

    /// Stops the wait that is going on, when the view goes away.
    func cancel() {
        hide?.cancel()
        hide = nil
    }

    /// Waits until the wait that is going on is over (for tests).
    func settled() async { await hide?.value }
}
