import Testing

@testable import MapUI

/// A sleep that waits until the test lets it go, so that no real time passes.
private actor Sleeps {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var started = 0

    func sleep() async {
        started += 1
        await withCheckedContinuation { waiting.append($0) }
    }

    func release(_ index: Int) { waiting[index].resume() }

    func waitUntilStarted(_ count: Int) async {
        while started < count { await Task.yield() }
    }
}

@MainActor
@Suite("Scale ruler presenter")
struct ScaleRulerPresenterTests {
    private func presenter(_ sleeps: Sleeps) -> ScaleRulerPresenter {
        ScaleRulerPresenter(sleep: { _ in await sleeps.sleep() })
    }

    @Test("A change shows the ruler, and it goes away when the delay is over")
    func showsAndHides() async {
        let sleeps = Sleeps()
        let presenter = presenter(sleeps)
        #expect(!presenter.isShown)
        presenter.changed(visibility: .afterMoving(), moving: false)
        #expect(presenter.isShown)
        await sleeps.waitUntilStarted(1)
        await sleeps.release(0)
        await presenter.settled()
        #expect(!presenter.isShown)
    }

    @Test("During a gesture nothing is scheduled, and the end of it starts the wait")
    func gesture() async {
        let sleeps = Sleeps()
        let presenter = presenter(sleeps)
        for _ in 0..<50 { presenter.changed(visibility: .afterMoving(), moving: true) }
        #expect(presenter.isShown)
        for _ in 0..<20 { await Task.yield() }
        #expect(await sleeps.started == 0, "no task for the changes of a gesture")
        presenter.changed(visibility: .afterMoving(), moving: false)
        await sleeps.waitUntilStarted(1)
        await sleeps.release(0)
        await presenter.settled()
        #expect(!presenter.isShown)
    }

    @Test("A new change cancels the wait: the ruler goes away only after the last change")
    func restarts() async {
        let sleeps = Sleeps()
        let presenter = presenter(sleeps)
        presenter.changed(visibility: .afterMoving(), moving: false)
        await sleeps.waitUntilStarted(1)
        presenter.changed(visibility: .afterMoving(), moving: false)
        await sleeps.waitUntilStarted(2)
        // The first wait is over, but it was cancelled: the ruler stays.
        await sleeps.release(0)
        for _ in 0..<20 { await Task.yield() }
        #expect(presenter.isShown)
        await sleeps.release(1)
        await presenter.settled()
        #expect(!presenter.isShown)
    }

    @Test("A gesture that begins during the wait keeps the ruler")
    func gestureDuringWait() async {
        let sleeps = Sleeps()
        let presenter = presenter(sleeps)
        presenter.changed(visibility: .afterMoving(), moving: false)
        await sleeps.waitUntilStarted(1)
        presenter.changed(visibility: .afterMoving(), moving: true)
        await sleeps.release(0)
        for _ in 0..<20 { await Task.yield() }
        #expect(presenter.isShown)
    }

    @Test("Other visibilities schedule nothing and stop a wait; cancelling stops it too")
    func others() async {
        let sleeps = Sleeps()
        let presenter = presenter(sleeps)
        presenter.changed(visibility: .always, moving: false)
        presenter.changed(visibility: .hidden, moving: true)
        for _ in 0..<20 { await Task.yield() }
        #expect(await sleeps.started == 0 && !presenter.isShown)
        presenter.changed(visibility: .afterMoving(), moving: false)
        await sleeps.waitUntilStarted(1)
        presenter.cancel()
        await sleeps.release(0)
        for _ in 0..<20 { await Task.yield() }
        #expect(presenter.isShown, "a cancelled wait does not hide the ruler")
    }
}
