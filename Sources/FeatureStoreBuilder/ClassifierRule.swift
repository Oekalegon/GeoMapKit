import FeatureStore

/// What a tag value maps to.
struct ClassifierOutcome: Sendable {
    let featureClass: FeatureClass
    let subclass: UInt8
    let band: ZoomBand
    let watch: Bool
}

/// One entry of the ordered rule table: a key and the values that match.
///
/// With `anyValue` set, every value except empty and `no` matches.
struct ClassifierRule: Sendable {
    let key: String
    let outcomes: [String: ClassifierOutcome]
    let anyValue: ClassifierOutcome?

    init(_ key: String, _ outcomes: [String: ClassifierOutcome]) {
        self.key = key
        self.outcomes = outcomes
        self.anyValue = nil
    }

    init(_ key: String, any: ClassifierOutcome) {
        self.key = key
        self.outcomes = [:]
        self.anyValue = any
    }

    func match(_ value: String) -> ClassifierOutcome? {
        if let outcome = outcomes[value] { return outcome }
        if let anyValue, !value.isEmpty, value != "no" { return anyValue }
        return nil
    }
}
