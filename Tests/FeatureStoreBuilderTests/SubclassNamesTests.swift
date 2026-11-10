import FeatureStore
import Testing

@testable import FeatureStoreBuilder

/// The names a style selects by are the values of the rule table.
@Suite("Subclass names")
struct SubclassNamesTests {
    @Test func theNameTableIsTheRuleTable() {
        var fromRules: [FeatureClass: [String: [UInt8]]] = [:]
        for rule in FeatureClassifier.rules {
            for (value, outcome) in rule.outcomes {
                fromRules[outcome.featureClass, default: [:]][value, default: []].append(outcome.subclass)
            }
        }
        for (featureClass, names) in fromRules {
            for (name, numbers) in names {
                #expect(Set(SubclassNames.numbers(of: name, in: featureClass)) == Set(numbers), "\(featureClass) \(name)")
            }
        }
        for (featureClass, names) in SubclassNames.all {
            for name in names.keys { #expect(fromRules[featureClass]?[name] != nil, "\(featureClass) \(name) is not in the rule table") }
        }
    }

    @Test func aRoadHasItsHighwayValueAndABridgeBitIsIgnored() {
        #expect(SubclassNames.name(of: SubclassBits.value(of: 1 | SubclassBits.bridge), in: .roadMajor) == "motorway")
        #expect(SubclassNames.numbers(of: "grass", in: .landcover).count == 2)
        #expect(SubclassNames.numbers(of: "farmland", in: .landcover).count == 1)
        #expect(SubclassNames.numbers(of: "nonsense", in: .roadMajor).isEmpty)
    }
}
