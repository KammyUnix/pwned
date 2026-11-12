import XCTest
@testable import Pwned

final class NoteLinkerTests: XCTestCase {
    private func mentions(_ text: String) -> [LinkMention] {
        NoteLinker.mentions(in: text)
    }

    // MARK: CVEs

    func testRecognizesCVEIdentifiersInAnyCase() {
        let text = "See CVE-2024-23222 and cve-2023-1234."
        let found = mentions(text).filter { $0.kind == .vulnerability }
        XCTAssertEqual(found.map(\.entityID), ["CVE-2024-23222", "CVE-2023-1234"])
        XCTAssertTrue(found.allSatisfy { $0.certainty == .certain })
    }

    func testRejectsMalformedCVEIdentifiers() {
        XCTAssertTrue(mentions("CVE-24-1 and CVE-2024-12").filter { $0.kind == .vulnerability }.isEmpty)
    }

    // MARK: Repositories

    func testRecognizesGitHubRepositoryURLs() {
        let text = "Source: https://github.com/apple/swift-nio."
        let found = mentions(text).filter { $0.kind == .repository }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.entityID, "apple/swift-nio")
        XCTAssertEqual(found.first?.certainty, .certain)
        XCTAssertEqual(found.first.map { String(text[$0.range]) }, "github.com/apple/swift-nio")
    }

    func testRepositoryIDsAreLowerCaseAndIgnoreDotGit() {
        let found = mentions("clone github.com/Apple/Swift-NIO.git now").filter { $0.kind == .repository }
        XCTAssertEqual(found.first?.entityID, "apple/swift-nio")
    }

    func testAPIHostsAreNotRepositoryLinks() {
        XCTAssertTrue(mentions("api.github.com/repos/foo/bar").filter { $0.kind == .repository }.isEmpty)
    }

    func testARepositoryURLIsNotAlsoATopicMention() {
        let found = mentions("github.com/WebKit/WebKit")
        XCTAssertEqual(found.map(\.kind), [.repository])
    }

    // MARK: Topics

    func testTechnologyNamesAreOnlySuggestions() {
        let found = mentions("The BootROM runs first.").filter { $0.kind == .technology }
        XCTAssertEqual(found.map(\.entityID), ["bootrom"])
        XCTAssertEqual(found.first?.certainty, .suggested)
    }

    func testProductMentionsIncludeTheVersion() {
        let text = "Reproduced on iOS 18.2."
        let found = mentions(text).filter { $0.kind == .product }
        XCTAssertEqual(found.first?.entityID, "ios")
        XCTAssertEqual(found.first?.displayName, "iOS")
        XCTAssertEqual(found.first.map { String(text[$0.range]) }, "iOS 18.2")
    }

    func testUniqueMentionsKeepsTheFirstOfEachTarget() {
        let unique = NoteLinker.uniqueMentions(mentions("BootROM, then BootROM again, and CVE-2024-1111 and CVE-2024-1111"))
        XCTAssertEqual(unique.map(\.key), ["technology:bootrom", "vulnerability:CVE-2024-1111"])
    }

    func testKeyCombinesKindAndEntity() {
        let found = mentions("CVE-2024-1111").first
        XCTAssertEqual(found?.key, "vulnerability:CVE-2024-1111")
    }

    // MARK: Links inside the app

    func testLinkURLRoundTrips() throws {
        let url = try XCTUnwrap(LinkURL.url(kind: .repository, entityID: "apple/swift-nio"))
        XCTAssertEqual(url.scheme, "pwned")
        let target = try XCTUnwrap(LinkURL.target(from: url))
        XCTAssertEqual(target.kind, .repository)
        XCTAssertEqual(target.entityID, "apple/swift-nio")
    }

    func testLinkURLRejectsOtherURLs() throws {
        XCTAssertNil(LinkURL.target(from: try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertNil(LinkURL.target(from: try XCTUnwrap(URL(string: "pwned://open?kind=bogus&id=x"))))
        XCTAssertNil(LinkURL.target(from: try XCTUnwrap(URL(string: "pwned://open?kind=technology"))))
    }

    func testRoutesFromLinkURLs() throws {
        let cve = try XCTUnwrap(LinkURL.url(kind: .vulnerability, entityID: "CVE-2024-1111"))
        XCTAssertEqual(AppRoute(linkURL: cve), .vulnerability("CVE-2024-1111"))

        let topic = try XCTUnwrap(LinkURL.url(kind: .technology, entityID: "bootrom"))
        XCTAssertEqual(AppRoute(linkURL: topic), .researchTopic("bootrom"))

        let repository = try XCTUnwrap(LinkURL.url(kind: .repository, entityID: "apple/swift-nio"))
        XCTAssertEqual(AppRoute(linkURL: repository), .repository(GitHubRepositoryReference(owner: "apple", name: "swift-nio")))
    }

    // MARK: Rendering

    func testOnlyLinkedMentionsBecomeLinksInRenderedText() throws {
        let body = "CVE-2024-1111 and the BootROM"
        let reference = NoteReference(
            noteID: UUID(), kind: .vulnerability, entityID: "CVE-2024-1111",
            displayName: "CVE-2024-1111", origin: .automatic
        )
        let rendered = NoteRenderer.attributed(
            body: body,
            mentions: NoteLinker.mentions(in: body),
            references: [reference],
            resolution: { _, _ in .resolved }
        )
        let links = rendered.runs.compactMap { $0.link }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first, LinkURL.url(kind: .vulnerability, entityID: "CVE-2024-1111"))
        XCTAssertEqual(String(rendered.characters), body)
    }
}
