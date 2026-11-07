import MapStyle
import Testing

@testable import MapRender

@Suite("Label placement")
struct LabelPlacerTests {
    private let style = LabelStyle(size: ZoomValue(constant: 10), color: .black, priority: 0)

    /// Every text is 50 × 10 points, whatever the font size.
    private let measure: (String, Double) -> (width: Double, height: Double) = { _, _ in (50, 10) }

    private func candidate(
        _ id: Int64, x: Double, y: Double, radius: Double = 3, priority: Int = 0, text: String? = nil
    ) -> LabelCandidate {
        LabelCandidate(
            objectID: id, text: text ?? "L\(id)", anchor: ScreenPoint(x: x, y: y), symbolRadius: radius, fontSize: 10,
            style: LabelStyle(size: ZoomValue(constant: 10), color: .black, priority: priority))
    }

    private func place(_ candidates: [LabelCandidate]) -> [PlacedLabel] {
        LabelPlacer.place(candidates, viewWidth: 400, viewHeight: 300, measure: measure)
    }

    @Test func pointLabelGoesToTheRightOfTheSymbol() throws {
        let label = try #require(place([candidate(1, x: 100, y: 100)]).first)
        #expect(label.origin.x == 106 && label.origin.y == 95)
    }

    @Test func areaLabelIsCentred() throws {
        let label = try #require(place([candidate(1, x: 100, y: 100, radius: 0)]).first)
        #expect(label.origin == ScreenPoint(x: 75, y: 95))
    }

    @Test func collidingLabelMovesToAnotherPosition() throws {
        // The right-hand label of 2 would overlap the label of 1, so 2 goes to the left of its symbol.
        let labels = place([candidate(1, x: 100, y: 100, priority: 5), candidate(2, x: 60, y: 100)])
        #expect(labels.count == 2)
        let first = try #require(labels.first { $0.text == "L1" })
        let second = try #require(labels.first { $0.text == "L2" })
        #expect(first.origin.x == 106)
        #expect(second.origin.x == 60 - 3 - 3 - 50)
    }

    @Test func higherPriorityWinsWhenNothingFits() {
        // Two area labels on the same spot; an area label has only one position.
        let labels = LabelPlacer.place(
            [candidate(1, x: 30, y: 10, radius: 0, priority: 1), candidate(2, x: 30, y: 10, radius: 0, priority: 9)],
            viewWidth: 60, viewHeight: 20, measure: measure)
        #expect(labels.map(\.text) == ["L2"])
    }

    @Test func labelsOutsideTheViewAreDropped() {
        #expect(place([candidate(1, x: 395, y: 100), candidate(2, x: 100, y: 2)]).count <= 2)
        let edge = LabelPlacer.place([candidate(1, x: 10, y: 10, radius: 0)], viewWidth: 40, viewHeight: 300, measure: measure)
        #expect(edge.isEmpty)
    }

    @Test func symbolsBlockLabelsOfOtherFeatures() {
        // The label of 1 would sit exactly on the symbol of 2.
        let labels = place([candidate(1, x: 100, y: 100, priority: 5), candidate(2, x: 110, y: 100, radius: 6)])
        let first = labels.first { $0.text == "L1" }
        #expect(first != nil && first?.origin.x != 106)
    }

    @Test func oneLabelPerFeature() {
        #expect(place([candidate(1, x: 100, y: 100), candidate(1, x: 300, y: 200)]).count == 1)
    }

    @Test func placementIsDeterministic() {
        var input: [LabelCandidate] = []
        for i in 1...30 {
            let x = Double(i * 11 % 300)
            let y = Double(i * 7 % 200)
            input.append(candidate(Int64(i), x: x, y: y))
        }
        #expect(place(input) == place(input.reversed()))
    }

    @Test func emptyTextBoxIsSkipped() {
        let none = LabelPlacer.place([candidate(1, x: 100, y: 100)], viewWidth: 400, viewHeight: 300) { _, _ in (0, 0) }
        #expect(none.isEmpty)
    }
}
