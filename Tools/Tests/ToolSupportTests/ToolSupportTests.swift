import Testing
import GeoCore
@testable import ToolSupport

@Suite("CommandLineArguments")
struct CommandLineArgumentsTests {
    @Test("Separates positional arguments and options")
    func parses() throws {
        let arguments = try CommandLineArguments(
            ["file.pbf", "--bbox", "1,2,3,4", "--limit", "5"], knownOptions: ["bbox", "limit"]
        )
        #expect(arguments.positional == ["file.pbf"])
        #expect(arguments.value(for: "bbox") == "1,2,3,4")
        #expect(arguments.value(for: "limit") == "5")
        #expect(arguments.value(for: "missing") == nil)
    }

    @Test("A negative number is accepted as an option value")
    func negativeValues() throws {
        let arguments = try CommandLineArguments(["--center", "-33.9,18.4", "--radius-km", "5"], knownOptions: ["center", "radius-km"])
        #expect(arguments.value(for: "center") == "-33.9,18.4")
        #expect(arguments.positional.isEmpty)
        let box = try AreaArgument.parse(bbox: nil, center: arguments.value(for: "center"), radiusKilometres: arguments.value(for: "radius-km"))
        #expect(box.contains(Coordinate(latitude: -33.9, longitude: 18.4)))
    }

    @Test("Unknown options and options without a value are errors")
    func errors() {
        #expect(throws: ToolError.self) { try CommandLineArguments(["--nope", "1"], knownOptions: ["bbox"]) }
        #expect(throws: ToolError.self) { try CommandLineArguments(["--bbox"], knownOptions: ["bbox"]) }
    }
}

@Suite("AreaArgument")
struct AreaArgumentTests {
    @Test("A bounding box")
    func bbox() throws {
        let box = try AreaArgument.parse(bbox: "47.1,9.5,47.2,9.6", center: nil, radiusKilometres: nil)
        #expect(box == BoundingBox(south: 47.1, west: 9.5, north: 47.2, east: 9.6))
    }

    @Test("A centre and radius")
    func centre() throws {
        let box = try AreaArgument.parse(bbox: nil, center: "59.9139,10.7522", radiusKilometres: "15")
        #expect(box.contains(Coordinate(latitude: 59.9139, longitude: 10.7522)))
        #expect(abs((box.north - box.south) - 30 / 111.195) < 1e-3)   // 2 x 15 km
    }

    @Test("Missing, conflicting and invalid areas are rejected")
    func rejects() {
        #expect(throws: ToolError.self) { try AreaArgument.parse(bbox: nil, center: nil, radiusKilometres: nil) }
        #expect(throws: ToolError.self) { try AreaArgument.parse(bbox: "1,2,3,4", center: "1,2", radiusKilometres: "5") }
        #expect(throws: ToolError.self) { try AreaArgument.parse(bbox: "1,2,3", center: nil, radiusKilometres: nil) }
        #expect(throws: ToolError.self) { try AreaArgument.parse(bbox: "4,2,3,4", center: nil, radiusKilometres: nil) }
        #expect(throws: ToolError.self) { try AreaArgument.parse(bbox: nil, center: "60,10", radiusKilometres: nil) }
        #expect(throws: ToolError.self) { try AreaArgument.parse(bbox: nil, center: "60,10", radiusKilometres: "-3") }
        #expect(throws: ToolError.self) { try AreaArgument.parse(bbox: "a,b,c,d", center: nil, radiusKilometres: nil) }
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test("Bytes use decimal units")
    func bytes() {
        #expect(Formatting.bytes(999) == "999 B")
        #expect(Formatting.bytes(3_501_761) == "3.5 MB")
        #expect(Formatting.bytes(1_000_000_000) == "1.0 GB")
    }

    @Test("Counts have thousands separators")
    func counts() {
        #expect(Formatting.count(358_095) == "358,095")
        #expect(Formatting.count(7) == "7")
    }

    @Test("Seconds from a duration, including more than a minute")
    func seconds() {
        #expect(Formatting.seconds(.milliseconds(230)) == "0.23 s")
        #expect(Formatting.seconds(.seconds(71) + .milliseconds(440)) == "71.44 s")
        #expect(Formatting.seconds(.seconds(3_725)) == "3725.00 s")
    }
}

@Suite("Throughput")
struct ThroughputTests {
    @Test("Megabytes per second")
    func rate() throws {
        let rate = try #require(Throughput.megabytesPerSecond(bytes: 1_378_381_804, duration: .seconds(23)))
        #expect(abs(rate - 59.9) < 0.1)
    }

    @Test("A zero duration has no rate")
    func zero() {
        #expect(Throughput.megabytesPerSecond(bytes: 100, duration: .zero) == nil)
    }
}

@Suite("ProfileArgument")
struct ProfileArgumentTests {
    @Test("No value means full; full and watch parse")
    func parse() throws {
        #expect(try ProfileArgument.parse(nil) == .full)
        #expect(try ProfileArgument.parse("full") == .full)
        #expect(try ProfileArgument.parse("watch") == .watch)
    }

    @Test("Any other value is rejected")
    func invalid() {
        #expect(throws: ToolError.self) { try ProfileArgument.parse("phone") }
        #expect(throws: ToolError.self) { try ProfileArgument.parse("") }
    }
}
