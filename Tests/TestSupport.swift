import Foundation
@testable import Pwned

/// An HTTP transport that records requests and answers from a closure.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let respond: @Sendable (URLRequest) throws -> HTTPResult

    init(respond: @escaping @Sendable (URLRequest) throws -> HTTPResult) {
        self.respond = respond
    }

    /// Always answers with the same status and body.
    convenience init(status: Int = 200, body: String = "", retryAfter: TimeInterval? = nil) {
        self.init { _ in HTTPResult(data: Data(body.utf8), statusCode: status, retryAfter: retryAfter) }
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        lock.withLock { recorded.append(request) }
        return try respond(request)
    }
}

/// NVD responses used by several test files. The shapes follow the NVD CVE API
/// 2.0; the records themselves are invented.
enum NVDFixtures {
    static let appleRecordJSON = """
    {"resultsPerPage":1,"startIndex":0,"totalResults":1,"vulnerabilities":[{"cve":{
      "id":"CVE-2026-9001","sourceIdentifier":"product-security@apple.com",
      "published":"2026-10-20T10:00:00.000","lastModified":"2026-10-21T10:00:00.000","vulnStatus":"Analyzed",
      "descriptions":[{"lang":"en","value":"A memory issue in WebKit was addressed with improved checks. This issue is fixed in iOS 26.1."}],
      "metrics":{"cvssMetricV31":[{"source":"nvd@nist.gov","type":"Primary","cvssData":{"version":"3.1","vectorString":"CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H","baseScore":8.8,"baseSeverity":"HIGH"}}]},
      "configurations":[{"nodes":[{"operator":"OR","negate":false,"cpeMatch":[{"vulnerable":true,"criteria":"cpe:2.3:o:apple:iphone_os:*:*:*:*:*:*:*:*","versionEndExcluding":"26.1"}]}]}],
      "references":[{"url":"https://support.apple.com/en-us/124567","source":"product-security@apple.com","tags":["Vendor Advisory"]}]
    }}]}
    """

    /// Third-party software that runs on macOS: the vulnerable product is not Apple's.
    static let runsOnMacOSJSON = """
    {"resultsPerPage":1,"startIndex":0,"totalResults":1,"vulnerabilities":[{"cve":{
      "id":"CVE-2026-9002","sourceIdentifier":"cve@example.org",
      "published":"2026-10-22T10:00:00.000","lastModified":"2026-10-22T10:00:00.000","vulnStatus":"Analyzed",
      "descriptions":[{"lang":"en","value":"Example Editor before 2.0 allows local file disclosure."}],
      "configurations":[{"operator":"AND","nodes":[
        {"operator":"OR","negate":false,"cpeMatch":[{"vulnerable":true,"criteria":"cpe:2.3:a:example:editor:*:*:*:*:*:*:*:*","versionEndExcluding":"2.0"}]},
        {"operator":"OR","negate":false,"cpeMatch":[{"vulnerable":false,"criteria":"cpe:2.3:o:apple:macos:-:*:*:*:*:*:*:*"}]}
      ]}],
      "references":[]
    }}]}
    """

    /// A negated node lists what must NOT be present, so it names no affected product.
    static let negatedNodeJSON = """
    {"resultsPerPage":1,"startIndex":0,"totalResults":1,"vulnerabilities":[{"cve":{
      "id":"CVE-2026-9003","sourceIdentifier":"cve@example.org",
      "published":"2026-10-23T10:00:00.000","lastModified":"2026-10-23T10:00:00.000",
      "descriptions":[{"lang":"en","value":"A flaw in Example Server when a plugin is absent."}],
      "configurations":[{"nodes":[
        {"operator":"OR","negate":false,"cpeMatch":[{"vulnerable":true,"criteria":"cpe:2.3:a:example:server:*:*:*:*:*:*:*:*"}]},
        {"operator":"OR","negate":true,"cpeMatch":[{"vulnerable":true,"criteria":"cpe:2.3:o:apple:macos:*:*:*:*:*:*:*:*"}]}
      ]}],
      "references":[]
    }}]}
    """

    static let emptyPageJSON = #"{"resultsPerPage":0,"startIndex":0,"totalResults":0,"vulnerabilities":[]}"#

    static func decode(_ json: String) throws -> [Vulnerability] {
        let response = try JSONDecoder().decode(NVDResponse.self, from: Data(json.utf8))
        return NVDMapper.vulnerabilities(from: response)
    }
}
