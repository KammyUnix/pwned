import XCTest
@testable import Pwned

final class NVDTests: XCTestCase {
    // MARK: Dates

    func testParsesNVDTimestampsAsUTC() {
        XCTAssertEqual(NVDDate.parse("2021-12-10T10:15:09.143")?.timeIntervalSince1970 ?? 0, 1_639_131_309.143, accuracy: 0.001)
        XCTAssertEqual(NVDDate.parse("2024-02-29T23:59:59")?.timeIntervalSince1970, 1_709_251_199)
        XCTAssertEqual(NVDDate.parse("2026-11-01")?.timeIntervalSince1970, 1_793_491_200)
    }

    func testIgnoresATrailingZoneDesignator() {
        XCTAssertEqual(NVDDate.parse("2026-11-08T06:09:55Z")?.timeIntervalSince1970, NVDDate.parse("2026-11-08T06:09:55")?.timeIntervalSince1970)
    }

    func testRejectsMalformedDates() {
        XCTAssertNil(NVDDate.parse(nil))
        XCTAssertNil(NVDDate.parse("yesterday"))
        XCTAssertNil(NVDDate.parse("2026-13-01"))
    }

    func testRequestStringRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_639_131_309)
        XCTAssertEqual(NVDDate.requestString(date), "2021-12-10T10:15:09.000Z")
        XCTAssertEqual(NVDDate.parse(NVDDate.requestString(date)), date)
    }

    // MARK: Queries

    private func query(_ query: NVDQuery) throws -> [String: String] {
        let url = try query.url()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    func testAppleCNAQueryUsesTheDocumentedParameters() throws {
        let from = Date(timeIntervalSince1970: 1_639_131_309)
        let items = try query(.appleCNA(from: from, to: from.addingTimeInterval(30 * Fixtures.day), resultsPerPage: 500))
        XCTAssertEqual(items["sourceIdentifier"], "product-security@apple.com")
        XCTAssertEqual(items["pubStartDate"], "2021-12-10T10:15:09.000Z")
        XCTAssertEqual(items["pubEndDate"], "2022-01-09T10:15:09.000Z")
        XCTAssertEqual(items["resultsPerPage"], "500")
        XCTAssertEqual(items["startIndex"], "0")
        XCTAssertNil(items["keywordSearch"])
    }

    func testCPEQueryCarriesTheMatchString() throws {
        let now = Fixtures.referenceDate
        let items = try query(.cpeMatch("cpe:2.3:o:apple:*", from: now, to: now, resultsPerPage: 100))
        XCTAssertEqual(items["virtualMatchString"], "cpe:2.3:o:apple:*")
    }

    func testValuesAreStrictlyPercentEncoded() throws {
        let url = try NVDQuery.search(keyword: "a&b=c+d", resultsPerPage: 10).url()
        XCTAssertTrue(url.absoluteString.contains("keywordSearch=a%26b%3Dc%2Bd"))
        XCTAssertTrue(try NVDQuery.appleCNA(from: .now, to: .now, resultsPerPage: 1).url().absoluteString.contains("product-security%40apple.com"))
    }

    func testCVELookupIsUpperCased() throws {
        XCTAssertEqual(try query(.cve("cve-2024-1234"))["cveId"], "CVE-2024-1234")
    }

    // MARK: Mapping

    func testMapsAnalyzedAppleRecordAndKeepsRawProductNames() throws {
        let records = try NVDFixtures.decode(NVDFixtures.appleRecordJSON)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.id, "CVE-2026-9001")
        XCTAssertEqual(record.cvss?.baseScore, 8.8)
        XCTAssertEqual(record.severity, .high)
        XCTAssertEqual(record.sourceIdentifier, "product-security@apple.com")

        // The data keeps NVD's own spelling; only the display changes.
        let product = try XCTUnwrap(record.affectedProducts.first)
        XCTAssertEqual(product.vendor, "apple")
        XCTAssertEqual(product.product, "iphone os")
        XCTAssertEqual(product.versions, "before 26.1")
        XCTAssertEqual(product.origin, .nvdAnalysis)
        XCTAssertEqual(AppleNaming.productName(vendor: product.vendor, product: product.product), "iOS")
        XCTAssertEqual(AppleNaming.versionText(product.versions), "Before 26.1")
    }

    func testMappedAppleRecordIsClassifiedAsConfirmed() throws {
        let record = try XCTUnwrap(NVDFixtures.decode(NVDFixtures.appleRecordJSON).first)
        let result = AppleClassifier.classify(record)
        XCTAssertEqual(result.relevance, .confirmed)
        XCTAssertEqual(result.platforms, [.iOS])
        XCTAssertTrue(result.componentIDs.contains("webkit"))
    }

    func testPlatformContextIsKeptApartFromAffectedProducts() throws {
        let record = try XCTUnwrap(NVDFixtures.decode(NVDFixtures.runsOnMacOSJSON).first)
        XCTAssertEqual(record.affectedProducts.map(\.vendor), ["example"])
        XCTAssertEqual(record.runsOn?.map(\.product), ["macos"])
        XCTAssertEqual(AppleClassifier.classify(record).relevance, .uncertain)
    }

    func testNegatedNodesNameNoAffectedProduct() throws {
        let record = try XCTUnwrap(NVDFixtures.decode(NVDFixtures.negatedNodeJSON).first)
        XCTAssertEqual(record.affectedProducts.map(\.vendor), ["example"])
        XCTAssertNil(record.runsOn)
        XCTAssertEqual(AppleClassifier.classify(record).relevance, .notApple)
    }

    func testAMalformedRecordDoesNotDiscardItsNeighbours() throws {
        let json = """
        {"totalResults":2,"vulnerabilities":[{"cve":{"published":"2026-01-01T00:00:00"}},
        {"cve":{"id":"CVE-2026-9100","published":"2026-01-02T00:00:00","descriptions":[{"lang":"en","value":"Fine."}]}}]}
        """
        let records = try NVDFixtures.decode(json)
        XCTAssertEqual(records.map(\.id), ["CVE-2026-9100"])
    }

    // MARK: Client and feed

    func testClientSendsTheQueryAndApiKeyHeader() async throws {
        let transport = RecordingTransport(body: NVDFixtures.emptyPageJSON)
        let client = NVDClient(transport: transport, limiter: RateLimiter(), apiKeyProvider: { "test-key" })
        _ = try await client.fetch(.appleCNA(from: .now, to: .now, resultsPerPage: 10))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "apiKey"), "test-key")
        XCTAssertTrue(request.url?.absoluteString.contains("sourceIdentifier=product-security%40apple.com") == true)
    }

    func testClientMapsHTTPStatusesToErrors() async {
        let cases: [(Int, NetworkError)] = [
            (403, .rateLimited(retryAfter: nil)),
            (503, .server(status: 503)),
            (400, .rejected(status: 400))
        ]
        for (status, expected) in cases {
            let client = NVDClient(transport: RecordingTransport(status: status), limiter: RateLimiter(), apiKeyProvider: { nil })
            do {
                _ = try await client.fetch(.cve("CVE-2026-0001"))
                XCTFail("Expected an error for HTTP \(status)")
            } catch {
                XCTAssertEqual(NetworkError.map(error), expected)
            }
        }
    }

    func testAppleFeedAsksEachSourceAndMergesDuplicates() async throws {
        let directory = Fixtures.temporaryDirectory(for: "feed")
        defer { try? FileManager.default.removeItem(at: directory) }

        let transport = RecordingTransport(body: NVDFixtures.appleRecordJSON)
        let service = VulnerabilityService(
            client: NVDClient(transport: transport, limiter: RateLimiter(), apiKeyProvider: { nil }),
            cache: VulnerabilityCache(directory: directory)
        )
        let result = try await service.fetchAppleFeed(from: Fixtures.referenceDate.addingTimeInterval(-30 * Fixtures.day),
                                                      to: Fixtures.referenceDate, markRefreshed: true)

        // The same record came back from every source and is kept once.
        XCTAssertEqual(result.vulnerabilities.map(\.id), ["CVE-2026-9001"])
        XCTAssertTrue(result.isComplete)

        let urls = transport.requests.compactMap { $0.url?.absoluteString }
        XCTAssertEqual(urls.count, 4)
        XCTAssertEqual(urls.filter { $0.contains("sourceIdentifier=") }.count, 1)
        XCTAssertEqual(urls.filter { $0.contains("virtualMatchString=cpe%3A2.3%3Ao%3Aapple%3A%2A") }.count, 1)
        XCTAssertEqual(urls.filter { $0.contains("virtualMatchString=cpe%3A2.3%3Aa%3Aapple%3A%2A") }.count, 1)
        XCTAssertEqual(urls.filter { $0.contains("virtualMatchString=cpe%3A2.3%3Ah%3Aapple%3A%2A") }.count, 1)
    }

    func testARejectedSourceIsReportedAndTheOthersStillRun() async throws {
        let directory = Fixtures.temporaryDirectory(for: "rejected")
        defer { try? FileManager.default.removeItem(at: directory) }

        let transport = RecordingTransport { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("sourceIdentifier=") {
                return HTTPResult(data: Data(), statusCode: 400, retryAfter: nil)
            }
            return HTTPResult(data: Data(NVDFixtures.appleRecordJSON.utf8), statusCode: 200, retryAfter: nil)
        }
        let service = VulnerabilityService(
            client: NVDClient(transport: transport, limiter: RateLimiter(), apiKeyProvider: { nil }),
            cache: VulnerabilityCache(directory: directory)
        )
        let result = try await service.fetchAppleFeed(from: .now.addingTimeInterval(-Fixtures.day), to: .now, markRefreshed: true)

        XCTAssertEqual(result.vulnerabilities.count, 1)
        XCTAssertFalse(result.isComplete, "A skipped source must mark the refresh incomplete")
        XCTAssertEqual(result.notices.count, 1)
        XCTAssertTrue(result.notices[0].contains("HTTP 400"))
    }
}
