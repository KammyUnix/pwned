import Foundation

/// The strongest interpretation of a raw search string.
enum ParsedQuery: Equatable {
    case cve(String)
    case gitHubRepository(GitHubRepositoryReference)
    case applePlatformVersion(platform: ApplePlatform, version: String)
    case text(String)
}

/// Recognizes what kind of thing a search string refers to. Purely syntactic:
/// it never claims that a CVE or repository exists.
enum SearchClassifier {
    static func classify(_ raw: String) -> ParsedQuery {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cve = normalizedCVE(query) {
            return .cve(cve)
        }
        if let repository = parseGitHubRepository(query) {
            return .gitHubRepository(repository)
        }
        if let (platform, version) = parsePlatformVersion(query) {
            return .applePlatformVersion(platform: platform, version: version)
        }
        return .text(query)
    }

    // MARK: CVE

    /// Returns an upper-cased `CVE-YYYY-NNNN…` identifier, or nil.
    static func normalizedCVE(_ input: String) -> String? {
        let parts = input.uppercased().split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "CVE",
              parts[1].count == 4,
              parts[2].count >= 4,
              parts[1].allSatisfy(\.isASCIIDigit),
              parts[2].allSatisfy(\.isASCIIDigit) else {
            return nil
        }
        return parts.joined(separator: "-")
    }

    // MARK: GitHub

    /// Parses `https://github.com/owner/name`, `github.com/owner/name`, and
    /// variants with `.git` suffixes or extra path components.
    static func parseGitHubRepository(_ input: String) -> GitHubRepositoryReference? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let components = URLComponents(string: text),
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            return nil
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        let owner = parts[0]
        var name = parts[1]
        if name.lowercased().hasSuffix(".git") {
            name.removeLast(4)
        }
        guard isValidOwner(owner), isValidRepositoryName(name) else { return nil }
        return GitHubRepositoryReference(owner: owner, name: name)
    }

    private static func isValidOwner(_ owner: String) -> Bool {
        (1...39).contains(owner.count)
            && owner.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == "-" }
    }

    private static func isValidRepositoryName(_ name: String) -> Bool {
        guard (1...100).contains(name.count), name != ".", name != ".." else { return false }
        return name.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == "-" || $0 == "_" || $0 == "." }
    }

    // MARK: Apple platform versions

    /// Parses queries such as `iOS 26.3` or `macOS 26`.
    static func parsePlatformVersion(_ input: String) -> (ApplePlatform, String)? {
        let tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count == 2,
              let platform = ApplePlatform(searchToken: tokens[0]) else {
            return nil
        }
        let components = tokens[1].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count),
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else {
            return nil
        }
        return (platform, tokens[1])
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}
