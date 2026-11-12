import Foundation

/// How text is converted to and from another representation of its UTF-8 bytes.
enum TextConversion: CaseIterable, Identifiable, Sendable {
    case textToHex
    case hexToText
    case textToBase64
    case base64ToText
    case textToBinary
    case binaryToText

    var id: Self { self }

    var title: String {
        switch self {
        case .textToHex: "Text to Hex"
        case .hexToText: "Hex to Text"
        case .textToBase64: "Text to Base64"
        case .base64ToText: "Base64 to Text"
        case .textToBinary: "Text to Binary"
        case .binaryToText: "Binary to Text"
        }
    }
}

/// Text conversions. Each returns nil when the input isn't valid for the
/// conversion, so the interface can say so instead of showing a guess.
enum TextConverter {
    static func convert(_ input: String, _ conversion: TextConversion) -> String? {
        switch conversion {
        case .textToHex: hex(from: input)
        case .hexToText: text(fromHex: input)
        case .textToBase64: base64(from: input)
        case .base64ToText: text(fromBase64: input)
        case .textToBinary: binary(from: input)
        case .binaryToText: text(fromBinary: input)
        }
    }

    // MARK: Hex

    /// UTF-8 bytes as space-separated upper-case pairs: `48 49`.
    static func hex(from text: String) -> String {
        text.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Bytes from hex digits. Whitespace, commas and `0x` prefixes are ignored.
    static func data(fromHex hex: String) -> Data? {
        let cleaned = hex
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace && $0 != "," && $0 != ":" }
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2),
              cleaned.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    static func text(fromHex hex: String) -> String? {
        data(fromHex: hex).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: Base64

    static func base64(from text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Decodes standard Base64. Whitespace is ignored and missing `=` padding is tolerated.
    static func text(fromBase64 encoded: String) -> String? {
        var cleaned = encoded.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        let remainder = cleaned.count % 4
        if remainder == 1 { return nil }
        if remainder != 0 { cleaned += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Binary

    /// UTF-8 bytes as space-separated 8-bit groups: `01001000 01001001`.
    static func binary(from text: String) -> String {
        text.utf8.map { byte in
            let digits = String(byte, radix: 2)
            return String(repeating: "0", count: 8 - digits.count) + digits
        }.joined(separator: " ")
    }

    static func text(fromBinary binary: String) -> String? {
        let cleaned = binary.filter { !$0.isWhitespace && $0 != "_" }
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 8), cleaned.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            return nil
        }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 8)
            guard let byte = UInt8(cleaned[index..<next], radix: 2) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(data: Data(bytes), encoding: .utf8)
    }
}
