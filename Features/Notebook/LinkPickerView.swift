import SwiftUI
import SwiftData

/// Adds links to a note by hand: type a CVE identifier, a GitHub repository, a
/// technology or product name, or the title of a vulnerability or another note.
///
/// Everything linked here is stored as a `NoteReference` with the `manual`
/// origin, so it stays until the user removes it, whatever the note's text says.
/// The sheet stays open after each link so several can be added in a row.
struct LinkPickerView: View {
    let noteID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(IntelligenceStore.self) private var store

    @Query private var ownReferences: [NoteReference]
    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]

    @State private var query = ""

    init(noteID: UUID) {
        self.noteID = noteID
        _ownReferences = Query(
            filter: #Predicate<NoteReference> { $0.noteID == noteID && $0.isDismissed == false }
        )
    }

    /// One thing that can be linked.
    private struct Candidate: Identifiable {
        let kind: ReferenceKind
        let entityID: String
        let displayName: String
        let detail: String?

        var id: String { "\(kind.rawValue):\(entityID)" }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var linkedKeys: Set<String> {
        Set(ownReferences.map { "\($0.kindRaw):\($0.entityID)" })
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    Section {
                        Label("Type a CVE identifier, a GitHub repository, a technology such as BootROM, an Apple product such as iOS, or the title of a note.",
                              systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let groups = candidateGroups(for: trimmedQuery)
                    if groups.isEmpty {
                        ContentUnavailableView.search(text: trimmedQuery)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(groups, id: \.kind) { group in
                            Section(group.kind.groupTitle) {
                                ForEach(group.items) { candidate in
                                    row(for: candidate)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "CVE, repository, topic or note")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Rows

    private func row(for candidate: Candidate) -> some View {
        let isLinked = linkedKeys.contains(candidate.id)
        return Button {
            guard !isLinked else { return }
            modelContext.link(
                noteID: noteID,
                kind: candidate.kind,
                entityID: candidate.entityID,
                displayName: candidate.displayName,
                origin: .manual
            )
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(candidate.displayName, systemImage: candidate.kind.systemImage)
                        .foregroundStyle(.primary)
                    if let detail = candidate.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if isLinked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(isLinked)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLinked ? "Already linked" : "Adds this link to the note")
    }

    // MARK: Candidates

    private struct CandidateGroup {
        let kind: ReferenceKind
        let items: [Candidate]
    }

    private func candidateGroups(for text: String) -> [CandidateGroup] {
        var groups: [CandidateGroup] = []

        if let vulnerabilities = vulnerabilityCandidates(for: text), !vulnerabilities.isEmpty {
            groups.append(CandidateGroup(kind: .vulnerability, items: vulnerabilities))
        }

        let topics = ResearchCatalog.topics(matching: text).prefix(8)
        for kind in [ReferenceKind.technology, .product] {
            let items = topics
                .filter { ReferenceKind.kind(for: $0) == kind }
                .map { topic in
                    Candidate(
                        kind: kind,
                        entityID: topic.id,
                        displayName: topic.name,
                        detail: topic.category.title
                    )
                }
            if !items.isEmpty { groups.append(CandidateGroup(kind: kind, items: items)) }
        }

        if let reference = Self.repositoryReference(from: text) {
            groups.append(CandidateGroup(kind: .repository, items: [
                Candidate(
                    kind: .repository,
                    entityID: reference.fullName.lowercased(),
                    displayName: reference.fullName,
                    detail: "GitHub repository"
                )
            ]))
        }

        let otherNotes = notes
            .filter { $0.id != noteID && ($0.title.localizedCaseInsensitiveContains(text) || $0.body.localizedCaseInsensitiveContains(text)) }
            .prefix(8)
            .map { note in
                Candidate(
                    kind: .note,
                    entityID: note.id.uuidString,
                    displayName: note.displayTitle,
                    detail: note.body.isEmpty ? nil : String(note.body.prefix(80))
                )
            }
        if !otherNotes.isEmpty { groups.append(CandidateGroup(kind: .note, items: Array(otherNotes))) }

        return groups
    }

    /// A typed CVE identifier is always offered, even when the record isn't
    /// stored here: the link is to the identifier, and the note says so. Other
    /// text searches the records that are on this device.
    private func vulnerabilityCandidates(for text: String) -> [Candidate]? {
        if let cveID = SearchClassifier.normalizedCVE(text) {
            let record = store.vulnerability(id: cveID)
            return [Candidate(
                kind: .vulnerability,
                entityID: cveID,
                displayName: cveID,
                detail: record?.summary ?? "Not stored on this device"
            )]
        }

        guard text.count >= 3 else { return nil }
        let matches = store.vulnerabilities
            .filter { $0.matches(searchText: text) }
            .prefix(6)
        return matches.map { record in
            Candidate(kind: .vulnerability, entityID: record.id.uppercased(), displayName: record.id, detail: record.summary)
        }
    }

    /// Accepts a GitHub URL or the `owner/name` shorthand.
    static func repositoryReference(from text: String) -> GitHubRepositoryReference? {
        if let reference = SearchClassifier.parseGitHubRepository(text), text.lowercased().contains("github.com") {
            return reference
        }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].contains("."), !parts[0].contains(":"), !parts[1].isEmpty else {
            return nil
        }
        return SearchClassifier.parseGitHubRepository("github.com/\(text)")
    }
}
