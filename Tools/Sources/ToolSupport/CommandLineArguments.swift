/// Positional arguments and `--name value` options from a command line.
///
/// Deliberately small: the tools need a few options, not a framework.
public struct CommandLineArguments: Equatable {
    /// Arguments that are not options, in order.
    public private(set) var positional: [String] = []

    private var options: [String: String] = [:]

    /// Parses arguments (without the program name).
    ///
    /// - Parameters:
    ///   - arguments: The raw arguments.
    ///   - knownOptions: The option names that take a value, without the leading `--`.
    /// - Throws: ``ToolError`` for an unknown option or an option without a value.
    public init(_ arguments: [String], knownOptions: Set<String>) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                guard knownOptions.contains(name) else { throw ToolError("Unknown option --\(name)") }
                guard index + 1 < arguments.count else { throw ToolError("Option --\(name) needs a value") }
                options[name] = arguments[index + 1]
                index += 2
            } else {
                positional.append(argument)
                index += 1
            }
        }
    }

    /// The value of an option, if given.
    public func value(for name: String) -> String? {
        options[name]
    }
}
