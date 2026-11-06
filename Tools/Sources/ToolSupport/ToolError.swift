/// An error shown to the user of a command-line tool.
public struct ToolError: Error, CustomStringConvertible, Equatable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
