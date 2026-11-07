import OSMPBF

/// A source of tag values for the classifier.
public protocol ClassifierTags {
    /// The value of a tag, or `nil` if the object has no such tag.
    func value(forKey key: String) -> String?
}

extension Dictionary: ClassifierTags where Key == String, Value == String {
    public func value(forKey key: String) -> String? { self[key] }
}

extension TagList: ClassifierTags {
    public func value(forKey key: String) -> String? { self[key] }
}
