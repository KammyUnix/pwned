import SwiftUI
import SwiftData

/// Everything the user has kept: notes, bookmarked vulnerabilities and
/// repositories, and what they opened recently. All of it lives in the
/// on-device SwiftData store and is never touched by "Clear Cached Data".
struct SavedView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case notes = "Notes"
        case vulnerabilities = "Vulnerabilities"
        case repositories = "Repositories"
        case recent = "Recent"

        var id: String { rawValue }
    }

    @Environment(IntelligenceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]
    @Query private var references: [NoteReference]
    @Query(sort: \VulnerabilityBookmark.createdAt, order: .reverse) private var vulnerabilityBookmarks: [VulnerabilityBookmark]
    @Query(sort: \RepositoryBookmark.createdAt, order: .reverse) private var repositoryBookmarks: [RepositoryBookmark]
    @Query(sort: \ViewedItem.viewedAt, order: .reverse) private var viewedItems: [ViewedItem]

    @State private var pane: Pane = .notes
    @State private var searchText = ""

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.savedPath) {
            List {
                Section {
                    Picker("Show", selection: $pane) {
                        ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                switch pane {
                case .notes: notesContent
                case .vulnerabilities: vulnerabilitiesContent
                case .repositories: repositoriesContent
                case .recent: recentContent
                }
            }
            .navigationTitle("Saved")
            .searchable(text: $searchText, prompt: "Notes, CVEs, technologies, repositories")
            .toolbar {
                if pane == .notes {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: createNote) {
                            Label("New Note", systemImage: "square.and.pencil")
                        }
                    }
                }
            }
            .appRouteDestinations()
        }
    }

    // MARK: Notes

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredNotes: [ResearchNote] {
        guard !trimmedSearch.isEmpty else { return notes }
        return SearchEngine.noteMatches(for: trimmedSearch, in: notes, references: references)
    }

    @ViewBuilder
    private var notesContent: some View {
        let items = filteredNotes
        if items.isEmpty {
            Section {
                if trimmedSearch.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Write about a CVE, BootROM or a repository and Pwned links it to your research. Notes stay on this device.")
                    } actions: {
                        Button("New Note", action: createNote)
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(items) { note in
                    NavigationLink(value: AppRoute.note(note.id)) {
                        NoteRow(note: note)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            note.isFavorite.toggle()
                            modelContext.saveLoggingFailure()
                        } label: {
                            Label(note.isFavorite ? "Unfavorite" : "Favorite",
                                  systemImage: note.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
                .onDelete { offsets in
                    delete(offsets.map { items[$0] })
                }
            }
        }
    }

    private func createNote() {
        let note = ResearchNote()
        modelContext.insert(note)
        modelContext.saveLoggingFailure()
        router.savedPath.append(AppRoute.note(note.id))
    }

    private func delete(_ doomed: [ResearchNote]) {
        for note in doomed {
            modelContext.deleteReferences(forNote: note.id)
            modelContext.delete(note)
        }
        modelContext.saveLoggingFailure()
    }

    // MARK: Bookmarks

    @ViewBuilder
    private var vulnerabilitiesContent: some View {
        Section {
            if vulnerabilityBookmarks.isEmpty {
                Text("Bookmark a vulnerability from its page to keep it here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vulnerabilityBookmarks) { bookmark in
                    NavigationLink(value: AppRoute.vulnerability(bookmark.cveID)) {
                        if let vulnerability = store.vulnerability(id: bookmark.cveID) {
                            VulnerabilityRow(
                                vulnerability: vulnerability,
                                classification: store.classification(for: vulnerability.id)
                            )
                        } else {
                            Label(bookmark.cveID, systemImage: "bookmark")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var repositoriesContent: some View {
        Section {
            if repositoryBookmarks.isEmpty {
                Text("Bookmark a repository from its page to keep it here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(repositoryBookmarks) { bookmark in
                    NavigationLink(value: AppRoute.repository(bookmark.reference)) {
                        Label(bookmark.fullName, systemImage: "bookmark")
                    }
                }
            }
        }
    }

    // MARK: Recent

    @ViewBuilder
    private var recentContent: some View {
        Section {
            if viewedItems.isEmpty {
                Text("Items you open appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewedItems.prefix(30)) { item in
                    if let route = item.route {
                        NavigationLink(value: route) {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
            }
        }
    }
}
