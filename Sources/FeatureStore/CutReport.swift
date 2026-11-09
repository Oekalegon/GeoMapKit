/// What a cut of a region came to.
public struct CutReport: Sendable, Equatable {
    /// The cells at the storage zoom that were looked at (the cells that touch the area).
    public var cellsExamined: Int
    /// The cells that have at least one feature in the copy.
    public var cellsWritten: Int
    /// The pieces of features written.
    public var featuresWritten: Int
    /// The size of the file in bytes.
    public var fileBytes: Int
}
