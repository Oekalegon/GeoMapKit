/// The `--profile` option of the `build` command.
public enum ProfileArgument: String, Equatable, CaseIterable {
    /// Everything, for iOS and macOS.
    case full
    /// The reduced copy for the Watch.
    case watch

    /// Parses the value of `--profile`; no value means `full`.
    ///
    /// - Parameter value: The value of `--profile`, if given.
    /// - Throws: ``ToolError`` for any other value.
    public static func parse(_ value: String?) throws -> ProfileArgument {
        guard let value else { return .full }
        guard let profile = ProfileArgument(rawValue: value) else {
            throw ToolError("--profile expects full or watch, not '\(value)'")
        }
        return profile
    }
}
