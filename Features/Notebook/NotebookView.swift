import SwiftUI
import SwiftData

struct NotebookView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]

    @State private var searchText = ""

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.notebookPath) {
            List {
                if filtered.isEmpty {
                    Section { emptyState }
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { note in
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
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Notebook")
            .searchable(text: $searchText, prompt: "Title, text or tag")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNote) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
            .appRouteDestinations()
        }
    }

    private var filtered: [ResearchNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Notes are stored on this device and are never cleared with cached data.")
            } actions: {
                Button("New Note", action: createNote)
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func createNote() {
        let note = ResearchNote()
        modelContext.insert(note)
        modelContext.saveLoggingFailure()
        router.notebookPath.append(AppRoute.note(note.id))
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { filtered[$0] }
        for note in doomed { modelContext.delete(note) }
        modelContext.saveLoggingFailure()
    }
}

struct NoteRow: View {
    let note: ResearchNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .imageScale(.small)
                        .accessibilityLabel("Favorite")
                }
            }
            Text(note.body.isEmpty ? "No additional text" : note.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(note.modifiedAt.shortDateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
