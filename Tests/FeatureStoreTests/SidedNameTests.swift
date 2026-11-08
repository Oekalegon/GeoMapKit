import Testing

@testable import FeatureStore

/// The name of a border, with a region on each side.
@Suite("Sided names")
struct SidedNameTests {
    @Test("The text form has the left name, a line feed and the right name, and reads back")
    func roundTrip() throws {
        let name = SidedName(left: "Norge", right: "Sverige")
        #expect(name.text == "Norge\nSverige")
        #expect(SidedName(text: name.text) == name)
    }

    @Test("A side can be empty, for a region that is not in the data")
    func emptySide() throws {
        #expect(SidedName(text: "Norge\n") == SidedName(left: "Norge", right: ""))
        #expect(SidedName(text: "\nSverige") == SidedName(left: "", right: "Sverige"))
    }

    @Test("A text with no separator, or with more than one, is no sided name")
    func notSided() {
        #expect(SidedName(text: "Norge – Sverige") == nil)
        #expect(SidedName(text: "") == nil)
        #expect(SidedName(text: "a\nb\nc") == nil)
    }
}
