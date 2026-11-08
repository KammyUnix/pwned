import SwiftUI
import SwiftData

struct VulnerabilitiesView: View {
    @Environment(IntelligenceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Query private var bookmarks: [VulnerabilityBookmark]

    @State private var searchText = ""
    @State private var bookmarkedOnly = false

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.vulnerabilitiesPath) {
            List {
                if store.isShowingSampleData {
                    Section { SampleDataNotice() }
                }

                if filtered.isEmpty {
                    emptyState
                } else {
                    Section {
                        ForEach(filtered) { vulnerability in
                            NavigationLink(value: AppRoute.vulnerability(vulnerability.id)) {
                                VulnerabilityRow(vulnerability: vulnerability)
                            }
                        }
                    } header: {
                        Text(filtered.countLabel(singular: "Vulnerability", plural: "Vulnerabilities"))
                    }
                }
            }
            .navigationTitle("Vulnerabilities")
            .searchable(text: $searchText, prompt: "CVE ID, product or keyword")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $bookmarkedOnly) {
                        Label("Bookmarked Only", systemImage: bookmarkedOnly ? "bookmark.fill" : "bookmark")
                    }
                    .toggleStyle(.button)
                }
            }
            .onChange(of: router.pendingVulnerabilityQuery, initial: true) { _, pending in
                guard let pending else { return }
                searchText = pending
                router.pendingVulnerabilityQuery = nil
            }
            .appRouteDestinations()
        }
    }

    private var bookmarkedIDs: Set<String> {
        Set(bookmarks.map { $0.cveID.uppercased() })
    }

    private var filtered: [Vulnerability] {
        store.recentVulnerabilities.filter { vulnerability in
            (!bookmarkedOnly || bookmarkedIDs.contains(vulnerability.id.uppercased()))
                && vulnerability.matches(searchText: searchText)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Section {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if bookmarkedOnly {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Bookmark a vulnerability from its detail page to find it here.")
                )
            } else {
                ContentUnavailableView(
                    "No Vulnerabilities",
                    systemImage: "tray",
                    description: Text("No vulnerability records are available yet.")
                )
            }
        }
        .listRowBackground(Color.clear)
    }
}
