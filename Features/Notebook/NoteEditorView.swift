import SwiftUI
import SwiftData

/// Plain-text note editor. Markdown rendering, tags, attachments and
/// cross-reference editing are added in Phase 6.
struct NoteEditorView: View {
    let noteID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [ResearchNote]
    @State private var confirmsDelete = false

    init(noteID: UUID) {
        self.noteID = noteID
        _matches = Query(filter: #Predicate<ResearchNote> { $0.id == noteID })
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

    private func editor(for note: ResearchNote) -> some View {
        @Bindable var note = note

        return Form {
            Section {
                TextField("Title", text: $note.title, axis: .vertical)
                    .font(.headline)
            }

            Section("Note") {
                TextEditor(text: $note.body)
                    .frame(minHeight: 280)
            }

            Section {
                Toggle("Favorite", isOn: $note.isFavorite)
                LabeledContent("Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(note.displayTitle)
        .onChange(of: note.title) { note.touch() }
        .onChange(of: note.body) { note.touch() }
        .onChange(of: note.isFavorite) { note.touch() }
        .onDisappear { modelContext.saveLoggingFailure() }
        .task(id: note.id) {
            modelContext.recordView(.note, id: note.id.uuidString, title: note.displayTitle)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                modelContext.delete(note)
                modelContext.saveLoggingFailure()
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}
