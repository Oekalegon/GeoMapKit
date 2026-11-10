import Foundation
import Testing

@testable import GeoMapKitDemo

/// Two devices changed one style: the newest version wins and every other version is kept as a copy.
@Suite("Style conflicts")
struct StyleConflictRuleTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func aNewerConflictingVersionWinsAndTheCurrentOneIsKept() {
        let plan = StyleConflictRule.plan(current: t0, conflicts: [(id: 0, modified: t0.addingTimeInterval(60))])
        #expect(plan.winner.id == 0)
        #expect(plan.copies.map(\.id) == [nil])
    }

    @Test func anOlderConflictingVersionIsKeptAsACopyAndTheCurrentOneStays() {
        let plan = StyleConflictRule.plan(current: t0, conflicts: [(id: 0, modified: t0.addingTimeInterval(-60)), (id: 1, modified: t0.addingTimeInterval(-10))])
        #expect(plan.winner.id == nil)
        #expect(plan.copies.map(\.id) == [1, 0], "newest copy first")
    }

    @Test func aTieKeepsTheFileAsItIs() {
        #expect(StyleConflictRule.plan(current: t0, conflicts: [(id: 3, modified: t0)]).winner.id == nil)
    }

    @Test func nothingIsLostWhateverTheOrder() {
        let plan = StyleConflictRule.plan(current: t0, conflicts: [(id: 0, modified: t0.addingTimeInterval(5)), (id: 1, modified: t0.addingTimeInterval(9)), (id: 2, modified: t0.addingTimeInterval(1))])
        #expect(plan.winner.id == 1)
        #expect(Set(plan.copies.map(\.id)) == [nil, 0, 2] && plan.copies.count == 3)
    }

    @Test func aCopyIsNamedAfterTheFileAndTheTimeAndIsUnique() {
        let name = StyleConflictRule.copyName(of: "Trail.json", modified: t0, existing: [])
        #expect(name.hasPrefix("Trail (conflict ") && name.hasSuffix(").json"))
        #expect(StyleConflictRule.copyName(of: "Trail.json", modified: t0, existing: [name]) == String(name.dropLast(5)) + " 2.json")
    }
}
