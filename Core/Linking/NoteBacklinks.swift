import Foundation

/// Answers "which notes link to this?" from the stored references.
///
/// Built once from the references and notes already loaded by `@Query`, so a
/// lookup is a dictionary read rather than a fetch per row.
struct NoteBacklinks {
    private let noteIDsByKey: [String: [UUID]]
    private let notesByID: [UUID: ResearchNote]
    private let keysByNoteID: [UUID: Set<String>]

    init(references: [NoteReference], notes: [ResearchNote]) {
        var byKey: [String: [UUID]] = [:]
        var byNote: [UUID: Set<String>] = [:]
        for reference in references where !reference.isDismissed {
            let key = "\(reference.kindRaw):\(reference.entityID)"
            if byKey[key, default: []].contains(reference.noteID) == false {
                byKey[key, default: []].append(reference.noteID)
            }
            byNote[reference.noteID, default: []].insert(key)
        }
        noteIDsByKey = byKey
        keysByNoteID = byNote
        notesByID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Notes that link to `entityID` as any of `kinds`, most recently edited first.
    func notes(kinds: [ReferenceKind], entityID: String) -> [ResearchNote] {
        var ids: [UUID] = []
        for kind in kinds {
            for id in noteIDsByKey["\(kind.rawValue):\(entityID)"] ?? [] where !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids.compactMap { notesByID[$0] }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Other notes that link to at least one of the same targets as `noteID`,
    /// those sharing the most first.
    func notesSharingReferences(with noteID: UUID, limit: Int = 5) -> [(note: ResearchNote, shared: Int)] {
        guard let mine = keysByNoteID[noteID], !mine.isEmpty else { return [] }

        var matches: [(note: ResearchNote, shared: Int)] = []
        for (otherID, keys) in keysByNoteID where otherID != noteID {
            let shared = mine.intersection(keys).count
            guard shared > 0, let note = notesByID[otherID] else { continue }
            matches.append((note, shared))
        }
        matches.sort { lhs, rhs in
            if lhs.shared != rhs.shared { return lhs.shared > rhs.shared }
            return lhs.note.modifiedAt > rhs.note.modifiedAt
        }
        return Array(matches.prefix(limit))
    }

    /// Repositories linked from notes that also link to `topicID`: the
    /// repositories the user has filed alongside a topic.
    func repositoryIDs(alongsideTopic topicID: String) -> [String] {
        let topicKeys = ReferenceKind.catalogKinds.map { "\($0.rawValue):\(topicID)" }
        let noteIDs = topicKeys.flatMap { noteIDsByKey[$0] ?? [] }
        var seen = Set<String>()
        var result: [String] = []
        let prefix = "\(ReferenceKind.repository.rawValue):"
        for noteID in noteIDs {
            for key in (keysByNoteID[noteID] ?? []).sorted() where key.hasPrefix(prefix) {
                let repository = String(key.dropFirst(prefix.count))
                if seen.insert(repository).inserted { result.append(repository) }
            }
        }
        return result
    }
}
