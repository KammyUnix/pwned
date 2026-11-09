import SwiftUI
import SwiftData

struct VulnerabilitiesView: View {
    @Environment(IntelligenceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Query private var bookmarks: [VulnerabilityBookmark]

    @State private var searchText = ""
    @State private var bookmarkedOnly = false
    @State private var filter = VulnerabilityFilter()

    var body: some View {
        @Bindable var router = router
        let items = filtered

        NavigationStack(path: $router.vulnerabilitiesPath) {
            List {
                statusSection
                nvdSearchSection
                resultsSection(items)
                loadEarlierSection
            }
            .navigationTitle("Vulnerabilities")
            .searchable(text: $searchText, prompt: "CVE ID, product or keyword")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    filterMenu
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

    // MARK: Data

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bookmarkedIDs: Set<String> {
        Set(bookmarks.map { $0.cveID.uppercased() })
    }

    private var filtered: [Vulnerability] {
        filter.apply(
            to: store.recentVulnerabilities,
            searchText: searchText,
            bookmarkedIDs: bookmarkedOnly ? bookmarkedIDs : nil
        )
    }

    private var isRestrictingResults: Bool {
        !trimmedSearch.isEmpty || filter.isNarrowing || bookmarkedOnly
    }

    // MARK: Status

    @ViewBuilder
    private var statusSection: some View {
        if store.isShowingSampleVulnerabilities || !connectivity.isOnline || store.refreshPhase != .idle {
            Section {
                if store.isShowingSampleVulnerabilities {
                    SampleDataNotice(
                        message: "These vulnerability records are built-in samples, not real intelligence. Pull down to load live records from NVD."
                    )
                }

                if !connectivity.isOnline {
                    Label("Offline. Showing data saved on this device.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }

                switch store.refreshPhase {
                case .idle:
                    EmptyView()
                case .loading:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading from NVD…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle")
                        Button("Try Again") {
                            Task { await store.refresh() }
                        }
                    }
                }
            }
        }
    }

    // MARK: Search NVD

    @ViewBuilder
    private var nvdSearchSection: some View {
        let term = trimmedSearch
        if store.hasNetworkService, !term.isEmpty {
            Section {
                if let cve = SearchClassifier.normalizedCVE(term) {
                    NavigationLink(value: AppRoute.vulnerability(cve)) {
                        Label("Open \(cve)", systemImage: "arrow.up.right.square")
                    }
                } else if let search = store.keywordSearch,
                          search.keyword.caseInsensitiveCompare(term) == .orderedSame {
                    keywordSearchStatus(search, term: term)
                } else {
                    Button {
                        Task { await store.searchNVD(term) }
                    } label: {
                        Label("Search NVD for “\(term)”", systemImage: "globe")
                    }
                    .disabled(!connectivity.isOnline)
                }
            } footer: {
                if SearchClassifier.normalizedCVE(term) == nil {
                    Text("Searches descriptions in the NVD database. Results are saved on this device.")
                }
            }
        }
    }

    @ViewBuilder
    private func keywordSearchStatus(_ search: KeywordSearchState, term: String) -> some View {
        if search.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Searching NVD…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let error = search.error {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.triangle")
                Button("Try Again") {
                    Task { await store.searchNVD(term) }
                }
            }
        } else {
            Label(
                "\(search.totalResults.formatted()) \(search.totalResults == 1 ? "match" : "matches") on NVD",
                systemImage: "globe"
            )
            if search.remaining > 0 {
                Button {
                    Task { await store.loadMoreKeywordResults() }
                } label: {
                    Label("Load Earlier Matches (\(search.remaining.formatted()) remaining)",
                          systemImage: "arrow.down.circle")
                }
                .disabled(!connectivity.isOnline)
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func resultsSection(_ items: [Vulnerability]) -> some View {
        if items.isEmpty {
            emptyState
        } else {
            Section {
                ForEach(items) { vulnerability in
                    NavigationLink(value: AppRoute.vulnerability(vulnerability.id)) {
                        VulnerabilityRow(vulnerability: vulnerability)
                    }
                }
            } header: {
                if isRestrictingResults {
                    Text("\(items.count.formatted()) of \(store.recentVulnerabilities.count.formatted()) loaded")
                } else {
                    Text(items.countLabel(singular: "Vulnerability", plural: "Vulnerabilities"))
                }
            } footer: {
                Text(store.vulnerabilityState.summary)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Section {
            if store.refreshPhase == .loading && store.recentVulnerabilities.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
            } else if !trimmedSearch.isEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
            } else if filter.isNarrowing {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No loaded vulnerabilities match the current filters.")
                } actions: {
                    Button("Reset Filters") { filter = VulnerabilityFilter() }
                }
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
                    description: Text("Pull down to load the latest records from NVD.")
                )
            }
        }
        .listRowBackground(Color.clear)
    }

    // MARK: Pagination

    @ViewBuilder
    private var loadEarlierSection: some View {
        if store.canLoadEarlier, trimmedSearch.isEmpty, !bookmarkedOnly, !store.isShowingSampleVulnerabilities {
            Section {
                Button {
                    Task { await store.loadEarlier() }
                } label: {
                    HStack {
                        Label("Load Earlier Vulnerabilities", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        if store.isLoadingEarlier {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isLoadingEarlier || !connectivity.isOnline)

                if let error = store.earlierError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Loads the previous 24 hours of publications from NVD.")
            }
        }
    }

    // MARK: Filter menu

    private var filterMenu: some View {
        Menu {
            Picker("Sort By", selection: $filter.sort) {
                ForEach(VulnerabilitySort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }

            Section("Severity") {
                ForEach(Severity.filterOptions) { severity in
                    Button {
                        toggle(severity)
                    } label: {
                        if filter.severities.contains(severity) {
                            Label(severity.title, systemImage: "checkmark")
                        } else {
                            Text(severity.title)
                        }
                    }
                }
            }

            Toggle("Known Exploited Only", isOn: $filter.knownExploitedOnly)

            if filter.isActive {
                Button("Reset Filters", role: .destructive) {
                    filter = VulnerabilityFilter()
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: filter.isNarrowing
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private func toggle(_ severity: Severity) {
        if filter.severities.contains(severity) {
            filter.severities.remove(severity)
        } else {
            filter.severities.insert(severity)
        }
    }
}
