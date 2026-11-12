import XCTest
@testable import Pwned

final class TermMatcherTests: XCTestCase {
    private func ids(_ text: String, _ mode: TermMatchMode = .note) -> [String] {
        TermMatcher.matches(in: text, mode: mode).map(\.topicID)
    }

    func testFindsNamesInReadingOrder() {
        XCTAssertEqual(ids("Studying the BootROM and then iBoot."), ["bootrom", "iboot"])
    }

    func testNoteModeIgnoresCaseForOrdinaryNames() {
        XCTAssertEqual(ids("the kernel panics"), ["kernel"])
        XCTAssertEqual(ids("ios and webkit"), ["ios", "webkit"])
    }

    func testShortAcronymsNeedExactCase() {
        XCTAssertEqual(ids("the SEP boots first"), ["sep"])
        XCTAssertEqual(ids("a sep of two words"), [])
        XCTAssertEqual(ids("the pac was ignored"), [])
    }

    func testMatchesWholeWordsOnly() {
        XCTAssertEqual(ids("WebKitGTK is not the same as WebKit"), ["webkit"])
        XCTAssertEqual(ids("iOSurface is a framework"), [])
    }

    func testMultiWordNamesNeedAdjacentWords() {
        XCTAssertEqual(ids("the secure boot process"), ["secure-boot"])
        XCTAssertEqual(ids("a secure. Boot is next"), [])
    }

    func testHyphenatedNames() {
        XCTAssertEqual(ids("pairing over Wi-Fi"), ["wi-fi"])
    }

    func testLongestNameWins() {
        XCTAssertEqual(ids("the Secure Enclave Processor"), ["sep"])
    }

    func testChipNamesMapToAppleSilicon() {
        XCTAssertEqual(ids("on the A14 and the M2"), ["apple-silicon", "apple-silicon"])
        XCTAssertEqual(ids("a M or A alone is not a chip"), [])
    }

    func testIgnoresCommonProseThatSharesAnAlias() {
        XCTAssertEqual(ids("a series of unrelated bugs"), [])
    }

    // MARK: Description mode

    func testDescriptionModeRequiresAppleSpellingOfOperatingSystems() {
        XCTAssertEqual(ids("This issue is fixed in iOS 18.2.", .description), ["ios"])
        XCTAssertEqual(ids("A vulnerability in Cisco IOS Software", .description), [])
    }

    func testDescriptionModeStillMatchesTechnologiesCaseInsensitively() {
        XCTAssertEqual(ids("a flaw in webkit", .description), ["webkit"])
    }

    func testRangesPointAtTheMatchedText() {
        let text = "Found in the XNU kernel."
        let match = TermMatcher.matches(in: text, mode: .note).first
        XCTAssertEqual(match.map { String(text[$0.range]) }, "XNU")
    }
}
