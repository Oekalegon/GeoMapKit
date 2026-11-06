import Foundation
import GeoCore

/// Parses the area options of the `cut` command.
public enum AreaArgument {
    /// Parses `--bbox south,west,north,east` or `--center lat,lon --radius-km R`.
    ///
    /// - Parameters:
    ///   - bbox: The value of `--bbox`, if given.
    ///   - center: The value of `--center`, if given.
    ///   - radiusKilometres: The value of `--radius-km`, if given.
    /// - Returns: The box.
    /// - Throws: ``ToolError`` if the options are missing, conflicting or invalid.
    public static func parse(bbox: String?, center: String?, radiusKilometres: String?) throws -> BoundingBox {
        switch (bbox, center) {
        case (nil, nil):
            throw ToolError("Give an area: --bbox south,west,north,east or --center lat,lon --radius-km R")
        case (.some, .some):
            throw ToolError("Use either --bbox or --center, not both")
        case let (.some(bbox), nil):
            let numbers = try parseNumbers(bbox, count: 4, option: "--bbox")
            let box = BoundingBox(south: numbers[0], west: numbers[1], north: numbers[2], east: numbers[3])
            guard box.isValid else { throw ToolError("--bbox is not a valid box (south <= north, west <= east, in range)") }
            return box
        case let (nil, .some(center)):
            let numbers = try parseNumbers(center, count: 2, option: "--center")
            guard let radiusText = radiusKilometres, let radius = Double(radiusText) else {
                throw ToolError("--center needs --radius-km R")
            }
            guard let box = BoundingBox.around(
                Coordinate(latitude: numbers[0], longitude: numbers[1]), radiusKilometres: radius
            ) else {
                throw ToolError("--center and --radius-km do not give a valid area (positive radius, away from the poles and the antimeridian)")
            }
            return box
        }
    }

    private static func parseNumbers(_ text: String, count: Int, option: String) throws -> [Double] {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == count, parts.allSatisfy({ $0 != nil }) else {
            throw ToolError("\(option) expects \(count) comma-separated numbers")
        }
        return parts.compactMap { $0 }
    }
}
