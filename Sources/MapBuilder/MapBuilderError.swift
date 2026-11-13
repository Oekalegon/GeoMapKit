/// An error of the map build pipeline, with a message that can be shown to the user (the command-line tools print it as it is).
public struct MapBuilderError: Error, CustomStringConvertible, Equatable {
    /// The message for the user.
    public let description: String

    /// Makes an error with a message for the user.
    public init(_ description: String) {
        self.description = description
    }
}
