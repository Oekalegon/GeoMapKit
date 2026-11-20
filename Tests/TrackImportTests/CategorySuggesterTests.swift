import Foundation
import Testing

@testable import TrackImport

@Suite("Category suggestions")
struct CategorySuggesterTests {
    private let suggester = CategorySuggester()

    @Test("Orienteering is suggested from OL, NK and the words for it, with case and accents ignored")
    func orienteering() {
        for text in ["OL training", "Sprint-OL Haarlem", "ol", "NK 2019", "Orienteering at Epe", "Oriëntatieloop", "orientierungslauf", "Orientering Halden"] {
            #expect(suggester.suggestion(for: [text])?.category == "orienteering", "\(text)")
        }
    }

    @Test("A word that only contains the letters is not a hit: Col de la Madeleine, Oriental, Kolen, Monk")
    func boundaries() {
        for text in ["Col de la Madeleine", "Oriental breakfast run", "Kolen", "Monk", "Morning run", "", "   "] {
            #expect(suggester.suggestion(for: [text]) == nil, "\(text)")
        }
    }

    @Test("The keyword is named, so the user can be shown why; the name and the description are both read")
    func keywordAndTexts() {
        let found = suggester.suggestion(for: ["Morning run", "Club event, NK middle distance"])
        #expect(found == CategorySuggestion(category: "orienteering", keyword: CategoryKeyword("NK", accentsMatter: true)))
    }

    @Test("The first rule that has a keyword wins")
    func order() {
        let race = CategoryRule(category: "race", keywords: [CategoryKeyword("NK")])
        #expect(CategorySuggester(rules: [race, .orienteering]).suggestion(for: ["NK OL"])?.category == "race")
        #expect(CategorySuggester(rules: [.orienteering, race]).suggestion(for: ["NK OL"])?.category == "orienteering")
    }

    @Test("An empty keyword matches nothing")
    func emptyKeyword() {
        let rule = CategoryRule(category: "x", keywords: [CategoryKeyword("", .prefix), CategoryKeyword("")])
        #expect(CategorySuggester(rules: [rule]).suggestion(for: ["anything"]) == nil)
    }

    @Test("OL needs its own accents: the Swedish öl is beer, the Norwegian øl too, and OL and ol are the same word")
    func accents() {
        for text in ["Öl", "ÖL med vänner", "øl-løp"] { #expect(suggester.suggestion(for: [text]) == nil, "\(text)") }
        #expect(suggester.suggestion(for: ["ol"])?.category == "orienteering")
        // A longer keyword still ignores accents.
        #expect(suggester.suggestion(for: ["Orïenteering"])?.category == "orienteering")
    }
}
