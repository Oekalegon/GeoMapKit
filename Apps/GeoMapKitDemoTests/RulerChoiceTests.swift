import MapUI
import Testing

@testable import GeoMapKitDemo

@Suite("Scale ruler choice")
struct RulerChoiceTests {
    @Test("Each choice gives the settings of the package, and every choice has its own name for the picker")
    func settings() {
        #expect(RulerChoice.off.settings.visibility == .hidden)
        #expect(RulerChoice.always.settings.visibility == .always)
        #expect(RulerChoice.afterMoving.settings.visibility == .afterMoving(delay: .seconds(2)))
        #expect(Set(RulerChoice.allCases.map(\.id)).count == 3)
        #expect(RulerChoice(rawValue: "While moving") == .afterMoving)
    }
}
