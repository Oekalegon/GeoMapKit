import FeatureStore

/// What the `inspect` command found in a feature store file.
public struct InspectReport: Equatable, Sendable {
    /// One row of a tag count.
    public struct TagCount: Equatable, Sendable {
        /// The tag as `key=value`, or just `key` in the key table.
        public let tag: String
        /// How many objects carry it.
        public let objects: Int

        /// Creates a row.
        public init(tag: String, objects: Int) {
            self.tag = tag
            self.objects = objects
        }
    }

    /// The file name.
    public let fileName: String
    /// The number of objects (a way cut at cell borders counts once) per class name, in class order.
    public let objectsByClass: [(name: String, objects: Int)]
    /// The class whose tags were counted, if one was asked for.
    public let inspectedClass: String?
    /// The most common `key=value` tags in that class.
    public let topTags: [TagCount]
    /// The most common keys in that class.
    public let topKeys: [TagCount]

    /// Creates a report.
    public init(
        fileName: String, objectsByClass: [(name: String, objects: Int)], inspectedClass: String?, topTags: [TagCount],
        topKeys: [TagCount]
    ) {
        self.fileName = fileName
        self.objectsByClass = objectsByClass
        self.inspectedClass = inspectedClass
        self.topTags = topTags
        self.topKeys = topKeys
    }

    public static func == (lhs: InspectReport, rhs: InspectReport) -> Bool {
        lhs.fileName == rhs.fileName && lhs.inspectedClass == rhs.inspectedClass && lhs.topTags == rhs.topTags
            && lhs.topKeys == rhs.topKeys && lhs.objectsByClass.map(\.name) == rhs.objectsByClass.map(\.name)
            && lhs.objectsByClass.map(\.objects) == rhs.objectsByClass.map(\.objects)
    }
}
