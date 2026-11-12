import XCTest
@testable import Pwned

/// The classifier decides what Discover shows. These cases cover the evidence
/// it should trust, the evidence it should only note, and the lookalikes it must
/// not mistake for Apple.
final class AppleClassifierTests: XCTestCase {
    private func classify(
        summary: String = "An unspecified issue.",
        products: [AffectedProduct] = [],
        references: [ExternalReference] = [],
        source: String? = nil,
        kev: KnownExploitedInfo? = nil,
        runsOn: [AffectedProduct]? = nil
    ) -> AppleClassification {
        AppleClassifier.classify(Fixtures.vulnerability(
            summary: summary, products: products, references: references,
            source: source, kev: kev, runsOn: runsOn
        ))
    }

    // MARK: Apple records

    func testIOSProductAnalyzedByNVDIsConfirmed() {
        let result = classify(products: [Fixtures.product("apple", "iphone_os")])
        XCTAssertEqual(result.relevance, .confirmed)
        XCTAssertTrue(result.isAppleFocused)
        XCTAssertEqual(result.platforms, [.iOS])
    }

    func testMacOSProductIsConfirmed() {
        let result = classify(products: [Fixtures.product("apple", "macos")])
        XCTAssertEqual(result.relevance, .confirmed)
        XCTAssertEqual(result.platforms, [.macOS])
    }

    func testSafariProductIsConfirmedAndTagsTheComponent() {
        let result = classify(products: [Fixtures.product("apple", "safari")])
        XCTAssertEqual(result.relevance, .confirmed)
        XCTAssertTrue(result.componentIDs.contains("safari"))
    }

    func testHardwareProductIsConfirmed() {
        let result = classify(products: [Fixtures.product("apple", "iphone", versions: "-")])
        XCTAssertEqual(result.relevance, .confirmed)
    }

    func testApplesOwnCNAIsConfirmedEvenWithoutProducts() {
        let result = classify(source: "product-security@apple.com")
        XCTAssertEqual(result.relevance, .confirmed)
        XCTAssertTrue(result.signals.contains { $0.kind == .appleCNA })
    }

    func testProductReportedByThePublisherIsLikelyNotConfirmed() {
        let result = classify(products: [Fixtures.product("apple", "macos", origin: .vendorReported)])
        XCTAssertEqual(result.relevance, .likely)
        XCTAssertTrue(result.isAppleFocused)
        XCTAssertEqual(result.platforms, [.macOS])
    }

    func testWebKitFixedInAnAppleReleaseIsLikely() {
        let result = classify(summary: "A memory corruption issue in WebKit was addressed with improved checks. This issue is fixed in iOS 18.2.")
        XCTAssertEqual(result.relevance, .likely)
        XCTAssertEqual(result.platforms, [.iOS])
        XCTAssertTrue(result.componentIDs.contains("webkit"))
    }

    func testXNUFixedInMacOSIsLikely() {
        let result = classify(summary: "A race condition in the XNU kernel was addressed in macOS 15.1 with improved locking.")
        XCTAssertEqual(result.relevance, .likely)
        XCTAssertEqual(result.platforms, [.macOS])
        XCTAssertTrue(result.componentIDs.contains("xnu"))
    }

    func testAppleSecurityReleaseReferenceIsLikely() {
        let result = classify(references: [Fixtures.reference("https://support.apple.com/en-us/124567")])
        XCTAssertEqual(result.relevance, .likely)
        XCTAssertTrue(result.signals.contains { $0.kind == .appleAdvisoryReference })
    }

    func testAppleKnownExploitedEntryIsLikely() {
        let kev = KnownExploitedInfo(name: "Apple Multiple Products Memory Corruption Vulnerability")
        let result = classify(kev: kev)
        XCTAssertEqual(result.relevance, .likely)
    }

    // MARK: Candidates

    func testBootROMMentionedOnlyInTheDescriptionNeedsReview() {
        let result = classify(summary: "A flaw in the BootROM allows code execution before the secure boot chain starts.")
        XCTAssertEqual(result.relevance, .uncertain)
        XCTAssertFalse(result.isAppleFocused)
    }

    func testThirdPartySoftwareRunningOnMacOSNeedsReview() {
        let result = classify(
            products: [Fixtures.product("example", "editor")],
            runsOn: [Fixtures.product("apple", "macos")]
        )
        XCTAssertEqual(result.relevance, .uncertain)
        XCTAssertFalse(result.isAppleFocused)
    }

    func testWebKitGTKNeedsReviewAndIsNotAppleFocused() {
        let result = classify(products: [Fixtures.product("webkitgtk", "webkitgtk")])
        XCTAssertEqual(result.relevance, .uncertain)
        XCTAssertFalse(result.isAppleFocused)
    }

    func testAnAppleHostedPageAloneNeedsReview() {
        let result = classify(references: [Fixtures.reference("https://developer.apple.com/documentation/example")])
        XCTAssertEqual(result.relevance, .uncertain)
    }

    // MARK: Not Apple

    func testPHPIsNotApple() {
        let result = classify(
            summary: "In PHP versions before 8.3.1, a heap overflow in the stream wrapper allows remote code execution.",
            products: [Fixtures.product("php", "php", versions: "before 8.3.1")]
        )
        XCTAssertEqual(result.relevance, .notApple)
        XCTAssertFalse(result.isAppleFocused)
    }

    func testWindowsOnlyKernelIssueIsNotApple() {
        let result = classify(
            summary: "Windows Kernel Elevation of Privilege Vulnerability",
            products: [Fixtures.product("microsoft", "windows_11")]
        )
        XCTAssertEqual(result.relevance, .notApple)
    }

    func testLinuxOnlyKernelIssueIsNotApple() {
        let result = classify(
            summary: "In the Linux kernel, the following vulnerability has been resolved: Bluetooth: fix a use-after-free in the HCI core.",
            products: [Fixtures.product("linux", "linux_kernel")]
        )
        XCTAssertEqual(result.relevance, .notApple)
    }

    func testUnrelatedThirdPartySoftwareIsNotApple() {
        let airflow = classify(
            summary: "Apache Airflow before 2.9.0 exposes connection secrets in task logs.",
            products: [Fixtures.product("apache", "airflow", versions: "before 2.9.0")]
        )
        XCTAssertEqual(airflow.relevance, .notApple)

        let neo4j = classify(
            summary: "Neo4j before 5.20 allows an authenticated user to read arbitrary files.",
            products: [Fixtures.product("neo4j", "neo4j", versions: "before 5.20")]
        )
        XCTAssertEqual(neo4j.relevance, .notApple)
    }

    /// "IOS" in a description is Cisco's operating system. It is not evidence of Apple's iOS.
    func testCiscoIOSIsNotMistakenForAppleIOS() {
        let result = classify(
            summary: "A vulnerability in the web UI of Cisco IOS Software could allow an authenticated attacker to cause a denial of service.",
            products: [Fixtures.product("cisco", "ios")]
        )
        XCTAssertEqual(result.relevance, .notApple)
    }

    func testRecordWithNoEvidenceAtAllIsNotApple() {
        XCTAssertEqual(classify().relevance, .notApple)
    }

    // MARK: Output shape

    func testPlatformsAreOnlyReportedForAppleFocusedRecords() {
        let result = classify(
            products: [Fixtures.product("example", "editor")],
            runsOn: [Fixtures.product("apple", "macos")]
        )
        XCTAssertTrue(result.platforms.isEmpty)
    }

    func testStrongerEvidenceRaisesConfidence() {
        let confirmed = classify(products: [Fixtures.product("apple", "iphone_os")])
        let both = classify(products: [Fixtures.product("apple", "iphone_os")], source: "product-security@apple.com")
        XCTAssertGreaterThan(both.confidence, confirmed.confidence)
        XCTAssertGreaterThan(confirmed.confidence, 0.9)
    }

    func testClassifyByIDKeysAreUpperCased() {
        let record = Fixtures.vulnerability(id: "cve-2026-0042", products: [Fixtures.product("apple", "macos")])
        let result = AppleClassifier.classify([record])
        XCTAssertEqual(result["CVE-2026-0042"]?.relevance, .confirmed)
    }

    func testRelevanceOrdering() {
        XCTAssertLessThan(AppleRelevance.notApple, .uncertain)
        XCTAssertLessThan(AppleRelevance.uncertain, .likely)
        XCTAssertLessThan(AppleRelevance.likely, .confirmed)
        XCTAssertFalse(AppleRelevance.uncertain.isAppleFocused)
        XCTAssertTrue(AppleRelevance.likely.isAppleFocused)
    }
}
