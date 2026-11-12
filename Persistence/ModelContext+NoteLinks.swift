import Foundation
import SwiftData

/// Reading and writing note references.
///
/// All of these run against the same `ModelContext` as the rest of the user's
/// data, so references survive relaunches, are never touched by "Clear Cached
/// Data", and need no extra store.
extension ModelContext {
    /// References owned by a note. Hidden (dismissed) links are left out unless asked for.
    func noteReferences(forNote noteID: UUID, includeDismissed: Bool = false) -> [NoteReference] {
        let descriptor = FetchDescriptor<NoteReference>(predicate: #Predicate { $0.noteID == noteID })
        let all = (try? fetch(descriptor)) ?? []
        return includeDismissed ? all : all.filter { !$0.isDismissed }
    }

    func existingReference(noteID: UUID, kind: ReferenceKind, entityID: String) -> NoteReference? {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<NoteReference>(
            predicate: #Predicate { $0.noteID == noteID && $0.kindRaw == kindRaw && $0.entityID == entityID }
        )
        return (try? fetch(descriptor))?.first
    }

    /// Links a note to a target. Linking the same target twice returns the
    /// existing reference, and linking something the user previously removed
    /// brings it back.
    @discardableResult
    func link(
        noteID: UUID,
        kind: ReferenceKind,
        entityID: String,
        displayName: String,
        origin: ReferenceOrigin
    ) -> NoteReference {
        if let existing = existingReference(noteID: noteID, kind: kind, entityID: entityID) {
            if existing.isDismissed {
                existing.isDismissed = false
                existing.originRaw = origin.rawValue
                existing.displayName = displayName
                saveLoggingFailure()
            }
            return existing
        }

        let reference = NoteReference(
            noteID: noteID, kind: kind, entityID: entityID, displayName: displayName, origin: origin
        )
        insert(reference)
        saveLoggingFailure()
        return reference
    }

    /// Removes a link.
    ///
    /// CVEs and repositories are recognized from the text, so their record is
    /// kept as hidden (`isDismissed`) to stop the same words being linked
    /// again. Everything else is simply deleted.
    func unlink(_ reference: NoteReference) {
        switch reference.kind {
        case .vulnerability, .repository:
            reference.isDismissed = true
        case .technology, .product, .note:
            delete(reference)
        }
        saveLoggingFailure()
    }

    /// Brings a note's automatic links in line with what its text says now.
    ///
    /// - New CVE identifiers and GitHub URLs get a link.
    /// - Automatic links whose text is gone are removed.
    /// - Links the user created are never removed here.
    /// - Links the user dismissed stay hidden while the text is still there,
    ///   and are forgotten once it is gone.
    func syncAutomaticReferences(noteID: UUID, mentions: [LinkMention]) {
        var wanted: [String: LinkMention] = [:]
        for mention in mentions where mention.certainty == .certain && wanted[mention.key] == nil {
            wanted[mention.key] = mention
        }

        var changed = false
        var existingKeys = Set<String>()

        for reference in noteReferences(forNote: noteID, includeDismissed: true) {
            let key = "\(reference.kindRaw):\(reference.entityID)"
            existingKeys.insert(key)
            let stillMentioned = wanted[key] != nil

            if reference.isDismissed {
                if !stillMentioned {
                    delete(reference)
                    changed = true
                }
            } else if reference.origin == .automatic, !stillMentioned {
                delete(reference)
                changed = true
            }
        }

        for (key, mention) in wanted where !existingKeys.contains(key) {
            insert(NoteReference(
                noteID: noteID,
                kind: mention.kind,
                entityID: mention.entityID,
                displayName: mention.displayName,
                origin: .automatic
            ))
            changed = true
        }

        if changed { saveLoggingFailure() }
    }

    /// Moves links stored in the note's older `related…` fields into references,
    /// then empties the fields so a link the user later removes stays removed.
    func importLegacyLinks(for note: ResearchNote) {
        guard !note.relatedCVEIDs.isEmpty || !note.relatedRepositories.isEmpty || !note.relatedTopicIDs.isEmpty else {
            return
        }

        for raw in note.relatedCVEIDs {
            guard let id = SearchClassifier.normalizedCVE(raw) else { continue }
            link(noteID: note.id, kind: .vulnerability, entityID: id, displayName: id, origin: .manual)
        }
        for raw in note.relatedRepositories {
            let parts = raw.split(separator: "/").map(String.init)
            guard parts.count == 2 else { continue }
            let reference = GitHubRepositoryReference(owner: parts[0], name: parts[1])
            link(noteID: note.id, kind: .repository, entityID: reference.fullName.lowercased(),
                 displayName: reference.fullName, origin: .manual)
        }
        for topicID in note.relatedTopicIDs {
            guard let topic = ResearchCatalog.topic(withID: topicID) else { continue }
            link(noteID: note.id, kind: ReferenceKind.kind(for: topic), entityID: topic.id,
                 displayName: topic.name, origin: .manual)
        }

        note.relatedCVEIDs = []
        note.relatedRepositories = []
        note.relatedTopicIDs = []
        saveLoggingFailure()
    }

    /// Deletes a note's links, and any other note's links that point at it.
    func deleteReferences(forNote noteID: UUID) {
        for reference in noteReferences(forNote: noteID, includeDismissed: true) {
            delete(reference)
        }

        let targetKind = ReferenceKind.note.rawValue
        let targetID = noteID.uuidString
        let descriptor = FetchDescriptor<NoteReference>(
            predicate: #Predicate { $0.kindRaw == targetKind && $0.entityID == targetID }
        )
        for reference in (try? fetch(descriptor)) ?? [] {
            delete(reference)
        }
    }
}
