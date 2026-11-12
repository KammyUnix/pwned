import Foundation

/// One word of a text, with where it sits.
struct TextToken: Sendable {
    /// The word as written.
    let text: String
    let lower: String
    let range: Range<String.Index>
}

enum TextTokenizer {
    /// Splits `text` into words made of letters and digits. Everything else
    /// (spaces, punctuation, symbols) separates words.
    static func tokens(in text: String) -> [TextToken] {
        var result: [TextToken] = []
        var wordStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let isWordCharacter = character.isLetter || character.isNumber
            if isWordCharacter {
                if wordStart == nil { wordStart = index }
            } else if let begin = wordStart {
                let word = String(text[begin..<index])
                result.append(TextToken(text: word, lower: word.lowercased(), range: begin..<index))
                wordStart = nil
            }
            index = text.index(after: index)
        }

        if let begin = wordStart {
            let word = String(text[begin..<text.endIndex])
            result.append(TextToken(text: word, lower: word.lowercased(), range: begin..<text.endIndex))
        }
        return result
    }
}

/// How strictly names are matched.
enum TermMatchMode: Sendable {
    /// Text the user typed. Case-insensitive, except for short ambiguous
    /// acronyms (SEP, PAC, TCC) that must be capitalized as written.
    case note
    /// Text published by a source, such as a CVE description. Operating system
    /// names must also match their exact capitalization, because "IOS" in a
    /// description is Cisco's operating system and "iOS" is Apple's.
    case description
}

/// A recognized mention of a catalog topic.
struct TermMatch: Hashable, Sendable {
    let topicID: String
    let range: Range<String.Index>
}

/// Finds mentions of `ResearchCatalog` topics (and Apple chip names) in text.
///
/// Matching is on whole words, so "WebKit" is found in "a WebKit bug" but not in
/// "WebKitGTK". Multi-word names match only when the words are adjacent.
enum TermMatcher {
    private struct Phrase {
        let topicID: String
        let words: [String]
        let exact: [String]
        let isCaseSensitive: Bool
        let isProduct: Bool
    }

    /// Aliases that exist for search ("M-series") but read as ordinary prose
    /// when matched word by word ("a series of bugs").
    private static let excludedAliasKeys: Set<String> = ["aseries", "mseries"]

    /// The topic that Apple's chip names (A14, M2) belong to.
    static let chipTopicID = "apple-silicon"

    private static let index: [String: [Phrase]] = {
        var table: [String: [Phrase]] = [:]
        for topic in ResearchCatalog.topics {
            for name in topic.allNames {
                if excludedAliasKeys.contains(AppleNaming.key(for: name)) { continue }
                let tokens = TextTokenizer.tokens(in: name)
                guard let first = tokens.first else { continue }
                let phrase = Phrase(
                    topicID: topic.id,
                    words: tokens.map(\.lower),
                    exact: tokens.map(\.text),
                    isCaseSensitive: topic.isCaseSensitive,
                    isProduct: topic.kind == .product
                )
                table[first.lower, default: []].append(phrase)
            }
        }
        return table
    }()

    /// Every mention in `text`, in reading order, longest name first when
    /// several start at the same word.
    static func matches(in text: String, mode: TermMatchMode) -> [TermMatch] {
        let tokens = TextTokenizer.tokens(in: text)
        var results: [TermMatch] = []
        var position = 0

        while position < tokens.count {
            let token = tokens[position]

            if isChipName(token.text) {
                results.append(TermMatch(topicID: chipTopicID, range: token.range))
                position += 1
                continue
            }

            var best: (phrase: Phrase, length: Int)?
            for phrase in index[token.lower] ?? [] {
                let length = phrase.words.count
                guard position + length <= tokens.count else { continue }
                guard fits(phrase, at: position, in: tokens, text: text, mode: mode) else { continue }
                if length > (best?.length ?? 0) {
                    best = (phrase, length)
                }
            }

            if let best {
                let end = tokens[position + best.length - 1].range.upperBound
                results.append(TermMatch(topicID: best.phrase.topicID, range: token.range.lowerBound..<end))
                position += best.length
            } else {
                position += 1
            }
        }
        return results
    }

    // MARK: Private

    private static func fits(
        _ phrase: Phrase,
        at position: Int,
        in tokens: [TextToken],
        text: String,
        mode: TermMatchMode
    ) -> Bool {
        let needsExactCase = phrase.isCaseSensitive || (mode == .description && phrase.isProduct)

        for offset in 0..<phrase.words.count {
            let token = tokens[position + offset]
            guard token.lower == phrase.words[offset] else { return false }
            if needsExactCase, token.text != phrase.exact[offset] { return false }

            if offset > 0 {
                let previous = tokens[position + offset - 1]
                guard isTightGap(text[previous.range.upperBound..<token.range.lowerBound]) else { return false }
            }
        }
        return true
    }

    /// Words of one name are separated by a single space, hyphen, slash or dot.
    /// Anything longer ("secure. Boot") means a sentence boundary.
    private static func isTightGap(_ gap: Substring) -> Bool {
        guard gap.count == 1, let character = gap.first else { return false }
        return character == " " || character == "-" || character == "/" || character == "."
    }

    /// `A14`, `A17`, `M1`, `M3`: an A or M followed by one or two digits.
    private static func isChipName(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 3,
              let first = word.first, first == "A" || first == "M" else { return false }
        return word.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }
}
