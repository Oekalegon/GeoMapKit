import FeatureStoreBuilder
import OSMPBF
import Testing

@testable import MapBuilder

/// The weights of the progress of one block, and the table the running blocks report to.
@Suite("Progress of a block")
struct BlockStepTests {
    @Test("The steps follow each other from 0 to 1, the part of a step is clamped, and the weights add up to the whole")
    func steps() {
        let all = BlockStep.allCases
        #expect(all.first?.start == 0)
        #expect(all.map(\.start) == all.map(\.start).sorted())
        #expect(abs(BlockStep.finishing.fraction(part: 1) - 1) < 1e-12)
        for step in all {
            #expect(step.fraction(part: -1) == step.start && step.fraction(part: 7) == step.fraction(part: 1))
            #expect(step.fraction(part: 0.5) > step.start && step.fraction(part: 0.5) < step.fraction(part: 1))
        }
        for (a, b) in zip(all, all.dropFirst()) { #expect(abs(a.fraction(part: 1) - b.start) < 1e-12) }
    }

    @Test("Every pass of the cut and every stage of the build has a step, in the order the work is done")
    func mapping() {
        let passes = AreaCutter.Pass.allCases.map { BlockStep($0).rawValue }
        let stages = BuildStage.allCases.map { BlockStep($0).rawValue }
        #expect(passes == passes.sorted() && stages == stages.sorted())
        #expect((passes.max() ?? 0) < (stages.min() ?? 0) && (stages.max() ?? 0) < BlockStep.finishing.rawValue)
    }

    @Test("The ways of the build are the bulk of the work, as measured")
    func waysDominate() {
        #expect(BlockStep.buildWays.weight / BlockStep.allCases.reduce(0) { $0 + $1.weight } > 0.4)
    }

    @Test("A block's fraction never goes down, is clamped, and leaves the sum when the block is done")
    func table() {
        let fractions = BlockFractions()
        fractions.set(0.4, forBlock: 1)
        fractions.set(0.1, forBlock: 1)
        fractions.set(2, forBlock: 2)
        #expect(fractions.sum == 1.4)
        fractions.remove(block: 2)
        #expect(fractions.sum == 0.4)
        fractions.remove(block: 1)
        #expect(fractions.sum == 0)
    }

    @Test("The blocks report from several threads without losing a value")
    func threads() async {
        let fractions = BlockFractions()
        await withTaskGroup(of: Void.self) { group in
            for block in 0..<8 {
                group.addTask { for step in 1...100 { fractions.set(Double(step) / 100, forBlock: block) } }
            }
        }
        #expect(abs(fractions.sum - 8) < 1e-9)
    }

    @Test("The fraction counts the parts of the running blocks, and the time left uses the work done")
    func progress() {
        let p = BlockProgress(total: 10, finished: 2, running: 2, built: 2, elapsed: .seconds(100), partial: 1.0)
        #expect(abs(p.fraction - 0.3) < 1e-12)
        #expect(BlockProgress(total: 2, finished: 1, running: 1, built: 1, elapsed: .zero, partial: 5).fraction == 1)
        // 3 blocks of work done in 300 s; 7 are left: 700 s.
        #expect(BlockProgress.estimateRemaining(left: 7, doneInRun: 3, elapsed: .seconds(300)) == .seconds(700))
        // Less than one block of work, or nothing left: no estimate.
        #expect(BlockProgress.estimateRemaining(left: 7, doneInRun: 0.9, elapsed: .seconds(30)) == nil)
        #expect(BlockProgress.estimateRemaining(left: 0, doneInRun: 3, elapsed: .seconds(300)) == nil)
    }
}
