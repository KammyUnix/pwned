import Foundation
import Observation

/// Where the data currently shown came from.
enum DataSourceState: Equatable {
    /// Nothing has been loaded on this device yet. Never filled with made-up data.
    case empty
    /// Records saved on this device. `lastUpdated` is when they were last refreshed from the network.
    case cached(lastUpdated: Date?)
    /// Fetched from the network during this session.
    case live(lastUpdated: Date)
}

/// Progress of the main feed refresh.
enum RefreshPhase: Equatable {
    case idle
    case loading
    case failed(String)
}

/// Progress of looking up one CVE that isn't stored locally.
enum LookupState: Equatable {
    case loading
    case notFound
    case failed(String)
}

/// Progress of the current "Search NVD" request.
struct KeywordSearchState: Equatable {
    var keyword: String
    var totalResults: Int
    /// Matches not yet fetched; 0 when everything has been loaded.
    var remaining: Int
    var isLoading = false
    var error: String?
}

/// Single source of truth for vulnerability intelligence shown across the app.
///
/// Two layers are kept apart on purpose:
///
/// * **Broad ingestion.** `vulnerabilities` holds every record the device knows
///   about: the Apple-focused feed, CVEs opened from a note, keyword search
///   results. Nothing is thrown away just because it isn't Apple's.
/// * **The Apple feed.** `appleFeed` is the subset the classifier judges to
///   concern the Apple ecosystem. Discover shows this; records with weaker
///   evidence are kept as `candidates` rather than discarded.
///
/// Records come from the on-disk cache and the NVD API only. When neither has
/// anything, the store is empty. It never substitutes sample data; that lives
/// in `SampleData`, reachable only from the Info tab's development data screen.
@MainActor
@Observable
final class IntelligenceStore {
    // MARK: Records

    /// Every known record, newest publication first.
    private(set) var vulnerabilities: [Vulnerability] = []
    /// Apple relevance for each record, keyed by upper-cased CVE ID.
    private(set) var classifications: [String: AppleClassification] = [:]
    /// Records judged likely or confirmed to concern Apple, newest first.
    private(set) var appleFeed: [Vulnerability] = []
    /// Records with some Apple evidence that isn't enough to call them Apple's.
    private(set) var candidates: [Vulnerability] = []

    private(set) var vulnerabilityState: DataSourceState = .empty
    private(set) var refreshPhase: RefreshPhase = .idle
    /// Notes about parts of the last refresh that didn't complete.
    private(set) var refreshNotices: [String] = []
    private(set) var isLoadingEarlier = false
    private(set) var canLoadEarlier = false
    private(set) var earlierError: String?
    private(set) var keywordSearch: KeywordSearchState?
    private(set) var lookups: [String: LookupState] = [:]
    private(set) var cacheRecordCount = 0
    private(set) var cacheSizeBytes: Int64 = 0
    private var recordsByID: [String: Vulnerability] = [:]

    private let service: VulnerabilityService?
    @ObservationIgnored private var feedOldest: Date?
    @ObservationIgnored private var lastRefreshed: Date?
    @ObservationIgnored private var hasStarted = false

    /// NVD asks clients not to poll aggressively, so an automatic refresh only
    /// happens when the data is older than this. Pull to refresh overrides it.
    private static let staleInterval: TimeInterval = 2 * 60 * 60
    /// Apple publishes security content in bursts weeks apart, so the feed
    /// window is a month rather than a day.
    private static let windowLength: TimeInterval = 30 * 24 * 60 * 60

    /// - Parameter service: Pass `VulnerabilityService.live()` for network and
    ///   cache access. With `nil` (previews, tests) the store serves `vulnerabilities` only.
    init(
        vulnerabilities: [Vulnerability] = [],
        state: DataSourceState = .empty,
        service: VulnerabilityService? = nil
    ) {
        self.service = service
        merge(vulnerabilities, classifications: AppleClassifier.classify(vulnerabilities), state: state)
    }

    // MARK: Derived data

    var hasNetworkService: Bool { service != nil }

    func classification(for id: String) -> AppleClassification? {
        classifications[id.uppercased()]
    }

    func vulnerability(id: String) -> Vulnerability? {
        recordsByID[id.uppercased()]
    }

    func vulnerabilities(withIDs ids: [String]) -> [Vulnerability] {
        ids.compactMap { vulnerability(id: $0) }
    }

    /// The Discover feed: Apple-focused records, plus the uncertain candidates
    /// when the user has chosen to include them.
    func feed(includingCandidates: Bool) -> [Vulnerability] {
        guard includingCandidates else { return appleFeed }
        return (appleFeed + candidates).sorted(by: VulnerabilityFilter.newestPublishedFirst)
    }

    /// Apple-focused records that concern a research topic: an operating system
    /// (by platform) or a component the classifier tagged.
    func appleVulnerabilities(forTopic topicID: String) -> [Vulnerability] {
        appleFeed.filter { record in
            guard let classification = classifications[record.id.uppercased()] else { return false }
            if classification.componentIDs.contains(topicID) { return true }
            return classification.platforms.contains { $0.rawValue.lowercased() == topicID }
        }
    }

    /// Other loaded records that list the same vendor and product as `vulnerability`'s first affected product.
    func vulnerabilities(sharingProductWith vulnerability: Vulnerability, limit: Int = 5) -> [Vulnerability] {
        guard let product = vulnerability.affectedProducts.first else { return [] }
        let matches = vulnerabilities.filter { other in
            other.id != vulnerability.id && other.affectedProducts.contains {
                $0.vendor.caseInsensitiveCompare(product.vendor) == .orderedSame
                    && $0.product.caseInsensitiveCompare(product.product) == .orderedSame
            }
        }
        return Array(matches.prefix(limit))
    }

    func lookupState(for id: String) -> LookupState? {
        lookups[id.uppercased()]
    }

    // MARK: Lifecycle

    /// Loads saved records, then refreshes from NVD if they are stale. Safe to call repeatedly.
    func start() async {
        guard let service, !hasStarted else { return }
        hasStarted = true

        let cached = await service.cachedContents()
        if !cached.vulnerabilities.isEmpty {
            lastRefreshed = cached.lastRefreshed
            await adopt(cached.vulnerabilities, as: .cached(lastUpdated: cached.lastRefreshed))
        }
        await updateCacheStatistics()
        await refreshIfStale()
    }

    func refreshIfStale() async {
        guard service != nil else { return }
        if let lastRefreshed, Date().timeIntervalSince(lastRefreshed) < Self.staleInterval {
            return
        }
        await refresh()
    }

    // MARK: Feed

    /// Fetches the Apple-focused CVEs published in the last 30 days.
    func refresh() async {
        guard let service, refreshPhase != .loading else { return }
        refreshPhase = .loading
        refreshNotices = []

        let end = Date()
        let start = end.addingTimeInterval(-Self.windowLength)
        do {
            let result = try await service.fetchAppleFeed(from: start, to: end, markRefreshed: true)
            await adopt(result.vulnerabilities, as: .live(lastUpdated: end))
            feedOldest = start
            canLoadEarlier = true
            if result.isComplete {
                lastRefreshed = end
            }
            refreshNotices = result.notices
            refreshPhase = .idle
        } catch {
            let mapped = NetworkError.map(error)
            refreshPhase = (mapped == .cancelled) ? .idle : .failed(mapped.localizedDescription)
        }
        await updateCacheStatistics()
    }

    /// Fetches the 30 days before the oldest window loaded so far.
    func loadEarlier() async {
        guard let service, let oldest = feedOldest, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        earlierError = nil
        defer { isLoadingEarlier = false }

        let start = oldest.addingTimeInterval(-Self.windowLength)
        do {
            let result = try await service.fetchAppleFeed(from: start, to: oldest, markRefreshed: false)
            await adopt(result.vulnerabilities, as: vulnerabilityState)
            if result.isComplete {
                feedOldest = start
            }
            earlierError = result.notices.first
        } catch {
            let mapped = NetworkError.map(error)
            earlierError = (mapped == .cancelled) ? nil : mapped.localizedDescription
        }
        await updateCacheStatistics()
    }

    // MARK: Keyword search on NVD

    func searchNVD(_ keyword: String) async {
        guard let service else { return }
        let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        keywordSearch = KeywordSearchState(keyword: term, totalResults: 0, remaining: 0, isLoading: true)
        do {
            let slice = try await service.startKeywordSearch(term)
            await adopt(slice.vulnerabilities, as: stateAfterNetworkFetch())
            keywordSearch = KeywordSearchState(keyword: term, totalResults: slice.totalResults, remaining: slice.remaining)
        } catch {
            let mapped = NetworkError.map(error)
            if mapped == .cancelled {
                keywordSearch = nil
            } else {
                keywordSearch = KeywordSearchState(
                    keyword: term, totalResults: 0, remaining: 0, error: mapped.localizedDescription
                )
            }
        }
        await updateCacheStatistics()
    }

    func loadMoreKeywordResults() async {
        guard let service, var search = keywordSearch, search.remaining > 0, !search.isLoading else { return }
        search.isLoading = true
        search.error = nil
        keywordSearch = search

        do {
            let slice = try await service.nextKeywordSlice(
                search.keyword, end: search.remaining, totalResults: search.totalResults
            )
            await adopt(slice.vulnerabilities, as: stateAfterNetworkFetch())
            keywordSearch = KeywordSearchState(
                keyword: search.keyword, totalResults: slice.totalResults, remaining: slice.remaining
            )
        } catch {
            let mapped = NetworkError.map(error)
            search.isLoading = false
            search.error = (mapped == .cancelled) ? nil : mapped.localizedDescription
            keywordSearch = search
        }
        await updateCacheStatistics()
    }

    // MARK: Single record

    /// Fetches one CVE from NVD if it isn't stored locally (or `force` is set).
    func lookup(cveID: String, force: Bool = false) async {
        let key = cveID.uppercased()
        guard let service, SearchClassifier.normalizedCVE(key) != nil else { return }
        if !force {
            if recordsByID[key] != nil { return }
            if lookups[key] == .notFound { return }
        }
        if lookups[key] == .loading { return }

        lookups[key] = .loading
        do {
            if let record = try await service.lookup(cveID: key) {
                await adopt([record], as: stateAfterNetworkFetch())
                lookups[key] = nil
            } else {
                lookups[key] = .notFound
            }
        } catch {
            let mapped = NetworkError.map(error)
            if mapped == .cancelled {
                lookups[key] = nil
            } else {
                lookups[key] = LookupState.failed(mapped.localizedDescription)
            }
        }
        await updateCacheStatistics()
    }

    // MARK: Cache

    func updateCacheStatistics() async {
        guard let service else { return }
        let statistics = await service.cacheStatistics()
        cacheRecordCount = statistics.records
        cacheSizeBytes = statistics.bytes
    }

    /// Deletes cached NVD records. Notes, bookmarks and history live in a
    /// different store and are not touched. The store is left empty until the
    /// next refresh: sample data is never brought back as a stand-in.
    func clearCachedData() async {
        await service?.clearCache()

        recordsByID = [:]
        vulnerabilities = []
        classifications = [:]
        appleFeed = []
        candidates = []
        vulnerabilityState = .empty
        refreshPhase = .idle
        refreshNotices = []
        keywordSearch = nil
        lookups = [:]
        feedOldest = nil
        lastRefreshed = nil
        canLoadEarlier = false
        earlierError = nil
        await updateCacheStatistics()
    }

    // MARK: Private

    /// Classifies off the main thread, then merges into the store.
    private func adopt(_ incoming: [Vulnerability], as newState: DataSourceState) async {
        let fresh = await Task.detached(priority: .userInitiated) {
            AppleClassifier.classify(incoming)
        }.value
        merge(incoming, classifications: fresh, state: newState)
    }

    private func merge(
        _ incoming: [Vulnerability],
        classifications fresh: [String: AppleClassification],
        state newState: DataSourceState
    ) {
        for record in incoming {
            recordsByID[record.id.uppercased()] = record
        }
        for (id, classification) in fresh {
            classifications[id] = classification
        }

        let sorted = recordsByID.values.sorted(by: VulnerabilityFilter.newestPublishedFirst)
        vulnerabilities = sorted
        appleFeed = sorted.filter { classifications[$0.id.uppercased()]?.relevance.isAppleFocused == true }
        candidates = sorted.filter { classifications[$0.id.uppercased()]?.relevance == .uncertain }
        vulnerabilityState = newState
    }

    /// State to show after a successful fetch that isn't a feed refresh.
    private func stateAfterNetworkFetch() -> DataSourceState {
        vulnerabilityState == .empty ? .live(lastUpdated: Date()) : vulnerabilityState
    }
}
