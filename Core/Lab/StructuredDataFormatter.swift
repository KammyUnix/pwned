import Foundation

/// Pretty-prints JSON and property lists so they can be read.
enum StructuredDataFormatter {
    enum Format: String, Sendable {
        case json = "JSON"
        case xmlPlist = "XML property list"
        case binaryPlist = "Binary property list"
    }

    struct Output: Equatable, Sendable {
        let format: Format
        let text: String
    }

    enum Failure: Error, Equatable, Sendable {
        case empty
        case unrecognized
    }

    /// Detects JSON, XML or binary property list data and returns readable text.
    /// Property lists are shown as XML; JSON is shown indented with sorted keys.
    static func format(_ data: Data) -> Result<Output, Failure> {
        guard !data.isEmpty else { return .failure(.empty) }

        if data.starts(with: Array("bplist00".utf8)) {
            return plist(data, as: .binaryPlist)
        }

        let firstByte = data.first(where: { !isWhitespace($0) })
        if firstByte == UInt8(ascii: "{") || firstByte == UInt8(ascii: "[") {
            if let json = json(data) { return .success(json) }
        }

        if firstByte == UInt8(ascii: "<") {
            return plist(data, as: .xmlPlist)
        }

        // Last resort: a scalar JSON value (`"text"`, `42`, `true`).
        if let json = json(data) { return .success(json) }
        return .failure(.unrecognized)
    }

    static func format(_ text: String) -> Result<Output, Failure> {
        format(Data(text.utf8))
    }

    private static func json(_ data: Data) -> Output? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        options.insert(.withoutEscapingSlashes)
        guard JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: options),
              let text = String(data: pretty, encoding: .utf8) else {
            // A bare scalar can't be re-serialized; show the original text.
            guard let original = String(data: data, encoding: .utf8) else { return nil }
            return Output(format: .json, text: original.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Output(format: .json, text: text)
    }

    private static func plist(_ data: Data, as format: Format) -> Result<Output, Failure> {
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let xml = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            guard let text = String(data: xml, encoding: .utf8) else { return .failure(.unrecognized) }
            return .success(Output(format: format, text: text))
        } catch {
            return .failure(.unrecognized)
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
