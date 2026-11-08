import SwiftUI

/// Browsable catalog of Apple platform and security topics.
///
/// Phase 1 provides the catalog structure only. Written research content,
/// cross-references and source classification are added in Phase 4.
struct ResearchLibraryView: View {
    @State private var searchText = ""

    var body: some View {
        List {
            if trimmedSearch.isEmpty {
                ForEach(ResearchCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(ResearchCatalog.topics(in: category)) { topic in
                            row(for: topic)
                        }
                    }
                }
                Section {
                    Label("Topic pages list names and aliases only. Written research is added in a later phase.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                let matches = ResearchCatalog.topics(matching: trimmedSearch)
                if matches.isEmpty {
                    ContentUnavailableView.search(text: trimmedSearch)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(matches) { row(for: $0) }
                    }
                }
            }
        }
        .navigationTitle("Apple Research")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Components and technologies")
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func row(for topic: ResearchTopic) -> some View {
        NavigationLink(value: AppRoute.researchTopic(topic.id)) {
            Label(topic.name, systemImage: topic.category.systemImage)
        }
    }
}
