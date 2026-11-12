import Foundation

/// Builds categorized universal-search results from local data only.
///
/// Searches the Apple-focused feed, the research catalog, the user's notes and
/// the links those notes make. A CVE identifier is looked up among *every*
/// record on the device, because someone who types a specific ID wants that
/// record whether or not it is Apple's; free-text matches come from the Apple
/// feed only, so an unrelated record never shows up under an ordinary search.
@MainActor
enum SearchEngine {
    private static let maxVulnerabilityMatches = 5
    private static let maxNoteMatches = 5

    /// - Parameters:
    ///   - feed: Apple-focused records, searched by text.
    ///   - known: Every record on the device, used to resolve an exact CVE ID.
    ///   - references: Note links, so a note can be found by what it links to.
    static func results(
        for rawQuery: String,
        feed: [Vulnerability],
        known: [Vulnerability],
        notes: [ResearchNote],
        references: [NoteReference] = []
    ) -> [SearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []

        switch SearchClassifier.classify(query) {
        case .cve(let id):
            results.append(cveResult(id: id, known: known))

        case .gitHubRepository(let reference):
            results.append(SearchResult(
                id: "repo:\(reference.fullName.lowercased())",
                category: .repository,
                title: reference.fullName,
                subtitle: "GitHub repository. Opens a page that fetches its details from GitHub.",
                systemImage: "shippingbox",
                target: .repository(reference)
            ))

        case .applePlatformVersion(let platform, let version):
            results.append(SearchResult(
                id: "version:\(platform.rawValue.lowercased())-\(version)",
                category: .appleVersion,
                title: "\(platform.title) \(version)",
                subtitle: "Opens the \(platform.title) research page.",
                systemImage: platform.systemImage,
                target: .researchTopic(ResearchCatalog.slug(for: platform.title))
            ))

        case .text:
            break
        }

        results += topicResults(for: query)
        results += vulnerabilityTextResults(for: query, in: feed)
        results += noteResults(for: query, in: notes, references: references)

        // Stable sort by category so groups appear in declaration order while
        // preserving relevance order within each group.
        return results.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.category != rhs.element.category {
                    return lhs.element.category.rawValue < rhs.element.category.rawValue
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: Result builders

    private static func cveResult(id: String, known: [Vulnerability]) -> SearchResult {
        if let match = known.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            return SearchResult(
                id: "cve:\(match.id)",
                category: .vulnerability,
                title: match.id,
                subtitle: match.summary,
                systemImage: "exclamationmark.shield",
                target: .vulnerability(match.id)
            )
        }
        return SearchResult(
            id: "cve:\(id)",
            category: .vulnerability,
            title: id,
            subtitle: "Not stored on this device. Opens a live lookup on NVD.",
            systemImage: "exclamationmark.shield",
            target: .vulnerability(id)
        )
    }

    private static func topicResults(for query: String) -> [SearchResult] {
        ResearchCatalog.topics(matching: query).map { topic in
            SearchResult(
                id: "topic:\(topic.id)",
                category: .appleResearch,
                title: topic.name,
                subtitle: topic.category.title,
                systemImage: topic.category.systemImage,
                target: .researchTopic(topic.id)
            )
        }
    }

    private static func vulnerabilityTextResults(for query: String, in feed: [Vulnerability]) -> [SearchResult] {
        guard query.count >= 2 else { return [] }
        let matches = feed.filter { $0.matches(searchText: query) }
        return matches.prefix(maxVulnerabilityMatches).map { vulnerability in
            SearchResult(
                id: "cve:\(vulnerability.id)",
                category: .vulnerability,
                title: vulnerability.id,
                subtitle: vulnerability.summary,
                systemImage: "exclamationmark.shield",
                target: .vulnerability(vulnerability.id)
            )
        }
    }

    /// A note matches on its title, text and tags, and on anything it links to:
    /// a CVE identifier, a technology, a product or a repository.
    static func noteMatches(
        for query: String,
        in notes: [ResearchNote],
        references: [NoteReference]
    ) -> [ResearchNote] {
        let linksByNote = Dictionary(
            grouping: references.filter { !$0.isDismissed },
            by: \.noteID
        )
        return notes.filter { note in
            if note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
                || note.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
                return true
            }
            return (linksByNote[note.id] ?? []).contains { reference in
                reference.displayName.localizedCaseInsensitiveContains(query)
                    || reference.entityID.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private static func noteResults(
        for query: String,
        in notes: [ResearchNote],
        references: [NoteReference]
    ) -> [SearchResult] {
        noteMatches(for: query, in: notes, references: references)
            .prefix(maxNoteMatches)
            .map { note in
                SearchResult(
                    id: "note:\(note.id.uuidString)",
                    category: .note,
                    title: note.displayTitle,
                    subtitle: note.body.isEmpty ? "No content" : String(note.body.prefix(120)),
                    systemImage: "note.text",
                    target: .note(note.id)
                )
            }
    }
}

extension Vulnerability {
    /// Case-insensitive match against the identifier, summary and product names.
    /// Products also match by their display name, so "ios" finds a record whose
    /// CPE product is `iphone_os`.
    func matches(searchText: String) -> Bool {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if id.localizedCaseInsensitiveContains(text) || summary.localizedCaseInsensitiveContains(text) {
            return true
        }
        return affectedProducts.contains {
            $0.vendor.localizedCaseInsensitiveContains(text)
                || $0.product.localizedCaseInsensitiveContains(text)
                || $0.versions.localizedCaseInsensitiveContains(text)
                || AppleNaming.productName(vendor: $0.vendor, product: $0.product)
                    .localizedCaseInsensitiveContains(text)
        }
    }
}
