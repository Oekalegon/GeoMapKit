import FeatureStore
import Testing

@testable import FeatureStoreBuilder

/// The Watch profile of the cutter and the Watch flags of the classifier must name the same classes.
@Suite("WatchProfile")
struct WatchProfileTests {
    @Test func theClassesOfTheCutterAreTheClassesWithAWatchRule() {
        var watch: Set<FeatureClass> = []
        for rule in FeatureClassifier.rules {
            for outcome in Array(rule.outcomes.values) + [rule.anyValue].compactMap({ $0 }) where outcome.watch {
                watch.insert(outcome.featureClass)
            }
        }
        #expect(WatchProfile.standard.classes == watch)
    }
}
