import SwiftUI
import SwiftData

/// Universal search, hosted in the system search tab. Results are grouped by
/// what the query was recognized as, and tapping one jumps to its section.
struct UniversalSearchView: View {
    @Environment(IntelligenceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]
    @Query(sort: \SearchHistoryEntry.searchedAt, order: .reverse) private var history: [SearchHistoryEntry]

    @State private var searchText = ""

    private static let suggestions = ["CVE-2099-0001", "iOS 26.3", "SPTM", "arm64e", "CoreTrust"]

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    idleContent
                } else {
                    resultsContent
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "CVEs, components, repositories, notes")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(of: .search) {
                modelContext.recordSearch(trimmedQuery)
            }
        }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Idle

    @ViewBuilder
    private var idleContent: some View {
        Section {
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button {
                    searchText = suggestion
                } label: {
                    Label(suggestion, systemImage: "magnifyingglass")
                }
            }
        } header: {
            Text("Try")
        } footer: {
            Text("Search recognizes CVE identifiers, Apple platform versions, Apple components and GitHub repository URLs. CVE-2099-0001 is a sample record.")
        }

        if !history.isEmpty {
            Section {
                ForEach(history.prefix(8)) { entry in
                    Button {
                        searchText = entry.query
                    } label: {
                        Label(entry.query, systemImage: "clock")
                    }
                }
                Button("Clear Search History", role: .destructive, action: clearHistory)
            } header: {
                Text("Recent Searches")
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsContent: some View {
        let results = SearchEngine.results(
            for: trimmedQuery,
            vulnerabilities: store.vulnerabilities,
            notes: notes
        )
        let grouped = Dictionary(grouping: results, by: \.category)

        ForEach(SearchCategory.allCases) { category in
            if let items = grouped[category], !items.isEmpty {
                Section(category.title) {
                    ForEach(items) { result in
                        Button {
                            modelContext.recordSearch(trimmedQuery)
                            router.open(result.target)
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private func clearHistory() {
        for entry in history { modelContext.delete(entry) }
        modelContext.saveLoggingFailure()
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(.body)
                    if result.isSample {
                        Text("Sample")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
                Text(result.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
