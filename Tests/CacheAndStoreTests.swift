import XCTest
@testable import Pwned

final class VulnerabilityCacheTests: XCTestCase {
    private func cacheFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("PwnedCache/vulnerabilities.json")
    }

    func testRecordsSurviveARestartWithTheirRawNames() async throws {
        let directory = Fixtures.temporaryDirectory(for: "cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = Fixtures.vulnerability(id: "CVE-2026-0030", products: [Fixtures.product("apple", "iphone os")])
        await VulnerabilityCache(directory: directory).merge([record], markRefreshed: true)

        let reopened = await VulnerabilityCache(directory: directory).contents()
        XCTAssertEqual(reopened.vulnerabilities.map(\.id), ["CVE-2026-0030"])
        XCTAssertEqual(reopened.vulnerabilities.first?.affectedProducts.first?.product, "iphone os",
                       "The cache stores what the source said; only display names change")
        XCTAssertNotNil(reopened.lastRefreshed)
    }

    func testClearingEmptiesMemoryAndDisk() async {
        let directory = Fixtures.temporaryDirectory(for: "cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheFile = cacheFileURL(in: directory)
        let cache = VulnerabilityCache(directory: directory)
        await cache.merge([Fixtures.vulnerability(id: "CVE-2026-0031")], markRefreshed: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))

        await cache.clear()

        let afterClear = await cache.contents()
        XCTAssertTrue(afterClear.vulnerabilities.isEmpty)
        XCTAssertNil(afterClear.lastRefreshed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))

        let reopened = await VulnerabilityCache(directory: directory).contents()
        XCTAssertTrue(reopened.vulnerabilities.isEmpty)
    }

    func testRecordsAreKeyedByUpperCasedID() async {
        let directory = Fixtures.temporaryDirectory(for: "cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = VulnerabilityCache(directory: directory)
        await cache.merge([Fixtures.vulnerability(id: "cve-2026-0032")])
        await cache.merge([Fixtures.vulnerability(id: "CVE-2026-0032", summary: "Updated.")])

        let contents = await cache.contents()
        XCTAssertEqual(contents.vulnerabilities.count, 1)
        XCTAssertEqual(contents.vulnerabilities.first?.summary, "Updated.")
    }

    /// A cache written before the Apple feed existed must be refreshed with it,
    /// but its records stay usable.
    func testAnOlderFeedVersionKeepsRecordsButForgetsTheRefreshTime() async throws {
        let directory = Fixtures.temporaryDirectory(for: "cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheFile = cacheFileURL(in: directory)
        let cache = VulnerabilityCache(directory: directory)
        await cache.merge([Fixtures.vulnerability(id: "CVE-2026-0033")], markRefreshed: true)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cacheFile)) as? [String: Any])
        XCTAssertNotNil(object["feedVersion"], "New caches record the feed version")
        object.removeValue(forKey: "feedVersion")
        try JSONSerialization.data(withJSONObject: object).write(to: cacheFile)

        let reopened = await VulnerabilityCache(directory: directory).contents()
        XCTAssertEqual(reopened.vulnerabilities.map(\.id), ["CVE-2026-0033"])
        XCTAssertNil(reopened.lastRefreshed)
    }

    func testAnUnreadableCacheFileIsIgnored() async throws {
        let directory = Fixtures.temporaryDirectory(for: "cache")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheFile = cacheFileURL(in: directory)
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cacheFile)

        let contents = await VulnerabilityCache(directory: directory).contents()
        XCTAssertTrue(contents.vulnerabilities.isEmpty)
    }
}

@MainActor
final class IntelligenceStoreTests: XCTestCase {
    private var sampleIDs: Set<String> {
        Set(SampleData.vulnerabilities.map { $0.id.uppercased() })
    }

    private func makeService(directory: URL, transport: RecordingTransport) -> (VulnerabilityService, VulnerabilityCache) {
        let cache = VulnerabilityCache(directory: directory)
        let client = NVDClient(transport: transport, limiter: RateLimiter(), apiKeyProvider: { nil })
        return (VulnerabilityService(client: client, cache: cache), cache)
    }

    func testANewStoreIsEmptyAndHoldsNoSampleData() {
        let store = IntelligenceStore()
        XCTAssertTrue(store.vulnerabilities.isEmpty)
        XCTAssertTrue(store.appleFeed.isEmpty)
        XCTAssertEqual(store.vulnerabilityState, .empty)
        XCTAssertTrue(sampleIDs.isDisjoint(with: Set(store.vulnerabilities.map { $0.id.uppercased() })))
    }

    func testSampleDataIsLabelledAndUsesReservedIdentifiers() {
        XCTAssertEqual(SampleData.label, "SAMPLE / DEVELOPMENT DATA")
        XCTAssertFalse(SampleData.vulnerabilities.isEmpty)
        XCTAssertTrue(SampleData.vulnerabilities.allSatisfy { $0.id.hasPrefix("CVE-2099-") && $0.isSample })
    }

    func testTheFeedHoldsOnlyAppleFocusedRecords() {
        let apple = Fixtures.vulnerability(id: "CVE-2026-0040", products: [Fixtures.product("apple", "macos")])
        let php = Fixtures.vulnerability(id: "CVE-2026-0041", summary: "PHP issue.", products: [Fixtures.product("php", "php")])
        let candidate = Fixtures.vulnerability(id: "CVE-2026-0042", products: [Fixtures.product("webkitgtk", "webkitgtk")])

        let store = IntelligenceStore(vulnerabilities: [apple, php, candidate], state: .cached(lastUpdated: nil))

        XCTAssertEqual(store.appleFeed.map(\.id), ["CVE-2026-0040"])
        XCTAssertEqual(store.candidates.map(\.id), ["CVE-2026-0042"])
        XCTAssertEqual(store.vulnerabilities.count, 3, "Everything fetched is kept; the feed is a view of it")
        XCTAssertEqual(store.feed(includingCandidates: false).map(\.id), ["CVE-2026-0040"])
        XCTAssertEqual(Set(store.feed(includingCandidates: true).map(\.id)), ["CVE-2026-0040", "CVE-2026-0042"])
    }

    func testTopicLookupReturnsOnlyAppleRecordsTaggedWithTheTopic() {
        let webkit = Fixtures.vulnerability(
            id: "CVE-2026-0043",
            summary: "A WebKit issue was addressed. Fixed in iOS 26.1.",
            products: [Fixtures.product("apple", "iphone_os")]
        )
        let other = Fixtures.vulnerability(id: "CVE-2026-0044", products: [Fixtures.product("apple", "macos")])
        let store = IntelligenceStore(vulnerabilities: [webkit, other], state: .cached(lastUpdated: nil))

        XCTAssertEqual(store.appleVulnerabilities(forTopic: "webkit").map(\.id), ["CVE-2026-0043"])
    }

    func testRefreshFillsTheFeedFromTheNetworkOnly() async throws {
        let directory = Fixtures.temporaryDirectory(for: "store-refresh")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (service, _) = makeService(directory: directory, transport: RecordingTransport(body: NVDFixtures.appleRecordJSON))

        let store = IntelligenceStore(service: service)
        await store.refresh()

        XCTAssertEqual(store.appleFeed.map(\.id), ["CVE-2026-9001"])
        XCTAssertEqual(store.refreshPhase, .idle)
        if case .live = store.vulnerabilityState {} else { XCTFail("Expected live data, got \(store.vulnerabilityState)") }
        XCTAssertTrue(sampleIDs.isDisjoint(with: Set(store.vulnerabilities.map { $0.id.uppercased() })))
    }

    func testAFailedRefreshLeavesTheStoreEmptyNotFilledWithSamples() async {
        let directory = Fixtures.temporaryDirectory(for: "store-offline")
        defer { try? FileManager.default.removeItem(at: directory) }
        let offline = RecordingTransport { _ in throw NetworkError.offline }
        let (service, _) = makeService(directory: directory, transport: offline)

        let store = IntelligenceStore(service: service)
        await store.refresh()

        XCTAssertTrue(store.vulnerabilities.isEmpty)
        XCTAssertEqual(store.vulnerabilityState, .empty)
        if case .failed = store.refreshPhase {} else { XCTFail("Expected a failed refresh, got \(store.refreshPhase)") }
    }

    /// "Clear Cached Data" must leave the app empty. It must never bring sample data back.
    func testClearingTheCacheLeavesTheStoreEmpty() async throws {
        let directory = Fixtures.temporaryDirectory(for: "store-clear")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (service, cache) = makeService(directory: directory, transport: RecordingTransport(body: NVDFixtures.appleRecordJSON))

        let store = IntelligenceStore(service: service)
        await store.refresh()
        XCTAssertFalse(store.vulnerabilities.isEmpty)
        let cachedBefore = await cache.recordCount()
        XCTAssertEqual(cachedBefore, 1)

        await store.clearCachedData()

        XCTAssertTrue(store.vulnerabilities.isEmpty)
        XCTAssertTrue(store.appleFeed.isEmpty)
        XCTAssertTrue(store.candidates.isEmpty)
        XCTAssertEqual(store.vulnerabilityState, .empty)
        XCTAssertTrue(sampleIDs.isDisjoint(with: Set(store.vulnerabilities.map { $0.id.uppercased() })))
        let cachedAfter = await cache.recordCount()
        XCTAssertEqual(cachedAfter, 0)
    }
}

final class AppInfoTests: XCTestCase {
    func testVersionLabelCombinesVersionAndBuild() {
        XCTAssertEqual(AppInfo(name: "Pwned", version: "0.3.0", build: "7").versionLabel, "Version 0.3.0 (7)")
    }

    func testAnEmptyBundleReportsUnavailableInsteadOfInventingValues() throws {
        let directory = Fixtures.temporaryDirectory(for: "bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try XCTUnwrap(Bundle(path: directory.path))

        let info = AppInfo(bundle: bundle)
        XCTAssertEqual(info.version, AppInfo.unavailable)
        XCTAssertEqual(info.build, AppInfo.unavailable)
    }

    func testTheRunningAppReportsItsRealVersionAndBuild() {
        let info = AppInfo(bundle: .main)
        let plist = Bundle.main.infoDictionary
        XCTAssertEqual(info.version, plist?["CFBundleShortVersionString"] as? String ?? AppInfo.unavailable)
        XCTAssertEqual(info.build, plist?["CFBundleVersion"] as? String ?? AppInfo.unavailable)
    }
}
