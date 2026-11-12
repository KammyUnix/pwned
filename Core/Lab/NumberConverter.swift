import Foundation

/// A base an integer can be written in.
enum NumberBase: Int, CaseIterable, Identifiable, Sendable {
    case binary = 2
    case octal = 8
    case decimal = 10
    case hexadecimal = 16

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .binary: "Binary"
        case .octal: "Octal"
        case .decimal: "Decimal"
        case .hexadecimal: "Hex"
        }
    }

    /// The prefix programmers write before a number in this base.
    var prefix: String {
        switch self {
        case .binary: "0b"
        case .octal: "0o"
        case .decimal: ""
        case .hexadecimal: "0x"
        }
    }
}

/// Unsigned integer conversion between bases. Values are 64-bit; anything that
/// doesn't fit is rejected rather than wrapped.
enum NumberConverter {
    /// Reads an unsigned integer written in `base`. A matching prefix
    /// (`0x`, `0b`, `0o`), spaces and underscores are allowed; a sign,
    /// other characters and values above 2^64 - 1 are not.
    static func parse(_ text: String, base: NumberBase) -> UInt64? {
        var cleaned = text.lowercased().filter { !$0.isWhitespace && $0 != "_" }
        if !base.prefix.isEmpty, cleaned.hasPrefix(base.prefix) {
            cleaned.removeFirst(base.prefix.count)
        }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isLetter) }) else {
            return nil
        }
        return UInt64(cleaned, radix: base.rawValue)
    }

    /// The value written in `base`, with its prefix, hex in upper case.
    static func format(_ value: UInt64, base: NumberBase) -> String {
        base.prefix + String(value, radix: base.rawValue, uppercase: base == .hexadecimal)
    }

    /// The printable ASCII character with this code, if there is one.
    static func printableASCII(_ value: UInt64) -> Character? {
        guard (0x20...0x7E).contains(value), let scalar = Unicode.Scalar(UInt8(value)) else { return nil }
        return Character(scalar)
    }

    /// The fewest bits that hold `value` (zero takes one).
    static func bitWidth(of value: UInt64) -> Int {
        max(64 - value.leadingZeroBitCount, 1)
    }
}
