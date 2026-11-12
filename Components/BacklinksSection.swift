import SwiftUI
import SwiftData

/// "Your Notes": the notes that link to a vulnerability, topic or repository.
/// Renders nothing when no note does, so pages stay quiet until the user has
/// written something relevant.
struct BacklinksSection: View {
    /// The kinds the target can be linked as. Catalog topics are either a
    /// technology or a product, so topic pages pass both.
    let kinds: [ReferenceKind]
    let entityID: String

    @Query private var references: [NoteReference]
    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]

    var body: some View {
        let linked = NoteBacklinks(references: references, notes: notes)
            .notes(kinds: kinds, entityID: entityID)

        if !linked.isEmpty {
            Section {
                ForEach(linked) { note in
                    NavigationLink(value: AppRoute.note(note.id)) {
                        Label(note.displayTitle, systemImage: "note.text")
                    }
                }
            } header: {
                Text("Your Notes")
            } footer: {
                Text("Notes that link here.")
            }
        }
    }
}
