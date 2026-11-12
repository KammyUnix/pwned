import XCTest
@testable import Pwned

final class VulnerabilityFilterTests: XCTestCase {
    private let critical = Fixtures.vulnerability(id: "CVE-2026-0010", summary: "Critical flaw.", score: 9.8, publishedDaysAgo: 3,
                                                  products: [Fixtures.product("apple", "iphone_os")])
    private let medium = Fixtures.vulnerability(id: "CVE-2026-0011", summary: "Medium flaw.", score: 5.0, publishedDaysAgo: 1,
                                                products: [Fixtures.product("apple", "macos")])
    private let unrated = Fixtures.vulnerability(id: "CVE-2026-0012", summary: "Unrated flaw.", publishedDaysAgo: 2)

    private var all: [Vulnerability] { [critical, medium, unrated] }

    func testDefaultOrderIsNewestPublishedFirst() {
        XCTAssertEqual(VulnerabilityFilter().apply(to: all).map(\.id), ["CVE-2026-0011", "CVE-2026-0012", "CVE-2026-0010"])
    }

    func testSeverityFilterNarrowsTheList() {
        var filter = VulnerabilityFilter()
        filter.severities = [.critical]
        XCTAssertEqual(filter.apply(to: all).map(\.id), ["CVE-2026-0010"])

        filter.severities = [.unknown]
        XCTAssertEqual(filter.apply(to: all).map(\.id), ["CVE-2026-0012"])
    }

    func testSeveritySortPutsTheHighestScoreFirstAndUnratedLast() {
        var filter = VulnerabilityFilter()
        filter.sort = .severity
        XCTAssertEqual(filter.apply(to: all).map(\.id), ["CVE-2026-0010", "CVE-2026-0011", "CVE-2026-0012"])
    }

    func testPlatformFilterUsesTheClassifiersPlatforms() {
        let classifications = AppleClassifier.classify(all)
        var filter = VulnerabilityFilter()
        filter.platforms = [.macOS]
        XCTAssertEqual(filter.apply(to: all, classifications: classifications).map(\.id), ["CVE-2026-0011"])

        filter.platforms = [.iOS, .macOS]
        XCTAssertEqual(Set(filter.apply(to: all, classifications: classifications).map(\.id)), ["CVE-2026-0010", "CVE-2026-0011"])
    }

    func testPlatformFilterWithoutClassificationsMatchesNothing() {
        var filter = VulnerabilityFilter()
        filter.platforms = [.iOS]
        XCTAssertTrue(filter.apply(to: all).isEmpty)
    }

    func testBookmarkedOnlyKeepsTheGivenIDs() {
        XCTAssertEqual(VulnerabilityFilter().apply(to: all, bookmarkedIDs: ["CVE-2026-0011"]).map(\.id), ["CVE-2026-0011"])
        XCTAssertTrue(VulnerabilityFilter().apply(to: all, bookmarkedIDs: []).isEmpty)
    }

    func testKnownExploitedFilter() {
        let exploited = Fixtures.vulnerability(id: "CVE-2026-0013", kev: KnownExploitedInfo(name: "Apple Example"))
        var filter = VulnerabilityFilter()
        filter.knownExploitedOnly = true
        XCTAssertEqual(filter.apply(to: all + [exploited]).map(\.id), ["CVE-2026-0013"])
    }

    func testSearchTextMatchesTheDisplayedProductName() {
        // The data says "iphone_os"; people search for "iOS".
        XCTAssertEqual(VulnerabilityFilter().apply(to: all, searchText: "iOS").map(\.id), ["CVE-2026-0010"])
        XCTAssertEqual(VulnerabilityFilter().apply(to: all, searchText: "cve-2026-0011").map(\.id), ["CVE-2026-0011"])
    }

    func testNarrowingAndActiveFlags() {
        var filter = VulnerabilityFilter()
        XCTAssertFalse(filter.isNarrowing)
        XCTAssertFalse(filter.isActive)

        filter.sort = .severity
        XCTAssertFalse(filter.isNarrowing, "Sorting alone doesn't narrow the list")
        XCTAssertTrue(filter.isActive)

        filter.platforms = [.iOS]
        XCTAssertTrue(filter.isNarrowing)
    }
}

@MainActor
final class SearchEngineTests: XCTestCase {
    private let apple = Fixtures.vulnerability(id: "CVE-2026-0020", summary: "Heap overflow in WebKit fixed in iOS 26.1.",
                                               products: [Fixtures.product("apple", "iphone_os")])
    private let php = Fixtures.vulnerability(id: "CVE-2026-0021", summary: "Heap overflow in the PHP stream wrapper.",
                                             products: [Fixtures.product("php", "php")])

    func testAnExactCVEIDFindsAnyRecordOnTheDevice() {
        let results = SearchEngine.results(for: "CVE-2026-0021", feed: [apple], known: [apple, php], notes: [])
        XCTAssertEqual(results.first?.category, .vulnerability)
        XCTAssertEqual(results.first?.target, .vulnerability("CVE-2026-0021"))
    }

    func testFreeTextOnlySearchesTheAppleFeed() {
        let results = SearchEngine.results(for: "heap overflow", feed: [apple], known: [apple, php], notes: [])
        let targets = results.map(\.target)
        XCTAssertTrue(targets.contains(.vulnerability("CVE-2026-0020")))
        XCTAssertFalse(targets.contains(.vulnerability("CVE-2026-0021")), "A non-Apple record must not appear in a text search")
    }

    func testPlatformVersionOpensThePlatformPage() {
        let results = SearchEngine.results(for: "iOS 18", feed: [], known: [], notes: [])
        XCTAssertTrue(results.contains { $0.category == .appleVersion && $0.target == .researchTopic("ios") })
    }

    func testARepositoryURLOffersTheRepository() {
        let results = SearchEngine.results(for: "https://github.com/apple/swift-nio", feed: [], known: [], notes: [])
        XCTAssertEqual(results.first?.category, .repository)
        XCTAssertEqual(results.first?.target, .repository(GitHubRepositoryReference(owner: "apple", name: "swift-nio")))
    }

    func testCatalogTopicsAreFoundByNameAndAlias() {
        let byName = SearchEngine.results(for: "BootROM", feed: [], known: [], notes: [])
        XCTAssertTrue(byName.contains { $0.target == .researchTopic("bootrom") })

        let byAlias = SearchEngine.results(for: "SecureROM", feed: [], known: [], notes: [])
        XCTAssertTrue(byAlias.contains { $0.target == .researchTopic("bootrom") })
    }

    func testAnEmptyQueryReturnsNothing() {
        XCTAssertTrue(SearchEngine.results(for: "   ", feed: [apple], known: [apple], notes: []).isEmpty)
    }

    func testNoSearchResultIsMarkedAsSampleData() {
        let results = SearchEngine.results(for: "CVE", feed: [apple], known: [apple], notes: [])
        XCTAssertFalse(results.contains { $0.id.contains("sample") })
    }
}
