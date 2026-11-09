import Foundation
import Observation

/// Where the data currently shown in a section came from.
enum DataSourceState: Equatable {
    /// Built-in development data only. No live source has been queried.
    case sample
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

/// Single source of truth for intelligence data shown across the app.
///
/// Vulnerabilities come from the on-disk cache and the NVD CVE API. Apple
/// advisories, announcements and repository summaries are still built-in
/// samples; later phases replace them behind this same interface.
@MainActor
@Observable
final class IntelligenceStore {
    // MARK: Sample-backed sections

    private(set) var appleAdvisories: [AppleAdvisory]
    private(set) var announcements: [SecurityAnnouncement]
    private(set) var repositories: [RepositorySummary]
    /// State of the sample-backed sections above.
    private(set) var state: DataSourceState

    // MARK: Vulnerabilities

    /// Every known record, newest publication first.
    private(set) var vulnerabilities: [Vulnerability]
    private(set) var vulnerabilityState: DataSourceState
    private(set) var refreshPhase: RefreshPhase = .idle
    private(set) var isLoadingEarlier = false
    private(set) var canLoadEarlier = false
    private(set) var earlierError: String?
    private(set) var keywordSearch: KeywordSearchState?
    private(set) var lookups: [String: LookupState] = [:]
    private(set) var cacheRecordCount = 0
    private(set) var cacheSizeBytes: Int64 = 0
    private var recordsByID: [String: Vulnerability]

    private let service: VulnerabilityService?
    @ObservationIgnored private var feedOldest: Date?
    @ObservationIgnored private var lastRefreshed: Date?
    @ObservationIgnored private var hasStarted = false

    /// NVD asks clients not to poll aggressively, so an automatic refresh only
    /// happens when the data is older than this. Pull to refresh overrides it.
    private static let staleInterval: TimeInterval = 2 * 60 * 60
    private static let windowLength: TimeInterval = 24 * 60 * 60

    /// - Parameter service: Pass `VulnerabilityService.live()` for network and
    ///   cache access. With `nil` (previews) the store serves its initial data only.
    init(
        vulnerabilities: [Vulnerability] = SampleData.vulnerabilities,
        appleAdvisories: [AppleAdvisory] = SampleData.appleAdvisories,
        announcements: [SecurityAnnouncement] = SampleData.announcements,
        repositories: [RepositorySummary] = SampleData.repositories,
        state: DataSourceState = .sample,
        service: VulnerabilityService? = nil
    ) {
        self.recordsByID = Dictionary(
            vulnerabilities.map { ($0.id.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.vulnerabilities = vulnerabilities.sorted(by: VulnerabilityFilter.newestPublishedFirst)
        self.vulnerabilityState = state
        self.appleAdvisories = appleAdvisories
        self.announcements = announcements
        self.repositories = repositories
        self.state = state
        self.service = service
    }

    // MARK: Derived data

    var isShowingSampleData: Bool { state == .sample }
    var isShowingSampleVulnerabilities: Bool { vulnerabilityState == .sample }
    var hasNetworkService: Bool { service != nil }

    /// Newest publication first.
    var recentVulnerabilities: [Vulnerability] { vulnerabilities }

    var recentAdvisories: [AppleAdvisory] {
        appleAdvisories.sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentRepositories: [RepositorySummary] {
        repositories.sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentAnnouncements: [SecurityAnnouncement] {
        announcements.sorted { $0.date > $1.date }
    }

    func vulnerability(id: String) -> Vulnerability? {
        recordsByID[id.uppercased()]
    }

    func vulnerabilities(withIDs ids: [String]) -> [Vulnerability] {
        ids.compactMap { vulnerability(id: $0) }
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
            adopt(cached.vulnerabilities, as: .cached(lastUpdated: cached.lastRefreshed))
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

    /// Fetches the CVEs published in the last 24 hours.
    func refresh() async {
        guard let service, refreshPhase != .loading else { return }
        refreshPhase = .loading

        let end = Date()
        let start = end.addingTimeInterval(-Self.windowLength)
        do {
            let result = try await service.fetchWindow(from: start, to: end, markRefreshed: true)
            adopt(result.vulnerabilities, as: .live(lastUpdated: end))
            feedOldest = start
            canLoadEarlier = true
            if result.isComplete {
                lastRefreshed = end
            }
            refreshPhase = result.error.map { RefreshPhase.failed($0.localizedDescription) } ?? .idle
        } catch {
            let mapped = NetworkError.map(error)
            refreshPhase = (mapped == .cancelled) ? .idle : .failed(mapped.localizedDescription)
        }
        await updateCacheStatistics()
    }

    /// Fetches the 24 hours before the oldest window loaded so far.
    func loadEarlier() async {
        guard let service, let oldest = feedOldest, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        earlierError = nil
        defer { isLoadingEarlier = false }

        let start = oldest.addingTimeInterval(-Self.windowLength)
        do {
            let result = try await service.fetchWindow(from: start, to: oldest, markRefreshed: false)
            adopt(result.vulnerabilities, as: vulnerabilityState)
            if result.isComplete {
                feedOldest = start
            }
            earlierError = result.error?.localizedDescription
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
            adopt(slice.vulnerabilities, as: stateAfterNetworkFetch())
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
            adopt(slice.vulnerabilities, as: stateAfterNetworkFetch())
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
                adopt([record], as: stateAfterNetworkFetch())
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
    /// different store and are not touched. The list falls back to labeled
    /// sample data until the next refresh.
    func clearCachedData() async {
        await service?.clearCache()

        recordsByID = Dictionary(
            SampleData.vulnerabilities.map { ($0.id.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        vulnerabilities = SampleData.vulnerabilities.sorted(by: VulnerabilityFilter.newestPublishedFirst)
        vulnerabilityState = .sample
        refreshPhase = .idle
        keywordSearch = nil
        lookups = [:]
        feedOldest = nil
        lastRefreshed = nil
        canLoadEarlier = false
        earlierError = nil
        await updateCacheStatistics()
    }

    // MARK: Private

    /// Merges records into the store. The first real data replaces the sample records.
    private func adopt(_ incoming: [Vulnerability], as newState: DataSourceState) {
        if vulnerabilityState == .sample {
            recordsByID = [:]
        }
        for record in incoming {
            recordsByID[record.id.uppercased()] = record
        }
        vulnerabilities = recordsByID.values.sorted(by: VulnerabilityFilter.newestPublishedFirst)
        vulnerabilityState = newState
    }

    /// State to show after a successful fetch that isn't a feed refresh.
    private func stateAfterNetworkFetch() -> DataSourceState {
        vulnerabilityState == .sample ? .live(lastUpdated: Date()) : vulnerabilityState
    }
}
