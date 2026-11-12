import Foundation

/// A place in a note's text that refers to something in the research database.
struct LinkMention: Hashable, Sendable {
    enum Certainty: Sendable {
        /// Unambiguous text (a CVE identifier, a GitHub URL). Linked automatically.
        case certain
        /// A word that is probably a reference (BootROM, iOS 18). Only linked
        /// when the user confirms it.
        case suggested
    }

    let kind: ReferenceKind
    /// Stable target ID: see `NoteReference.entityID`.
    let entityID: String
    let displayName: String
    /// Where the text sits in the note body.
    let range: Range<String.Index>
    let certainty: Certainty

    /// Identity of the target, shared with `NoteReference`.
    var key: String { "\(kind.rawValue):\(entityID)" }
}

/// Finds references in note text. Pure and synchronous, so it can run on any
/// thread and be tested without a database.
///
/// What it does and does not claim:
/// * A CVE identifier or GitHub URL is recognized from its shape alone. That
///   says the text *names* a CVE or repository, not that one exists; whether
///   the record is on this device is a separate question (`ReferenceResolver`).
/// * Technology and product names come from `ResearchCatalog`. They are
///   suggestions: a note that says "kernel" may not mean Apple's.
enum NoteLinker {
    /// Every mention in `text`, in reading order.
    static func mentions(in text: String) -> [LinkMention] {
        var result = cveMentions(in: text)
        result += repositoryMentions(in: text)

        let certainRanges = result.map(\.range)
        for match in TermMatcher.matches(in: text, mode: .note) {
            guard let topic = ResearchCatalog.topic(withID: match.topicID) else { continue }
            // "github.com/apple/WebKit" is a repository, not a mention of WebKit.
            if certainRanges.contains(where: { $0.overlaps(match.range) }) { continue }

            let kind = ReferenceKind.kind(for: topic)
            let range = (kind == .product) ? rangeIncludingVersion(match.range, in: text) : match.range
            result.append(LinkMention(
                kind: kind,
                entityID: topic.id,
                displayName: topic.name,
                range: range,
                certainty: .suggested
            ))
        }

        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The first mention of each distinct target, in reading order.
    static func uniqueMentions(_ mentions: [LinkMention]) -> [LinkMention] {
        var seen = Set<String>()
        return mentions.filter { seen.insert($0.key).inserted }
    }

    // MARK: CVE identifiers

    private static func cveMentions(in text: String) -> [LinkMention] {
        let tokens = TextTokenizer.tokens(in: text)
        var result: [LinkMention] = []
        var index = 0

        while index + 2 < tokens.count {
            let first = tokens[index]
            let year = tokens[index + 1]
            let number = tokens[index + 2]

            guard first.lower == "cve",
                  isDigits(year.text), year.text.count == 4,
                  isDigits(number.text), number.text.count >= 4,
                  text[first.range.upperBound..<year.range.lowerBound] == "-",
                  text[year.range.upperBound..<number.range.lowerBound] == "-",
                  let id = SearchClassifier.normalizedCVE("CVE-\(year.text)-\(number.text)") else {
                index += 1
                continue
            }

            result.append(LinkMention(
                kind: .vulnerability,
                entityID: id,
                displayName: id,
                range: first.range.lowerBound..<number.range.upperBound,
                certainty: .certain
            ))
            index += 3
        }
        return result
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: GitHub repositories

    private static func repositoryMentions(in text: String) -> [LinkMention] {
        var result: [LinkMention] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let hit = text.range(of: "github.com/", options: .caseInsensitive, range: searchStart..<text.endIndex) {
            searchStart = hit.upperBound

            // Skip longer host names such as "api.github.com/" or "notgithub.com/".
            if hit.lowerBound > text.startIndex {
                let before = text[..<hit.lowerBound]
                if !before.lowercased().hasSuffix("www.") {
                    let previous = text[text.index(before: hit.lowerBound)]
                    if previous.isLetter || previous.isNumber || previous == "-" || previous == "." {
                        continue
                    }
                }
            }

            var index = hit.upperBound
            let ownerStart = index
            while index < text.endIndex, isOwnerCharacter(text[index]) {
                index = text.index(after: index)
            }
            guard index > ownerStart, index < text.endIndex, text[index] == "/" else { continue }
            let owner = String(text[ownerStart..<index])

            index = text.index(after: index)
            let nameStart = index
            while index < text.endIndex, isNameCharacter(text[index]) {
                index = text.index(after: index)
            }
            // A trailing dot is sentence punctuation, not part of the name.
            var nameEnd = index
            while nameEnd > nameStart, text[text.index(before: nameEnd)] == "." {
                nameEnd = text.index(before: nameEnd)
            }
            guard nameEnd > nameStart else { continue }
            let name = String(text[nameStart..<nameEnd])

            guard let reference = SearchClassifier.parseGitHubRepository("github.com/\(owner)/\(name)") else {
                continue
            }
            result.append(LinkMention(
                kind: .repository,
                entityID: reference.fullName.lowercased(),
                displayName: reference.fullName,
                range: hit.lowerBound..<nameEnd,
                certainty: .certain
            ))
            searchStart = nameEnd
        }
        return result
    }

    private static func isOwnerCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "-")
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "-"
            || character == "_" || character == ".")
    }

    // MARK: Versions

    /// Extends a platform name over a version that follows it: "iOS 18.2".
    private static func rangeIncludingVersion(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var index = range.upperBound
        guard index < text.endIndex, text[index] == " " else { return range }
        index = text.index(after: index)

        let start = index
        while index < text.endIndex, text[index].isASCII, text[index].isNumber || text[index] == "." {
            index = text.index(after: index)
        }

        var end = index
        while end > start, text[text.index(before: end)] == "." {
            end = text.index(before: end)
        }
        guard end > start, let first = text[start...].first, first.isASCII, first.isNumber else {
            return range
        }
        return range.lowerBound..<end
    }
}

// MARK: - Link URLs

/// The `pwned://open?kind=…&id=…` URLs that rendered note text uses for its
/// inline links. They never leave the app: the open-URL handler on the note
/// screen turns them into navigation.
enum LinkURL {
    static let scheme = "pwned"
    private static let host = "open"

    static func url(kind: ReferenceKind, entityID: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "id", value: entityID)
        ]
        return components.url
    }

    static func target(from url: URL) -> (kind: ReferenceKind, entityID: String)? {
        guard url.scheme == scheme, url.host == host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let kindText = items.first(where: { $0.name == "kind" })?.value,
              let kind = ReferenceKind(rawValue: kindText),
              let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty else {
            return nil
        }
        return (kind, id)
    }
}

extension AppRoute {
    /// The destination for a `LinkURL`, or nil for any other URL.
    init?(linkURL: URL) {
        guard let target = LinkURL.target(from: linkURL),
              let route = AppRoute(kind: target.kind, entityID: target.entityID) else {
            return nil
        }
        self = route
    }
}
