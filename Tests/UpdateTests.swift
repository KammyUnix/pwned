import XCTest
@testable import Pwned

final class SemanticVersionTests: XCTestCase {
    private func version(_ text: String, line: UInt = #line) -> SemanticVersion {
        guard let parsed = SemanticVersion(text) else {
            XCTFail("\(text) should parse", line: line)
            return SemanticVersion("0")!
        }
        return parsed
    }

    func testParsesCommonTagFormats() {
        XCTAssertEqual(version("0.4.0").description, "0.4.0")
        XCTAssertEqual(version("v0.4.0").description, "0.4.0")
        XCTAssertEqual(version("V1.2").description, "1.2")
        XCTAssertEqual(version(" 2 ").description, "2")
        XCTAssertEqual(version("1.2.3+build.5").description, "1.2.3")
        XCTAssertEqual(version("1.0.0-beta.1").description, "1.0.0-beta.1")
    }

    func testRejectsTextThatIsNotAVersion() {
        for text in ["", "v", "abc", "1..2", "1.2.3.4.5", "1.-2", "1.2.x", "1.0.0-", "1.0.0-beta..1", "1.0.0-be ta", "٣.١"] {
            XCTAssertNil(SemanticVersion(text), "\(text) should not parse")
        }
    }

    func testNumbersCompareAsNumbersNotText() {
        XCTAssertLessThan(version("0.9.0"), version("0.10.0"))
        XCTAssertLessThan(version("0.3.9"), version("0.4.0"))
        XCTAssertLessThan(version("1.9.9"), version("2.0.0"))
        XCTAssertGreaterThan(version("1.10"), version("1.9.9"))
    }

    func testMissingTrailingComponentsAreZero() {
        XCTAssertEqual(version("1.2"), version("1.2.0"))
        XCTAssertEqual(version("v1"), version("1.0.0"))
        XCTAssertEqual(Set([version("1.2"), version("1.2.0")]).count, 1)
        XCTAssertLessThan(version("1.2"), version("1.2.1"))
    }

    func testPrereleaseSortsBelowItsRelease() {
        XCTAssertLessThan(version("1.0.0-beta.1"), version("1.0.0"))
        XCTAssertLessThan(version("1.0.0-rc.1"), version("1.0.0"))
        XCTAssertGreaterThan(version("1.0.1-alpha"), version("1.0.0"))
        XCTAssertTrue(version("1.0.0-beta").isPrerelease)
        XCTAssertFalse(version("1.0.0").isPrerelease)
    }

    func testPrereleaseIdentifiersFollowSemverOrder() {
        // The order from the Semantic Versioning 2.0 specification.
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                       "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(version(lower), version(higher), "\(lower) < \(higher)")
        }
    }

    func testBuildMetadataDoesNotAffectOrder() {
        XCTAssertEqual(version("1.0.0+1"), version("1.0.0+2"))
    }
}

final class UpdateCheckerTests: XCTestCase {
    static let releaseJSON = """
    {"tag_name":"v0.5.0","name":"Pwned 0.5.0","body":"## Changes\\n- Faster **refresh**","draft":false,
     "prerelease":false,"published_at":"2026-11-25T09:30:00Z",
     "html_url":"https://github.com/KammyUnix/pwned/releases/tag/v0.5.0","assets":[]}
    """

    private func checker(status: Int = 200, body: String = releaseJSON, retryAfter: TimeInterval? = nil) -> (UpdateChecker, RecordingTransport) {
        let transport = RecordingTransport(status: status, body: body, retryAfter: retryAfter)
        return (UpdateChecker(transport: transport), transport)
    }

    private func release(tag: String, prerelease: Bool = false) -> ReleaseInfo {
        ReleaseInfo(
            tagName: tag,
            name: nil,
            notes: "",
            publishedAt: nil,
            pageURL: URL(string: "https://github.com/KammyUnix/pwned/releases/tag/\(tag)")!,
            isPrerelease: prerelease
        )
    }

    // MARK: Requests

    func testRequestAsksForTheLatestReleaseOfTheProjectRepository() async throws {
        let (checker, transport) = checker()
        _ = try await checker.latestRelease()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/KammyUnix/pwned/releases/latest")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Update checks are anonymous")
    }

    // MARK: Decoding

    func testDecodesTheReleaseFields() async throws {
        let (checker, _) = checker()
        let release = try await XCTUnwrap(checker.latestRelease())

        XCTAssertEqual(release.tagName, "v0.5.0")
        XCTAssertEqual(release.title, "Pwned 0.5.0")
        XCTAssertEqual(release.versionLabel, "0.5.0")
        XCTAssertEqual(release.notes, "## Changes\n- Faster **refresh**")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/KammyUnix/pwned/releases/tag/v0.5.0")
        XCTAssertFalse(release.isPrerelease)

        let published = try XCTUnwrap(release.publishedAt)
        XCTAssertEqual(published.timeIntervalSince1970, 1_795_599_000, accuracy: 1)
    }

    func testTitleFallsBackToTheTagWhenTheReleaseHasNoName() {
        XCTAssertEqual(release(tag: "v1.0.0").title, "v1.0.0")
    }

    func testRepositoryWithoutReleasesGivesNil() async throws {
        let (checker, _) = checker(status: 404, body: #"{"message":"Not Found"}"#)
        let latest = try await checker.latestRelease()
        XCTAssertNil(latest)
    }

    func testDraftsAreIgnored() async throws {
        let draft = Self.releaseJSON.replacingOccurrences(of: #""draft":false"#, with: #""draft":true"#)
        let (checker, _) = checker(body: draft)
        let latest = try await checker.latestRelease()
        XCTAssertNil(latest)
    }

    // MARK: Failures

    private func failure(status: Int = 200, body: String = "", retryAfter: TimeInterval? = nil) async -> GitHubError? {
        let (checker, _) = checker(status: status, body: body, retryAfter: retryAfter)
        do {
            _ = try await checker.latestRelease()
            return nil
        } catch {
            return error as? GitHubError
        }
    }

    func testRateLimitIsReported() async {
        let error = await failure(status: 403, retryAfter: 30)
        XCTAssertEqual(error, .rateLimited(retryAfter: 30))
        let tooMany = await failure(status: 429)
        XCTAssertEqual(tooMany, .rateLimited(retryAfter: nil))
    }

    func testServerErrorIsReported() async {
        let error = await failure(status: 503)
        XCTAssertEqual(error, .server(status: 503))
    }

    func testOtherStatusIsRejected() async {
        let error = await failure(status: 422)
        XCTAssertEqual(error, .rejected(status: 422))
    }

    func testUnreadableBodyIsAnInvalidResponse() async {
        let error = await failure(body: "<html>not json</html>")
        XCTAssertEqual(error, .invalidResponse)
        let missingFields = await failure(body: #"{"tag_name":"v1.0.0"}"#)
        XCTAssertEqual(missingFields, .invalidResponse)
    }

    func testTransportErrorsAreMapped() async {
        let offline = UpdateChecker(transport: RecordingTransport { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await offline.latestRelease()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .offline)
        }

        let timedOut = UpdateChecker(transport: RecordingTransport { _ in throw URLError(.timedOut) })
        do {
            _ = try await timedOut.latestRelease()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .timedOut)
        }
    }

    // MARK: Status

    func testNewerReleaseIsAnUpdate() {
        let latest = release(tag: "v0.5.0")
        XCTAssertEqual(UpdateChecker.status(installedVersion: "0.4.0", release: latest), .updateAvailable(latest))
        XCTAssertEqual(UpdateChecker.status(installedVersion: "0.4.9", release: latest), .updateAvailable(latest))
    }

    func testTenIsNewerThanNine() {
        let latest = release(tag: "v0.10.0")
        XCTAssertEqual(UpdateChecker.status(installedVersion: "0.9.0", release: latest), .updateAvailable(latest))
    }

    func testSameVersionIsUpToDate() {
        let latest = release(tag: "v0.4.0")
        XCTAssertEqual(UpdateChecker.status(installedVersion: "0.4.0", release: latest), .upToDate(latest))
        XCTAssertEqual(UpdateChecker.status(installedVersion: "0.4", release: latest), .upToDate(latest))
    }

    func testNewerInstalledVersionIsAhead() {
        let latest = release(tag: "v0.3.0")
        XCTAssertEqual(UpdateChecker.status(installedVersion: "0.4.0", release: latest), .ahead(latest))
    }

    func testPrereleaseNeverCountsAsAnUpdate() {
        let beta = release(tag: "v9.0.0-beta.1", prerelease: true)
        XCTAssertEqual(UpdateChecker.status(installedVersion: "0.4.0", release: beta), .noRelease)
    }

    func testUnreadableTagIsReportedNotGuessed() {
        let status = UpdateChecker.status(installedVersion: "0.4.0", release: release(tag: "nightly"))
        guard case .apiError(let message) = status else {
            return XCTFail("Expected an API error, got \(status)")
        }
        XCTAssertTrue(message.contains("nightly"))
    }

    func testUnreadableInstalledVersionIsReported() {
        let status = UpdateChecker.status(installedVersion: AppInfo.unavailable, release: release(tag: "v1.0.0"))
        guard case .apiError = status else {
            return XCTFail("Expected an API error, got \(status)")
        }
    }

    func testErrorsMapToTheRightStatus() {
        guard case .networkError = UpdateChecker.status(for: .offline) else { return XCTFail("offline") }
        guard case .networkError = UpdateChecker.status(for: .timedOut) else { return XCTFail("timed out") }
        guard case .apiError = UpdateChecker.status(for: .rateLimited(retryAfter: nil)) else { return XCTFail("rate limit") }
        guard case .apiError = UpdateChecker.status(for: .server(status: 500)) else { return XCTFail("server") }
        guard case .apiError = UpdateChecker.status(for: .rejected(status: 400)) else { return XCTFail("rejected") }
        guard case .apiError = UpdateChecker.status(for: .invalidResponse) else { return XCTFail("invalid") }
        XCTAssertNil(UpdateChecker.status(for: .cancelled))
    }

    // MARK: Model

    @MainActor
    func testModelReportsAnAvailableUpdate() async {
        let (checker, _) = checker()
        let model = UpdateModel(checker: checker, installedVersion: "0.4.0")
        XCTAssertEqual(model.status, .idle)

        await model.check()

        guard case .updateAvailable(let release) = model.status else {
            return XCTFail("Expected an update, got \(model.status)")
        }
        XCTAssertEqual(release.versionLabel, "0.5.0")
        XCTAssertNotNil(model.lastChecked)
    }

    @MainActor
    func testModelReportsUpToDateAndNoRelease() async {
        let (current, _) = checker()
        let upToDate = UpdateModel(checker: current, installedVersion: "0.5.0")
        await upToDate.check()
        guard case .upToDate = upToDate.status else { return XCTFail("Expected up to date, got \(upToDate.status)") }

        let (empty, _) = checker(status: 404, body: "{}")
        let none = UpdateModel(checker: empty, installedVersion: "0.4.0")
        await none.check()
        XCTAssertEqual(none.status, .noRelease)
    }

    @MainActor
    func testModelReportsNetworkAndAPIErrors() async {
        let offline = UpdateModel(
            checker: UpdateChecker(transport: RecordingTransport { _ in throw URLError(.notConnectedToInternet) }),
            installedVersion: "0.4.0"
        )
        await offline.check()
        guard case .networkError = offline.status else { return XCTFail("Expected a network error, got \(offline.status)") }

        let (broken, _) = checker(status: 500)
        let server = UpdateModel(checker: broken, installedVersion: "0.4.0")
        await server.check()
        guard case .apiError = server.status else { return XCTFail("Expected an API error, got \(server.status)") }
    }

    @MainActor
    func testAutomaticCheckRunsOnceAndOnlyWhenEnabled() async {
        let (checker, transport) = checker()
        let model = UpdateModel(checker: checker, installedVersion: "0.4.0")

        await model.checkAutomatically(enabled: false)
        XCTAssertEqual(transport.requests.count, 0)

        await model.checkAutomatically(enabled: true)
        await model.checkAutomatically(enabled: true)
        XCTAssertEqual(transport.requests.count, 1, "One automatic check per launch")

        await model.check()
        XCTAssertEqual(transport.requests.count, 2, "A manual check always runs")
    }

    @MainActor
    func testManualCheckAfterAnErrorRecovers() async {
        let outcomes = Outcomes()
        let transport = RecordingTransport { _ in
            if outcomes.next() == 0 { throw URLError(.notConnectedToInternet) }
            return HTTPResult(data: Data(Self.releaseJSON.utf8), statusCode: 200, retryAfter: nil)
        }
        let model = UpdateModel(checker: UpdateChecker(transport: transport), installedVersion: "0.4.0")

        await model.check()
        guard case .networkError = model.status else { return XCTFail("Expected a network error") }
        await model.check()
        guard case .updateAvailable = model.status else { return XCTFail("Expected an update, got \(model.status)") }
    }

    /// Counts calls from inside a `@Sendable` closure.
    private final class Outcomes: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int {
            lock.withLock {
                defer { count += 1 }
                return count
            }
        }
    }
}
