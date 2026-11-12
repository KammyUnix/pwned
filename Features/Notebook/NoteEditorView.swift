import SwiftUI
import SwiftData

/// A research note. It reads as text with inline links, edits as plain text,
/// and keeps its links in `NoteReference` rows apart from the words.
///
/// * CVE identifiers and GitHub URLs link themselves, as soon as they are typed.
/// * Technology and product names (BootROM, iOS 18) are only *suggested*; the
///   user decides which become links.
/// * Links can also be added by hand from the link picker and removed again.
struct NoteEditorView: View {
    let noteID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(IntelligenceStore.self) private var store

    @Query private var matches: [ResearchNote]
    @Query private var ownReferences: [NoteReference]
    @Query private var allReferences: [NoteReference]
    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var allNotes: [ResearchNote]

    @State private var confirmsDelete = false
    @State private var isEditing = false
    @State private var didChooseMode = false
    @State private var showsLinkPicker = false
    @State private var analysis = Analysis(text: "", mentions: [])

    /// The mentions found in one exact version of the body.
    private struct Analysis {
        var text: String
        var mentions: [LinkMention]
    }

    init(noteID: UUID) {
        self.noteID = noteID
        _matches = Query(filter: #Predicate<ResearchNote> { $0.id == noteID })
        _ownReferences = Query(
            filter: #Predicate<NoteReference> { $0.noteID == noteID && $0.isDismissed == false }
        )
        _allReferences = Query(filter: #Predicate<NoteReference> { $0.isDismissed == false })
    }

    var body: some View {
        Group {
            if let note = matches.first {
                editor(for: note)
            } else {
                ContentUnavailableView(
                    "Note Not Found",
                    systemImage: "note.text",
                    description: Text("This note may have been deleted.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Editor

    private func editor(for note: ResearchNote) -> some View {
        @Bindable var note = note

        return List {
            Section {
                if isEditing {
                    TextField("Title", text: $note.title, axis: .vertical)
                        .font(.headline)
                } else {
                    Text(note.displayTitle)
                        .font(.title3.weight(.semibold))
                }
            }

            Section("Note") {
                if isEditing {
                    TextEditor(text: $note.body)
                        .frame(minHeight: 260)
                } else if note.body.isEmpty {
                    Text("Nothing written yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(renderedBody(for: note))
                        .textSelection(.enabled)
                }
            }

            if isEditing {
                suggestionsSection(for: note)
            }

            relatedSection(note)
            relatedNotesSection(note)

            Section {
                Toggle("Favorite", isOn: $note.isFavorite)
                LabeledContent("Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(note.displayTitle)
        .environment(\.openURL, OpenURLAction { url in
            guard let route = AppRoute(linkURL: url) else { return .systemAction }
            router.push(route)
            return .handled
        })
        .onChange(of: note.title) { note.touch() }
        .onChange(of: note.body) { note.touch() }
        .onChange(of: note.isFavorite) { note.touch() }
        .onDisappear {
            analyze(note, syncing: true)
            modelContext.saveLoggingFailure()
        }
        .task(id: note.id) {
            modelContext.importLegacyLinks(for: note)
            modelContext.recordView(.note, id: note.id.uuidString, title: note.displayTitle)
            if !didChooseMode {
                // A new, empty note opens for writing; an existing one for reading.
                isEditing = note.body.isEmpty
                didChooseMode = true
            }
            analyze(note, syncing: true)
        }
        // Recognize links shortly after typing stops, not on every keystroke.
        .task(id: note.body) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            analyze(note, syncing: true)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsLinkPicker = true
                } label: {
                    Label("Add Link", systemImage: "link.badge.plus")
                }

                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                    if !isEditing {
                        analyze(note, syncing: true)
                        modelContext.saveLoggingFailure()
                    }
                }

                Menu {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsLinkPicker) {
            LinkPickerView(noteID: note.id)
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                modelContext.deleteReferences(forNote: note.id)
                modelContext.delete(note)
                modelContext.saveLoggingFailure()
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: Analysis

    /// Finds mentions in the note's current text and, when asked, brings the
    /// note's automatic links in line with them.
    private func analyze(_ note: ResearchNote, syncing: Bool) {
        let text = note.body
        let mentions = NoteLinker.mentions(in: text)
        analysis = Analysis(text: text, mentions: mentions)
        if syncing {
            modelContext.syncAutomaticReferences(noteID: note.id, mentions: mentions)
        }
    }

    /// Mentions for exactly this body. If the analysis is from an older
    /// version of the text, it is redone here rather than trusting indices
    /// that no longer line up.
    private func currentMentions(for body: String) -> [LinkMention] {
        analysis.text == body ? analysis.mentions : NoteLinker.mentions(in: body)
    }

    private func renderedBody(for note: ResearchNote) -> AttributedString {
        NoteRenderer.attributed(
            body: note.body,
            mentions: currentMentions(for: note.body),
            references: ownReferences,
            resolution: { kind, entityID in
                ReferenceResolver.resolution(kind: kind, entityID: entityID, in: store)
            }
        )
    }

    // MARK: Suggestions

    /// Things the note mentions that aren't linked yet. CVEs and repositories
    /// link themselves, so this is mostly technologies and products, plus any
    /// CVE or repository the user has unlinked and may want back.
    private func suggestions(for note: ResearchNote) -> [LinkMention] {
        let linked = Set(ownReferences.map { "\($0.kindRaw):\($0.entityID)" })
        let unique = NoteLinker.uniqueMentions(currentMentions(for: note.body))
        let open = unique.filter { !linked.contains($0.key) }
        // The newest text is what the user is working on, so offer it first.
        return Array(open.reversed().prefix(4))
    }

    @ViewBuilder
    private func suggestionsSection(for note: ResearchNote) -> some View {
        let items = suggestions(for: note)
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.key) { mention in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mention.displayName)
                                if let caption = suggestionCaption(for: mention) {
                                    Text(caption)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: mention.kind.systemImage)
                        }
                        Spacer()
                        Button("Link") {
                            modelContext.link(
                                noteID: note.id,
                                kind: mention.kind,
                                entityID: mention.entityID,
                                displayName: mention.displayName,
                                origin: .manual
                            )
                        }
                        .buttonStyle(.borderless)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Suggested Links")
            } footer: {
                Text("Pwned only links what you confirm. CVE identifiers and GitHub URLs link themselves.")
            }
        }
    }

    private func suggestionCaption(for mention: LinkMention) -> String? {
        let status = ReferenceResolver.resolution(kind: mention.kind, entityID: mention.entityID, in: store)
        var parts = [mention.kind.title]
        if let caption = status.caption { parts.append(caption) }
        return parts.joined(separator: " · ")
    }

    // MARK: Related research

    @ViewBuilder
    private func relatedSection(_ note: ResearchNote) -> some View {
        let grouped = Dictionary(grouping: ownReferences, by: \.kind)
        let linkedTopicIDs = Set(ownReferences.filter { $0.kind == .technology || $0.kind == .product }.map(\.entityID))
        let relatedConcepts = relatedConcepts(excluding: linkedTopicIDs)

        if !ownReferences.isEmpty {
            ForEach(ReferenceKind.allCases.sorted { $0.sortOrder < $1.sortOrder }, id: \.self) { kind in
                if let items = grouped[kind], !items.isEmpty {
                    Section(kind.groupTitle) {
                        ForEach(items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) { reference in
                            referenceRow(reference)
                        }
                    }
                }
            }
        }

        if !relatedConcepts.isEmpty {
            Section {
                ForEach(relatedConcepts) { topic in
                    NavigationLink(value: AppRoute.researchTopic(topic.id)) {
                        Label(topic.name, systemImage: topic.category.systemImage)
                    }
                }
            } header: {
                Text("Related Concepts")
            } footer: {
                Text("Topics connected to the ones you linked. Related is not the same: each is its own technology.")
            }
        }
    }

    @ViewBuilder
    private func referenceRow(_ reference: NoteReference) -> some View {
        let status = ReferenceResolver.resolution(kind: reference.kind, entityID: reference.entityID, in: store)
        let row = VStack(alignment: .leading, spacing: 2) {
            Label(reference.displayName, systemImage: reference.kind.systemImage)
            if let caption = status.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)

        Group {
            if let route = reference.route {
                NavigationLink(value: route) { row }
            } else {
                row
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.unlink(reference)
            } label: {
                Label("Remove Link", systemImage: "link.badge.minus")
            }
        }
    }

    /// Topics related to the note's linked topics that the note doesn't link
    /// itself, closest (most often named) first.
    private func relatedConcepts(excluding linked: Set<String>) -> [ResearchTopic] {
        var counts: [String: Int] = [:]
        for topicID in linked {
            guard let topic = ResearchCatalog.topic(withID: topicID) else { continue }
            for related in topic.related where !linked.contains(related) {
                counts[related, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key }
            .compactMap { ResearchCatalog.topic(withID: $0.key) }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private func relatedNotesSection(_ note: ResearchNote) -> some View {
        let shared = NoteBacklinks(references: allReferences, notes: allNotes)
            .notesSharingReferences(with: note.id, limit: 5)
        if !shared.isEmpty {
            Section {
                ForEach(shared, id: \.note.id) { entry in
                    NavigationLink(value: AppRoute.note(entry.note.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(entry.note.displayTitle, systemImage: "note.text")
                            Text("Shares \(entry.shared) \(entry.shared == 1 ? "link" : "links")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                Text("Related Notes")
            }
        }
    }
}
