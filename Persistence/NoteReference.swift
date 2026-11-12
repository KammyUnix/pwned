import Foundation
import SwiftData

/// What a note reference points at.
///
/// `technology` and `product` both point into the research catalog
/// (`ResearchCatalog`); the catalog entry's own `kind` decides which one a link
/// gets, so BootROM is a technology and iOS is a product.
enum ReferenceKind: String, Codable, CaseIterable, Sendable {
    case vulnerability
    case technology
    case product
    case repository
    case note

    /// Group heading in a note's Related Research section.
    var groupTitle: String {
        switch self {
        case .vulnerability: "Vulnerabilities"
        case .technology: "Technologies"
        case .product: "Apple Products"
        case .repository: "Repositories"
        case .note: "Notes"
        }
    }

    /// Singular name for accessibility labels and pickers.
    var title: String {
        switch self {
        case .vulnerability: "Vulnerability"
        case .technology: "Technology"
        case .product: "Apple Product"
        case .repository: "Repository"
        case .note: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .vulnerability: "exclamationmark.shield"
        case .technology: "cpu"
        case .product: "apple.logo"
        case .repository: "shippingbox"
        case .note: "note.text"
        }
    }

    /// Display order of the groups.
    var sortOrder: Int {
        switch self {
        case .vulnerability: 0
        case .technology: 1
        case .product: 2
        case .repository: 3
        case .note: 4
        }
    }

    /// The kind a catalog topic is linked as.
    static func kind(for topic: ResearchTopic) -> ReferenceKind {
        topic.kind == .product ? .product : .technology
    }

    /// Both catalog kinds, for looking up every link to one topic ID.
    static let catalogKinds: [ReferenceKind] = [.technology, .product]
}

/// How a reference came to exist.
enum ReferenceOrigin: String, Codable, Sendable {
    /// Recognized by Pwned from unambiguous text: a CVE identifier or a GitHub URL.
    case automatic
    /// Added by the user, either from the link picker or by accepting a suggestion.
    case manual
}

/// A link from a note to something in the research database.
///
/// Links are stored apart from the note's text and identify their target by a
/// stable ID (a CVE identifier, a catalog slug, `owner/name`, a note UUID)
/// rather than by the words that happen to be in the note. Editing or deleting
/// a sentence therefore never breaks a link the user made, and one note can
/// link to the same CVE from several places with a single row.
///
/// Resolution status ("is this in the local database?") is deliberately not
/// stored: it changes whenever the cache does, so `ReferenceResolver` works it
/// out when needed. Identity is `noteID` + `kind` + `entityID`; uniqueness is
/// enforced by `ModelContext.link(...)` rather than a store constraint, which
/// keeps this model a plain addition to the existing store.
@Model
final class NoteReference {
    var id: UUID = UUID()
    /// `ResearchNote.id` of the note that owns this link.
    var noteID: UUID = UUID()
    var kindRaw: String = ReferenceKind.vulnerability.rawValue
    /// Stable identifier: CVE ID (upper-case), catalog topic slug, lower-case
    /// `owner/name`, or a note's UUID string.
    var entityID: String = ""
    /// What the user sees. Not used for matching.
    var displayName: String = ""
    var originRaw: String = ReferenceOrigin.manual.rawValue
    /// True when the user removed an automatic link. The record stays so the
    /// same text isn't linked again, but it is hidden everywhere else.
    var isDismissed: Bool = false
    var createdAt: Date = Date()

    init(noteID: UUID, kind: ReferenceKind, entityID: String, displayName: String, origin: ReferenceOrigin) {
        self.noteID = noteID
        self.kindRaw = kind.rawValue
        self.entityID = entityID
        self.displayName = displayName
        self.originRaw = origin.rawValue
    }

    var kind: ReferenceKind { ReferenceKind(rawValue: kindRaw) ?? .vulnerability }
    var origin: ReferenceOrigin { ReferenceOrigin(rawValue: originRaw) ?? .manual }

    /// Where the link leads inside the app, if its ID is well formed.
    var route: AppRoute? {
        AppRoute(kind: kind, entityID: entityID)
    }
}

extension AppRoute {
    /// The in-app destination for a reference target.
    init?(kind: ReferenceKind, entityID: String) {
        switch kind {
        case .vulnerability:
            guard let id = SearchClassifier.normalizedCVE(entityID) else { return nil }
            self = .vulnerability(id)
        case .technology, .product:
            guard ResearchCatalog.topic(withID: entityID) != nil else { return nil }
            self = .researchTopic(entityID)
        case .repository:
            let parts = entityID.split(separator: "/").map(String.init)
            guard parts.count == 2 else { return nil }
            self = .repository(GitHubRepositoryReference(owner: parts[0], name: parts[1]))
        case .note:
            guard let uuid = UUID(uuidString: entityID) else { return nil }
            self = .note(uuid)
        }
    }
}
