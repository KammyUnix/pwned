import SwiftUI
import SwiftData

/// A catalog topic: what it is called, how it relates to other topics, which
/// vulnerabilities on this device concern it, and what the user has written.
///
/// The page makes no claims of its own about the technology. Everything beyond
/// the catalog entry is derived from data the user can inspect: classified
/// vulnerability records, linked repositories and the user's own notes.
struct ResearchTopicView: View {
    let topicID: String

    @Environment(AppRouter.self) private var router
    @Environment(IntelligenceStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<NoteReference> { $0.isDismissed == false }) private var references: [NoteReference]
    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]

    private static let vulnerabilityLimit = 5

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
        let backlinks = NoteBacklinks(references: references, notes: notes)
        let kind = ReferenceKind.kind(for: topic)

        return List {
            Section {
                LabeledContent("Category", value: topic.category.title)
                LabeledContent("Type", value: kind.title)
                if !topic.aliases.isEmpty {
                    LabeledContent("Also Known As", value: topic.aliases.joined(separator: ", "))
                }
            }

            Section {
                Label("Pwned has not written research content for this topic yet. This page shows what connects to it: related topics, vulnerabilities on this device and your own notes.",
                      systemImage: "doc.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            relatedConceptsSection(for: topic)
            vulnerabilitiesSection(for: topic)
            repositoriesSection(for: topic, backlinks: backlinks)
            BacklinksSection(kinds: ReferenceKind.catalogKinds, entityID: topic.id)

            Section {
                Button {
                    startNote(about: topic, kind: kind)
                } label: {
                    Label("New Note About \(topic.name)", systemImage: "square.and.pencil")
                }
            }
        }
    }

    // MARK: Related concepts

    @ViewBuilder
    private func relatedConceptsSection(for topic: ResearchTopic) -> some View {
        let related = ResearchCatalog.relatedTopics(of: topic)
        if !related.isEmpty {
            Section {
                ForEach(related) { other in
                    NavigationLink(value: AppRoute.researchTopic(other.id)) {
                        Label(other.name, systemImage: other.category.systemImage)
                    }
                }
            } header: {
                Text("Related Concepts")
            } footer: {
                Text("Related is not the same as identical: each of these is its own technology.")
            }
        }
    }

    // MARK: Vulnerabilities

    @ViewBuilder
    private func vulnerabilitiesSection(for topic: ResearchTopic) -> some View {
        let records = store.appleVulnerabilities(forTopic: topic.id)
        Section {
            ForEach(records.prefix(Self.vulnerabilityLimit)) { record in
                NavigationLink(value: AppRoute.vulnerability(record.id)) {
                    VulnerabilityRow(vulnerability: record, classification: store.classification(for: record.id))
                }
            }

            if records.isEmpty {
                Text("No Apple vulnerability on this device is tagged with \(topic.name).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                router.open(.vulnerabilityQuery(topic.name))
            } label: {
                Label("Search Vulnerabilities for “\(topic.name)”", systemImage: "magnifyingglass")
            }
        } header: {
            Text("Vulnerabilities")
        } footer: {
            if records.count > Self.vulnerabilityLimit {
                Text("Showing \(Self.vulnerabilityLimit) of \(records.count). Search lists the rest.")
            } else if !records.isEmpty {
                Text("Matched from each record's affected products and description. A match is not proof the technology is the root cause.")
            }
        }
    }

    // MARK: Repositories

    @ViewBuilder
    private func repositoriesSection(for topic: ResearchTopic, backlinks: NoteBacklinks) -> some View {
        let repositories = backlinks.repositoryIDs(alongsideTopic: topic.id)
            .compactMap { AppRoute(kind: .repository, entityID: $0) }
        if !repositories.isEmpty {
            Section {
                ForEach(repositories, id: \.self) { route in
                    if case .repository(let reference) = route {
                        NavigationLink(value: route) {
                            Label(reference.fullName, systemImage: ReferenceKind.repository.systemImage)
                        }
                    }
                }
            } header: {
                Text("Repositories")
            } footer: {
                Text("Repositories from your notes that also link to \(topic.name).")
            }
        }
    }

    // MARK: Notes

    private func startNote(about topic: ResearchTopic, kind: ReferenceKind) {
        let note = ResearchNote(title: topic.name)
        modelContext.insert(note)
        modelContext.link(
            noteID: note.id,
            kind: kind,
            entityID: topic.id,
            displayName: topic.name,
            origin: .manual
        )
        modelContext.saveLoggingFailure()
        router.push(.note(note.id))
    }
}
