import OSMPBF

/// An array of tags as a source for the classifier, compared byte for byte.
struct ClassifierTagArray: ClassifierTags {
    let tags: [OSMTag]

    init(_ tags: [OSMTag]) { self.tags = tags }

    func value(forKey key: String) -> String? {
        tags.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }
}
