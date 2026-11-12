import SwiftUI
import SwiftData

/// Apple security research feed and universal search.
///
/// The list shows only records the classifier judges to concern the Apple
/// ecosystem. Everything else the device has downloaded stays in the database
/// but is out of this list; records with weaker evidence are kept as
/// "uncertain" candidates and shown only when the user asks.
struct DiscoverView: View {
    @Environment(IntelligenceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.modelContext) private var modelContext

    @Query private var bookmarks: [VulnerabilityBookmark]
    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]
    @Query private var references: [NoteReference]

    @AppStorage(AppSettings.includeUncertainKey) private var includeUncertain = false

    @State private var searchText = ""
    @State private var bookmarkedOnly = false
    @State private var filter = VulnerabilityFilter()

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.discoverPath) {
            List {
                if trimmedSearch.isEmpty {
                    feedContent
                } else {
                    searchContent
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $searchText, prompt: "CVEs, Apple components, repositories, notes")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    filterMenu
                }
            }
            .onChange(of: router.pendingDiscoverQuery, initial: true) { _, pending in
                guard let pending else { return }
                searchText = pending
                router.pendingDiscoverQuery = nil
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

    /// The feed with the user's filters applied.
    private var visibleFeed: [Vulnerability] {
        filter.apply(
            to: store.feed(includingCandidates: includeUncertain),
            bookmarkedIDs: bookmarkedOnly ? bookmarkedIDs : nil,
            classifications: store.classifications
        )
    }

    // MARK: Feed

    @ViewBuilder
    private var feedContent: some View {
        statusSection
        exploreSection
        feedSection
        candidatesSection
        loadEarlierSection
    }

    @ViewBuilder
    private var statusSection: some View {
        let showsStatus = !connectivity.isOnline
            || store.refreshPhase != .idle
            || !store.refreshNotices.isEmpty
        if showsStatus {
            Section {
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
                        Text("Loading Apple security research from NVD…")
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

                ForEach(store.refreshNotices, id: \.self) { notice in
                    Label(notice, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var exploreSection: some View {
        Section("Explore") {
            NavigationLink(value: AppRoute.researchLibrary) {
                Label("Apple Research Center", systemImage: "books.vertical")
            }
            NavigationLink(value: AppRoute.openRepository) {
                Label("GitHub Repositories", systemImage: "shippingbox")
            }
            NavigationLink(value: AppRoute.laboratory) {
                Label("Laboratory", systemImage: "testtube.2")
            }
        }
    }

    @ViewBuilder
    private var feedSection: some View {
        let items = visibleFeed
        if items.isEmpty {
            emptyState
        } else {
            Section {
                ForEach(items) { vulnerability in
                    NavigationLink(value: AppRoute.vulnerability(vulnerability.id)) {
                        VulnerabilityRow(
                            vulnerability: vulnerability,
                            classification: store.classification(for: vulnerability.id)
                        )
                    }
                }
            } header: {
                Text(feedHeader(for: items))
            } footer: {
                Text(store.vulnerabilityState.summary)
            }
        }
    }

    private func feedHeader(for items: [Vulnerability]) -> String {
        if filter.isNarrowing || bookmarkedOnly {
            let total = store.feed(includingCandidates: includeUncertain).count
            return "\(items.count.formatted()) of \(total.formatted()) Apple records"
        }
        return items.countLabel(singular: "Apple Vulnerability", plural: "Apple Vulnerabilities")
    }

    @ViewBuilder
    private var emptyState: some View {
        Section {
            if store.refreshPhase == .loading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
            } else if filter.isNarrowing {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No Apple records match the current filters.")
                } actions: {
                    Button("Reset Filters") { filter = VulnerabilityFilter() }
                }
            } else if !connectivity.isOnline {
                ContentUnavailableView(
                    "Nothing Saved Yet",
                    systemImage: "wifi.slash",
                    description: Text("Connect to the internet and pull down to load Apple security research from NVD.")
                )
            } else {
                ContentUnavailableView(
                    "No Apple Research Yet",
                    systemImage: "tray",
                    description: Text("Pull down to load Apple security research from NVD.")
                )
            }
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var candidatesSection: some View {
        if !includeUncertain, !store.candidates.isEmpty {
            Section {
                NavigationLink(value: AppRoute.candidates) {
                    LabeledContent("Needs Review", value: store.candidates.count.formatted())
                }
            } footer: {
                Text("These records mention Apple but don't have enough evidence to be listed as Apple vulnerabilities.")
            }
        }
    }

    @ViewBuilder
    private var loadEarlierSection: some View {
        if store.canLoadEarlier {
            Section {
                Button {
                    Task { await store.loadEarlier() }
                } label: {
                    HStack {
                        Label("Load Earlier Records", systemImage: "clock.arrow.circlepath")
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
                Text("Loads the previous 30 days of Apple publications from NVD.")
            }
        }
    }

    // MARK: Search

    @ViewBuilder
    private var searchContent: some View {
        let term = trimmedSearch
        let results = SearchEngine.results(
            for: term,
            feed: store.feed(includingCandidates: true),
            known: store.vulnerabilities,
            notes: notes,
            references: references
        )
        let grouped = Dictionary(grouping: results, by: \.category)

        ForEach(SearchCategory.allCases) { category in
            if let items = grouped[category], !items.isEmpty {
                Section(category.title) {
                    ForEach(items) { result in
                        Button {
                            modelContext.recordSearch(term)
                            router.open(result.target)
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }

        nvdSearchSection(term)
        otherMatchesSection(term)
    }

    @ViewBuilder
    private func nvdSearchSection(_ term: String) -> some View {
        if store.hasNetworkService, SearchClassifier.normalizedCVE(term) == nil {
            Section {
                if let search = store.keywordSearch,
                   search.keyword.caseInsensitiveCompare(term) == .orderedSame {
                    keywordSearchStatus(search, term: term)
                } else {
                    Button {
                        Task { await store.searchNVD(term) }
                    } label: {
                        Label("Search All of NVD for “\(term)”", systemImage: "globe")
                    }
                    .disabled(!connectivity.isOnline)
                }
            } footer: {
                Text("Searches every vulnerability in NVD, not just Apple's. Results are saved on this device and shown below.")
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

    /// After an explicit NVD search, shows the saved matches that the Apple
    /// feed doesn't list, labelled with what the classifier made of them.
    @ViewBuilder
    private func otherMatchesSection(_ term: String) -> some View {
        if let search = store.keywordSearch,
           search.keyword.caseInsensitiveCompare(term) == .orderedSame,
           !search.isLoading {
            let appleIDs = Set(store.feed(includingCandidates: true).map { $0.id.uppercased() })
            let others = store.vulnerabilities.filter { record in
                !appleIDs.contains(record.id.uppercased()) && record.matches(searchText: term)
            }
            if !others.isEmpty {
                Section {
                    ForEach(others.prefix(40)) { record in
                        NavigationLink(value: AppRoute.vulnerability(record.id)) {
                            VulnerabilityRow(
                                vulnerability: record,
                                classification: store.classification(for: record.id),
                                showsNonApple: true
                            )
                        }
                    }
                } header: {
                    Text("Other NVD Matches")
                } footer: {
                    Text("Saved from your NVD search. These aren't in the Apple feed.")
                }
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

            Section("Platform") {
                ForEach(ApplePlatform.allCases) { platform in
                    Button {
                        toggle(platform)
                    } label: {
                        if filter.platforms.contains(platform) {
                            Label(platform.title, systemImage: "checkmark")
                        } else {
                            Text(platform.title)
                        }
                    }
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
            Toggle("Bookmarked Only", isOn: $bookmarkedOnly)
            Toggle("Include Uncertain Matches", isOn: $includeUncertain)

            if filter.isActive || bookmarkedOnly {
                Button("Reset Filters", role: .destructive) {
                    filter = VulnerabilityFilter()
                    bookmarkedOnly = false
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: (filter.isNarrowing || bookmarkedOnly)
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

    private func toggle(_ platform: ApplePlatform) {
        if filter.platforms.contains(platform) {
            filter.platforms.remove(platform)
        } else {
            filter.platforms.insert(platform)
        }
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
                Text(result.title)
                    .font(.body)
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
