import SwiftUI
import SwiftData

struct ResearchTopicView: View {
    let topicID: String

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]

    var body: some View {
        Group {
            if let topic = ResearchCatalog.topic(withID: topicID) {
                content(for: topic)
                    .navigationTitle(topic.name)
                    .task(id: topicID) {
                        modelContext.recordView(.researchTopic, id: topic.id, title: topic.name)
                    }
            } else {
                ContentUnavailableView(
                    "Topic Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("This topic isn't in the research catalog.")
                )
                .navigationTitle("Apple Research")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for topic: ResearchTopic) -> some View {
        List {
            Section {
                LabeledContent("Category", value: topic.category.title)
                if !topic.aliases.isEmpty {
                    LabeledContent("Also Known As", value: topic.aliases.joined(separator: ", "))
                }
            }

            Section {
                Label("No research content has been written for this topic yet. Overview, technical explanation and references arrive in Phase 4.",
                      systemImage: "doc.text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Cross-References") {
                Button {
                    router.open(.vulnerabilityQuery(topic.name))
                } label: {
                    Label("Search Vulnerabilities for “\(topic.name)”", systemImage: "exclamationmark.shield")
                }
            }

            let related = notes.filter { $0.relatedTopicIDs.contains(topic.id) }
            Section("Research Notes") {
                if related.isEmpty {
                    Text("No notes reference this topic.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(related) { note in
                        NavigationLink(value: AppRoute.note(note.id)) {
                            Text(note.displayTitle)
                        }
                    }
                }
            }
        }
    }
}
