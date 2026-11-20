import Foundation

/// A version such as `0.4.0`, `v1.2` or `2.0.0-beta.1`, following the ordering
/// rules of Semantic Versioning 2.0.
///
/// Used to compare the installed version with the latest GitHub release. A
/// leading `v`, build metadata after `+`, and missing trailing components are
/// accepted: `v1.2` equals `1.2.0`. A pre-release (`1.0.0-beta.1`) sorts below
/// its release (`1.0.0`).
struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    enum Identifier: Hashable, Sendable {
        case number(Int)
        case text(String)

        var text: String {
            switch self {
            case .number(let value): String(value)
            case .text(let value): value
            }
        }
    }

    let numbers: [Int]
    let prerelease: [Identifier]

    /// Returns nil when `text` isn't a version number.
    init?(_ text: String) {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasPrefix("v") || rest.hasPrefix("V") { rest.removeFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = String(rest[..<plus]) }

        var prereleaseText: String?
        if let dash = rest.firstIndex(of: "-") {
            prereleaseText = String(rest[rest.index(after: dash)...])
            rest = String(rest[..<dash])
        }

        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard Self.isDigits(part), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        self.numbers = numbers

        var identifiers: [Identifier] = []
        if let prereleaseText {
            guard !prereleaseText.isEmpty else { return nil }
            for part in prereleaseText.split(separator: ".", omittingEmptySubsequences: false) {
                guard !part.isEmpty else { return nil }
                if Self.isDigits(part) {
                    guard let value = Int(part) else { return nil }
                    identifiers.append(.number(value))
                } else if part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
                    identifiers.append(.text(String(part)))
                } else {
                    return nil
                }
            }
        }
        prerelease = identifiers
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { ("0"..."9").contains($0) }
    }

    var isPrerelease: Bool { !prerelease.isEmpty }

    var description: String {
        let core = numbers.map(String.init).joined(separator: ".")
        guard !prerelease.isEmpty else { return core }
        return core + "-" + prerelease.map(\.text).joined(separator: ".")
    }

    // MARK: Comparison

    /// The numbers without trailing zeros, so `1.0` and `1.0.0` are the same version.
    private var normalized: [Int] {
        var result = numbers
        while result.count > 1, result.last == 0 { result.removeLast() }
        return result
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.normalized == rhs.normalized && lhs.prerelease == rhs.prerelease
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(normalized)
        hasher.combine(prerelease)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: SemanticVersion, _ rhs: SemanticVersion) -> Int {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }

        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return 0
        case (true, false): return 1
        case (false, true): return -1
        case (false, false): break
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            let order = compare(left, right)
            if order != 0 { return order }
        }
        if lhs.prerelease.count == rhs.prerelease.count { return 0 }
        return lhs.prerelease.count < rhs.prerelease.count ? -1 : 1
    }

    private static func compare(_ lhs: Identifier, _ rhs: Identifier) -> Int {
        switch (lhs, rhs) {
        case (.number(let left), .number(let right)):
            return left == right ? 0 : (left < right ? -1 : 1)
        case (.number, .text):
            return -1
        case (.text, .number):
            return 1
        case (.text(let left), .text(let right)):
            return left == right ? 0 : (left < right ? -1 : 1)
        }
    }
}
