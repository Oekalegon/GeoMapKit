import Foundation
import GeoCore
import Testing
import Tracks

@testable import TrackImport

@Suite("Category policy")
struct CategoryPolicyTests {
    private func activity(_ tags: [String: TagValue]) throws -> ActivityTrack {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<5).map { TrackPoint(coordinate: Coordinate(latitude: 60, longitude: 10 + Double($0) * 0.0001), time: start.addingTimeInterval(Double($0) * 4)) }
        return try ActivityTrack(points: points, tags: tags)
    }

    @Test("The text of the name decides the category, and anything else is the default")
    func category() throws {
        let policy = CategoryPolicy()
        #expect(policy.category(for: try activity(["gpx.name": .string("OL Epe")])) == "orienteering")
        #expect(policy.category(for: try activity(["gpx.name": .string("Col de la Madeleine")])) == "run")
        #expect(policy.category(for: try activity([:])) == "run")
        #expect(policy.category(for: try activity(["gpx.name": .integer(3)])) == "run")
        #expect(policy.suggestion(for: try activity(["gpx.name": .string("NK")]))?.keyword.text == "NK")
    }

    @Test("The app chooses the tags, the default and the categories that are raw; without a suggester nothing is suggested")
    func appChoices() throws {
        let policy = CategoryPolicy(defaultCategory: "ride", suggester: nil, textTags: ["title"], rawCategories: ["ski"])
        #expect(policy.category(for: try activity(["title": .string("OL")])) == "ride")
        #expect(policy.mode(of: "ski") == .raw && policy.mode(of: "orienteering") == .matched)
        let custom = CategoryPolicy(textTags: ["title"])
        #expect(custom.category(for: try activity(["title": .string("OL")])) == "orienteering")
        #expect(CategoryPolicy().mode(of: "orienteering") == .raw)
    }
}
