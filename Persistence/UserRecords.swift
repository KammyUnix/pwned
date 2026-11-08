import Foundation
import SwiftData

/// A bookmarked CVE. Stores only the identifier; the record itself is resolved
/// from the vulnerability store so data is not duplicated.
@Model
final class VulnerabilityBookmark {
    var cveID: String = ""
    var createdAt: Date = Date()

    init(cveID: String) {
        self.cveID = cveID
    }
}

/// A bookmarked GitHub repository.
@Model
final class RepositoryBookmark {
    var owner: String = ""
    var name: String = ""
    var createdAt: Date = Date()

    init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    var fullName: String { "\(owner)/\(name)" }
    var reference: GitHubRepositoryReference { GitHubRepositoryReference(owner: owner, name: name) }
}

/// An item the user opened, used for the "Recently Viewed" list.
@Model
final class ViewedItem {
    enum Kind: String, Codable {
        case vulnerability
        case repository
        case researchTopic
        case note
    }

    var kindRaw: String = Kind.vulnerability.rawValue
    /// CVE ID, `owner/name`, topic slug, or note UUID string, depending on `kind`.
    var itemID: String = ""
    var title: String = ""
    var viewedAt: Date = Date()

    init(kind: Kind, itemID: String, title: String) {
        self.kindRaw = kind.rawValue
        self.itemID = itemID
        self.title = title
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .vulnerability }
}

/// A query the user submitted to universal search.
@Model
final class SearchHistoryEntry {
    var query: String = ""
    var searchedAt: Date = Date()

    init(query: String) {
        self.query = query
    }
}
