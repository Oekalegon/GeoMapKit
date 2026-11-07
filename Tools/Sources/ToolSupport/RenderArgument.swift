import Foundation
import GeoCore

/// Parses the options of the `render` command.
public enum RenderArgument {
    /// Parses and validates the options.
    ///
    /// - Parameters:
    ///   - center: `--center lat,lon`, required.
    ///   - zoom: `--zoom Z`, required, 0 to 24.
    ///   - size: `--size WxH` in points, default `800x600`, each side 16 to 4096.
    ///   - scale: `--scale S`, pixels per point, default 2, 1 to 4.
    ///   - style: `--style standard|watch|file.json`, default `standard`.
    ///   - output: `--output file.png`, required.
    ///   - attribution: `--attribution full|compact|none`; default is the style's own choice.
    /// - Throws: ``ToolError`` for a missing or invalid option.
    public static func parse(
        center: String?, zoom: String?, size: String?, scale: String?, style: String?, output: String?,
        attribution: String? = nil
    ) throws -> RenderRequest {
        guard let center else { throw ToolError("render needs --center lat,lon") }
        let parts = center.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let latitude = parts[0], let longitude = parts[1] else {
            throw ToolError("--center expects 2 comma-separated numbers")
        }
        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else { throw ToolError("--center is outside the valid latitude and longitude range") }

        guard let zoomText = zoom, let zoomValue = Double(zoomText), (0...24).contains(zoomValue) else {
            throw ToolError("render needs --zoom Z, a number from 0 to 24")
        }

        var width = 800
        var height = 600
        if let size {
            let sides = size.lowercased().split(separator: "x").map { Int($0) }
            guard sides.count == 2, let w = sides[0], let h = sides[1], (16...4096).contains(w), (16...4096).contains(h) else {
                throw ToolError("--size expects WxH with each side from 16 to 4096, for example 800x600")
            }
            width = w
            height = h
        }

        var scaleValue = 2.0
        if let scale {
            guard let value = Double(scale), (1...4).contains(value) else { throw ToolError("--scale expects a number from 1 to 4") }
            scaleValue = value
        }

        var chosen = RenderRequest.Style.standard
        var styleFile: String?
        if let style {
            if let value = RenderRequest.Style(rawValue: style) {
                chosen = value
            } else if style.lowercased().hasSuffix(".json") {
                styleFile = style
            } else {
                throw ToolError("--style expects standard, watch or the path of a .json style file, not '\(style)'")
            }
        }

        var credit: RenderRequest.Attribution?
        if let attribution {
            guard let value = RenderRequest.Attribution(rawValue: attribution) else {
                throw ToolError("--attribution expects full, compact or none, not '\(attribution)'")
            }
            credit = value
        }

        guard let output, !output.isEmpty else { throw ToolError("render needs --output <file.png>") }
        return RenderRequest(
            center: coordinate, zoom: zoomValue, width: width, height: height, scale: scaleValue, style: chosen, output: output,
            attribution: credit, styleFile: styleFile)
    }
}
