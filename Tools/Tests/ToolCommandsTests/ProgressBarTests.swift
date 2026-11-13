import Foundation
import MapBuilder
import Testing
@testable import ToolCommands

@Suite("Progress bars")
struct ProgressBarTests {
    @Test("The estimate waits for four built blocks and uses wall-clock pace")
    func estimate() {
        #expect(BlockProgress.estimateRemaining(left: 100, finishedInRun: 3, elapsed: .seconds(300)) == nil)
        #expect(BlockProgress.estimateRemaining(left: 0, finishedInRun: 10, elapsed: .seconds(300)) == nil)
        // 8 blocks in 400 s is 50 s each; 20 are left.
        #expect(BlockProgress.estimateRemaining(left: 20, finishedInRun: 8, elapsed: .seconds(400)) == .seconds(1000))
    }

    @Test("The bar gets narrower for a narrow terminal and is left out when there is no room")
    func narrow() {
        let p = BlockProgress(total: 163, finished: 57, running: 4, built: 40, elapsed: .seconds(3000), remaining: .seconds(4350))
        let full = ProgressBar.line(for: p)
        let fitted = ProgressBar.line(for: p, terminalWidth: full.count - 8)
        #expect(fitted.count < full.count && fitted.count <= full.count - 8 - 1 && fitted.contains("█"))
        #expect(!ProgressBar.line(for: p, terminalWidth: 10).contains("░"))
        #expect(ProgressBar.line(for: p, terminalWidth: 200) == full)
        let d = ProgressBar.downloadLine(id: "mecklenburg-vorpommern", bytes: 5, total: 10, terminalWidth: 50)
        #expect(!d.contains("░") || d.count <= 49)
    }

    @Test("A run without blocks is complete")
    func empty() {
        #expect(BlockProgress(total: 0, finished: 0, running: 0, built: 0, elapsed: .zero).fraction == 1)
    }

    @Test("The line shows count, bar, share, running blocks and time left")
    func line() {
        let p = BlockProgress(total: 163, finished: 57, running: 4, built: 40, elapsed: .seconds(3000), remaining: .seconds(4350))
        let text = ProgressBar.line(for: p, barWidth: 10)
        #expect(text == "[ 57/163] ███░░░░░░░  34 %  4 running  1:12:30 left")
        let done = BlockProgress(total: 5, finished: 5, running: 0, built: 5, elapsed: .seconds(1))
        #expect(ProgressBar.line(for: done, barWidth: 4) == "[5/5] ████ 100 %")
    }

    @Test("Durations are h:mm:ss or m:ss")
    func clock() {
        #expect(ProgressBar.clock(.seconds(59)) == "0:59")
        #expect(ProgressBar.clock(.seconds(3725)) == "1:02:05")
    }

    @Test("The download line shows the share and the sizes, and survives a bad total")
    func download() {
        #expect(ProgressBar.downloadLine(id: "finland", bytes: 250_000_000, total: 1_000_000_000, barWidth: 4)
            == "finland  █░░░  25 %  250.0 MB of 1.0 GB")
        #expect(ProgressBar.downloadLine(id: "x", bytes: 5, total: 0, barWidth: 2).contains("  0 %"))
        #expect(ProgressBar.downloadLine(id: "x", bytes: 9, total: 3, barWidth: 2).contains("100 %"))
    }
}
