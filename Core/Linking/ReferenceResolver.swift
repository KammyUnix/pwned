import SwiftUI

/// Whether a reference's target can be opened from what is on this device.
enum ReferenceResolution: Equatable, Sendable {
    /// The record is in the local database (or catalog) and opens offline.
    case resolved
    /// The ID is well formed but nothing on this device matches it. A CVE in
    /// this state can be looked up on NVD; nothing about it is invented.
    case unresolved
    /// Lives outside the local database. Repositories open a page that fetches
    /// from GitHub on demand.
    case external

    /// A short note for rows and accessibility, nil when there's nothing to add.
    var caption: String? {
        switch self {
        case .resolved: nil
        case .unresolved: "Not stored on this device"
        case .external: "GitHub repository"
        }
    }
}

/// Works out a reference's `ReferenceResolution` from current data. Resolution
/// is never stored, because it changes whenever the vulnerability cache does.
@MainActor
enum ReferenceResolver {
    static func resolution(kind: ReferenceKind, entityID: String, in store: IntelligenceStore) -> ReferenceResolution {
        switch kind {
        case .vulnerability:
            return store.vulnerability(id: entityID) != nil ? .resolved : .unresolved
        case .technology, .product:
            return ResearchCatalog.topic(withID: entityID) != nil ? .resolved : .unresolved
        case .repository:
            return .external
        case .note:
            // Notes are checked when opened; a deleted note's links are removed with it.
            return .resolved
        }
    }
}

/// Turns a note body into styled text with inline links.
enum NoteRenderer {
    /// - Parameters:
    ///   - mentions: Mentions found in exactly `body`.
    ///   - references: The note's references. Only a mention whose target is
    ///     linked becomes a link; unconfirmed suggestions stay plain text.
    ///   - resolution: How a linked target resolves. Unresolved targets get a
    ///     quieter, dotted style so they read as "known by name, not on hand".
    static func attributed(
        body: String,
        mentions: [LinkMention],
        references: [NoteReference],
        resolution: (ReferenceKind, String) -> ReferenceResolution
    ) -> AttributedString {
        var output = AttributedString(body)
        let linked = Set(references.filter { !$0.isDismissed }.map { "\($0.kindRaw):\($0.entityID)" })

        for mention in mentions where linked.contains(mention.key) {
            guard let range = Range(mention.range, in: output),
                  let url = LinkURL.url(kind: mention.kind, entityID: mention.entityID) else {
                continue
            }
            output[range].link = url
            if resolution(mention.kind, mention.entityID) == .unresolved {
                output[range].foregroundColor = .secondary
                output[range].underlineStyle = Text.LineStyle(pattern: .dot, color: .secondary)
            }
        }
        return output
    }
}
