import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// How the ways of a road become one line of a level, and how a road is judged as a whole.
@Suite("Level chain merger")
struct LevelChainMergerTests {
    private func pt(_ lon: Int32, _ lat: Int32) -> PackedPoint { PackedPoint(longitude: lon, latitude: lat) }

    private func chain(
        _ id: Int64, _ points: [PackedPoint], classID: UInt8 = FeatureClass.roadMajor.rawValue, subclass: UInt8 = 3, name: String? = nil
    ) -> LevelChain {
        LevelChain(
            key: LevelKey(classID: classID, type: 1, id: id),
            attributes: LevelAttributes(subclass: subclass, name: name, incomplete: false, population: nil), line: points)
    }

    @Test func waysThatContinueEachOtherAreOneLineWhateverTheirDirection() {
        let a = pt(0, 0), b = pt(10, 0), c = pt(20, 0), d = pt(30, 0)
        // The second way runs the other way round, the third starts where the first one ends.
        let merged = LevelChainMerger.merge([chain(1, [a, b]), chain(2, [c, b]), chain(3, [c, d])])
        #expect(merged.count == 1)
        #expect(merged[0].key.id == 1)
        #expect(merged[0].line == [a, b, c, d])
    }

    @Test func aJunctionJoinsNothing() {
        let hub = pt(10, 0)
        let merged = LevelChainMerger.merge([chain(1, [pt(0, 0), hub]), chain(2, [hub, pt(20, 0)]), chain(3, [hub, pt(10, 10)])])
        #expect(merged.count == 3)
    }

    @Test func aNameAGradeOrABridgeKeepsWaysApart() {
        let a = pt(0, 0), b = pt(10, 0), c = pt(20, 0)
        #expect(LevelChainMerger.merge([chain(1, [a, b], name: "A1"), chain(2, [b, c], name: "A2")]).count == 2)
        #expect(LevelChainMerger.merge([chain(1, [a, b], subclass: 3), chain(2, [b, c], subclass: 4)]).count == 2)
        #expect(LevelChainMerger.merge([chain(1, [a, b], subclass: 3), chain(2, [b, c], subclass: 3 | SubclassBits.bridge)]).count == 2)
        #expect(LevelChainMerger.merge([chain(1, [a, b], classID: 3), chain(2, [b, c], classID: 5)]).count == 2)
    }

    @Test func aLoopOfWaysIsKeptAndNothingIsLost() {
        let a = pt(0, 0), b = pt(10, 0), c = pt(10, 10)
        let merged = LevelChainMerger.merge([chain(1, [a, b]), chain(2, [b, c]), chain(3, [c, a])])
        #expect(merged.count == 1)
        #expect(merged[0].line.count == 4 && merged[0].line.first == merged[0].line.last)
    }

    @Test func aWayThatClosesOnItselfJoinsNothingAtItsOwnEnd() {
        let a = pt(0, 0), b = pt(10, 0), c = pt(10, 10)
        let merged = LevelChainMerger.merge([chain(1, [a, b, c, a])])
        #expect(merged.count == 1 && merged[0].line == [a, b, c, a])
    }

    @Test func everyPointOfEveryWayIsStillThere() {
        var chains: [LevelChain] = []
        for index in 0..<50 { chains.append(chain(Int64(index), [pt(Int32(index) * 10, 0), pt(Int32(index) * 10 + 10, 0)])) }
        let merged = LevelChainMerger.merge(chains.shuffled())
        #expect(merged.count == 1)
        #expect(merged[0].line.count == 51)
    }

    @Test func aNetworkIsJudgedByItsExtentNotByTheExtentOfEachWay() {
        let spec = try! LevelSpec(topZoom: 8, classes: [FeatureClass.roadMajor.rawValue])
        // Two ways of 1,000 units each that meet, and a stub that is on its own.
        let a = pt(0, 0), b = pt(1_000, 0), c = pt(2_000, 0), far = pt(900_000, 0)
        let extents = LevelChainMerger.networkExtents(of: [
            (FeatureClass.roadMajor.rawValue, [a, b]), (FeatureClass.roadMajor.rawValue, [b, c]),
            (FeatureClass.roadMajor.rawValue, [far, pt(900_100, 0)]),
        ])
        #expect(extents[0] == extents[1], "ways that meet are one network")
        #expect(extents[0] > 1.9 * extents[2], "the network is twice as long as the stub")
        #expect(spec.minimumExtent > 0)
    }

    @Test func waysOfAnotherClassAreAnotherNetwork() {
        let extents = LevelChainMerger.networkExtents(of: [
            (FeatureClass.roadMajor.rawValue, [pt(0, 0), pt(1_000, 0)]), (FeatureClass.railway.rawValue, [pt(1_000, 0), pt(500_000, 0)]),
        ])
        #expect(extents[0] < extents[1] / 100)
    }
}

@Suite("Level spec roads")
struct LevelSpecRoadTests {
    private func held(_ topZoom: Int, _ value: UInt8, extra: UInt8 = 0) -> Bool {
        let spec = try! LevelSpec(topZoom: topZoom, classes: [FeatureClass.roadMajor.rawValue, FeatureClass.railway.rawValue])
        return spec.holds(classID: FeatureClass.roadMajor.rawValue, subclass: value | extra)
    }

    @Test func coarserLevelsHoldFewerRoads() {
        // 1 motorway, 2 trunk, 3 primary, 4 secondary, 5 tertiary, 9 to 13 the links.
        #expect([1, 2, 3, 4, 5, 9, 13].allSatisfy { held(9, $0) })
        #expect([1, 2, 3, 4].allSatisfy { held(8, $0) } && ![5, 9, 13].contains { held(8, $0) })
        #expect([1, 2, 3].allSatisfy { held(7, $0) && held(6, $0) } && !held(7, 4) && !held(6, 4))
        #expect([1, 2].allSatisfy { held(5, $0) && held(3, $0) } && !held(5, 3) && !held(3, 3))
        #expect(held(3, 0), "a road with no known grade is left alone")
    }

    @Test func theBridgeAndTunnelBitsDoNotChangeTheGrade() {
        #expect(held(8, 3, extra: SubclassBits.bridge))
        #expect(!held(8, 5, extra: SubclassBits.tunnel))
    }

    @Test func otherClassesAreNotLimitedAndOnlyTheLevelsClassesAreHeld() {
        let spec = try! LevelSpec(topZoom: 4, classes: [FeatureClass.railway.rawValue])
        #expect(spec.holds(classID: FeatureClass.railway.rawValue, subclass: 4))
        #expect(!spec.holds(classID: FeatureClass.roadMajor.rawValue, subclass: 1))
    }
}
