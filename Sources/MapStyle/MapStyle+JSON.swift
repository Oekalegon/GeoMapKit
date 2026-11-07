import Foundation

extension MapStyle {
    /// The version of the style file format that this build reads and writes.
    ///
    /// Files without a matching `formatVersion` are rejected with ``MapStyleError/unsupportedVersion(_:)``.
    public static let jsonFormatVersion = 1

    /// The largest style document that is read, in bytes. The built-in styles are about 10 KB.
    static let maximumJSONSize = 4_000_000

    /// Reads a style from JSON.
    ///
    /// The format is described under "Style file" in `docs/design/architecture.md`. It is strict: unknown keys and
    /// feature classes, bad colours and out-of-range numbers are errors, so a typo never turns into a silent default.
    /// A class that is missing from `classes` is hidden, as in the built-in styles.
    ///
    /// - Parameter data: The UTF-8 JSON document.
    /// - Throws: ``MapStyleError`` with the location of the problem, or if the document is larger than 4 MB.
    public init(json data: Data) throws {
        guard data.count <= Self.maximumJSONSize else {
            throw MapStyleError.invalid(path: "", reason: "file is larger than \(Self.maximumJSONSize) bytes, which no style needs")
        }
        do {
            self = try JSONDecoder().decode(MapStyle.self, from: data)
        } catch let error as MapStyleError {
            throw error
        } catch let error as DecodingError {
            throw Self.styleError(from: error)
        } catch {
            throw MapStyleError.invalid(path: "", reason: "\(error)")
        }
    }

    /// Writes the style as JSON, with sorted keys and indentation so the output is deterministic and easy to edit.
    ///
    /// Colours are written with 8 bits per component. Reading the result gives back an equal style for colours that
    /// were made from 8-bit values, which includes every built-in style.
    ///
    /// - Throws: ``MapStyleError`` if encoding fails (not expected for a valid style).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw MapStyleError.invalid(path: "", reason: "\(error)")
        }
    }

    private static func styleError(from error: DecodingError) -> MapStyleError {
        func describe(_ path: [CodingKey]) -> String {
            var text = ""
            for key in path {
                if let index = key.intValue {
                    text += "[\(index)]"
                } else {
                    text += (text.isEmpty ? "" : ".") + key.stringValue
                }
            }
            return text
        }
        switch error {
        case .keyNotFound(let key, let context):
            return .invalid(path: describe(context.codingPath), reason: "missing key '\(key.stringValue)'")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return .invalid(path: describe(context.codingPath), reason: "wrong kind of value (\(context.debugDescription))")
        case .dataCorrupted(let context):
            if context.codingPath.isEmpty, context.underlyingError != nil {
                return .invalid(path: "", reason: "not valid JSON (\(context.debugDescription))")
            }
            return .invalid(path: describe(context.codingPath), reason: context.debugDescription)
        @unknown default:
            return .invalid(path: "", reason: "\(error)")
        }
    }
}
