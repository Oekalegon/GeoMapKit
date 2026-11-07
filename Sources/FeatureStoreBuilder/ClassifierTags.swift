import OSMPBF

/// A source of tag values for the classifier.
public protocol ClassifierTags {
    /// The value of a tag, or `nil` if the object has no such tag.
    func value(forKey key: String) -> String?
}

/// A plain dictionary of tags, for tests and callers that already hold one.
///
/// Keys are compared with Swift `String` equality, which is fine for the ASCII keys the classifier asks for.
extension Dictionary: ClassifierTags where Key == String, Value == String {
    public func value(forKey key: String) -> String? { self[key] }
}

/// Tags read straight from an `OSMExtract` without building a dictionary.
extension TagList: ClassifierTags {
    public func value(forKey key: String) -> String? { self[key] }
}
