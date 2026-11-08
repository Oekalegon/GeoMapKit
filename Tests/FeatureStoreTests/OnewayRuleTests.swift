import Testing

@testable import FeatureStore

@Suite("OnewayRule")
struct OnewayRuleTests {
    @Test("The tag decides; a motorway is one-way without it; a roundabout is always one-way along its vertices")
    func rule() {
        #expect(OnewayRule.flow(oneway: "yes", highway: "residential", junction: nil) == 1)
        #expect(OnewayRule.flow(oneway: "-1", highway: "residential", junction: nil) == -1)
        #expect(OnewayRule.flow(oneway: "reverse", highway: nil, junction: nil) == -1)
        #expect(OnewayRule.flow(oneway: "no", highway: "motorway", junction: nil) == 0)
        #expect(OnewayRule.flow(oneway: "reversible", highway: "primary", junction: nil) == 0)
        #expect(OnewayRule.flow(oneway: nil, highway: "motorway", junction: nil) == 1)
        #expect(OnewayRule.flow(oneway: nil, highway: "motorway_link", junction: nil) == 1)
        #expect(OnewayRule.flow(oneway: nil, highway: "trunk", junction: nil) == 0)
        #expect(OnewayRule.flow(oneway: nil, highway: nil, junction: nil) == 0)
        #expect(OnewayRule.flow(oneway: nil, highway: "residential", junction: "roundabout") == 1)
        #expect(OnewayRule.flow(oneway: "-1", highway: "residential", junction: "roundabout") == 1)
    }
}
