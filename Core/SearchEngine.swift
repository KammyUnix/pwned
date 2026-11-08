import Foundation

/// Builds categorized universal-search results from local data only.
///
/// Phase 1 searches the vulnerability store, the Apple Research catalog and the
/// user's notes. Live sources (NVD, GitHub) are added in later phases.
@MainActor
enum SearchEngine {
    private static let maxVulnerabilityMatches = 5
    private static let maxNoteMatches = 5

    static func results(
        for rawQuery: String,
        vulnerabilities: [Vulnerability],
        notes: [ResearchNote]
    ) -> [SearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []

        switch SearchClassifier.classify(query) {
        case .cve(let id):
            results.append(cveResult(id: id, vulnerabilities: vulnerabilities))

        case .gitHubRepository(let reference):
            results.append(SearchResult(
                id: "repo:\(reference.fullName.lowercased())",
                category: .repository,
                title: reference.fullName,
                subtitle: "GitHub repository. Parsed from the URL; not yet fetched.",
                systemImage: "shippingbox",
                target: .repository(reference),
                isSample: false
            ))

        case .applePlatformVersion(let platform, let version):
            results.append(SearchResult(
                id: "version:\(platform.rawValue.lowercased())-\(version)",
                category: .appleVersion,
                title: "\(platform.title) \(version)",
                subtitle: "Opens the \(platform.title) research page. Version-specific release data is not loaded yet.",
                systemImage: platform.systemImage,
                target: .researchTopic(ResearchCatalog.slug(for: platform.title)),
                isSample: false
            ))

        case .text:
            break
        }

        results += topicResults(for: query)
        results += vulnerabilityTextResults(for: query, in: vulnerabilities)
        results += noteResults(for: query, in: notes)

        results.append(SearchResult(
            id: "search:vulnerabilities",
            category: .searchIn,
            title: "Search Vulnerabilities for “\(query)”",
            subtitle: "Filter the Vulnerabilities tab with this text.",
            systemImage: "exclamationmark.shield",
            target: .vulnerabilityQuery(query),
            isSample: false
        ))

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

    private static func cveResult(id: String, vulnerabilities: [Vulnerability]) -> SearchResult {
        if let match = vulnerabilities.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            return SearchResult(
                id: "cve:\(match.id)",
                category: .vulnerability,
                title: match.id,
                subtitle: match.summary,
                systemImage: "exclamationmark.shield",
                target: .vulnerability(match.id),
                isSample: match.isSample
            )
        }
        return SearchResult(
            id: "cve:\(id)",
            category: .vulnerability,
            title: id,
            subtitle: "Not in the local database. Live NVD lookup is not available yet.",
            systemImage: "exclamationmark.shield",
            target: .vulnerability(id),
            isSample: false
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
                target: .researchTopic(topic.id),
                isSample: false
            )
        }
    }

    private static func vulnerabilityTextResults(for query: String, in vulnerabilities: [Vulnerability]) -> [SearchResult] {
        guard query.count >= 2 else { return [] }
        let matches = vulnerabilities.filter { $0.matches(searchText: query) }
        return matches.prefix(maxVulnerabilityMatches).map { vulnerability in
            SearchResult(
                id: "cve:\(vulnerability.id)",
                category: .vulnerability,
                title: vulnerability.id,
                subtitle: vulnerability.summary,
                systemImage: "exclamationmark.shield",
                target: .vulnerability(vulnerability.id),
                isSample: vulnerability.isSample
            )
        }
    }

    private static func noteResults(for query: String, in notes: [ResearchNote]) -> [SearchResult] {
        let matches = notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return matches.prefix(maxNoteMatches).map { note in
            SearchResult(
                id: "note:\(note.id.uuidString)",
                category: .note,
                title: note.displayTitle,
                subtitle: note.body.isEmpty ? "No content" : String(note.body.prefix(120)),
                systemImage: "note.text",
                target: .note(note.id),
                isSample: false
            )
        }
    }
}

extension Vulnerability {
    /// Case-insensitive match against the identifier, summary and product names.
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
        }
    }
}
