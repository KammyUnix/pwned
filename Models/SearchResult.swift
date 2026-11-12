import Foundation

/// Where a universal-search result sends the user.
enum SearchTarget: Hashable, Sendable {
    /// A CVE identifier. Opens the record if one exists locally.
    case vulnerability(String)
    /// Free text to put in Discover's search field.
    case vulnerabilityQuery(String)
    /// An Apple Research Center topic, by slug.
    case researchTopic(String)
    /// A GitHub repository reference parsed from a URL.
    case repository(GitHubRepositoryReference)
    /// A local research note.
    case note(UUID)
}

/// Result groups, declared in display order.
enum SearchCategory: Int, CaseIterable, Identifiable, Sendable {
    case repository
    case vulnerability
    case appleVersion
    case appleResearch
    case note

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .repository: "Repository"
        case .vulnerability: "Vulnerability"
        case .appleVersion: "Apple Platform Version"
        case .appleResearch: "Apple Research"
        case .note: "Notes"
        }
    }
}

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let category: SearchCategory
    let title: String
    let subtitle: String
    let systemImage: String
    let target: SearchTarget
}
