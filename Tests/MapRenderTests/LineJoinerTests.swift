import FeatureStore
import Testing

@testable import MapRender

@Suite("Line joining")
struct LineJoinerTests {
    private func piece(_ coordinates: [(Int32, Int32)], before: Bool, after: Bool, offset: UInt32) -> LinePiece {
        LinePiece(
            points: coordinates.map { PackedPoint(longitude: $0.0, latitude: $0.1) }, continuesBefore: before,
            continuesAfter: after, offset: offset)
    }

    @Test func joinsPiecesThatMeetAtTheBorder() {
        let a = piece([(0, 0), (100, 0)], before: false, after: true, offset: 0)
        let b = piece([(100, 0), (200, 50)], before: true, after: false, offset: 10_000)
        #expect(LineJoiner.join([b, a]).map(\.count) == [3])
    }

    @Test func joinsAcrossRoundingOfTheClipPoint() {
        let a = piece([(0, 0), (100, 0)], before: false, after: true, offset: 0)
        let b = piece([(102, -2), (200, 50)], before: true, after: false, offset: 10_000)
        #expect(LineJoiner.join([a, b]).count == 1)
    }

    @Test func keepsPiecesApartWhenFlagsSayThereIsNoContinuation() {
        let a = piece([(0, 0), (100, 0)], before: false, after: false, offset: 0)
        let b = piece([(100, 0), (200, 50)], before: false, after: false, offset: 10_000)
        #expect(LineJoiner.join([a, b]).count == 2)
    }

    @Test func keepsPiecesApartWhenTheEndsAreFarApart() {
        let a = piece([(0, 0), (100, 0)], before: false, after: true, offset: 0)
        let b = piece([(5_000, 0), (6_000, 0)], before: true, after: false, offset: 10_000)
        #expect(LineJoiner.join([a, b]).count == 2)
    }

    @Test func joinsAChainOfThree() {
        let a = piece([(0, 0), (100, 0)], before: false, after: true, offset: 0)
        let b = piece([(100, 0), (200, 0)], before: true, after: true, offset: 100)
        let c = piece([(200, 0), (300, 0)], before: true, after: false, offset: 200)
        let joined = LineJoiner.join([c, a, b])
        #expect(joined.count == 1 && joined[0].count == 4)
    }

    @Test func aLineThatLeavesAndReentersStaysTwoLines() {
        // Piece 2 starts where the line re-entered the cell; it continues before, but nothing ends there.
        let a = piece([(0, 0), (100, 0)], before: false, after: true, offset: 0)
        let b = piece([(900, 0), (1_000, 0)], before: true, after: false, offset: 5_000)
        #expect(LineJoiner.join([a, b]).count == 2)
    }

    @Test func dropsDegeneratePieces() {
        #expect(LineJoiner.join([piece([(0, 0)], before: false, after: false, offset: 0)]).isEmpty)
        #expect(LineJoiner.join([]).isEmpty)
    }
}
