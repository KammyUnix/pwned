import Foundation

/// One decoded page of NVD results.
struct NVDPage: Sendable {
    /// Records mapped to the app model. Malformed CVEs are skipped.
    let vulnerabilities: [Vulnerability]
    /// How many CVE entries the server returned, before any were skipped.
    let returnedCount: Int
    /// Total matches for the query, as reported by NVD.
    let totalResults: Int
    let startIndex: Int
}

/// Client for the NVD CVE API 2.0.
///
/// Every request first waits for a slot in the shared `RateLimiter`. The API
/// key is optional; it is read at request time, sent only in the `apiKey`
/// header and never logged.
struct NVDClient: Sendable {
    let transport: any HTTPTransport
    let limiter: RateLimiter
    let apiKeyProvider: @Sendable () -> String?

    func fetch(_ query: NVDQuery) async throws -> NVDPage {
        let rawKey = apiKeyProvider()
        let key: String? = (rawKey?.isEmpty == false) ? rawKey : nil
        await limiter.configure(hasAPIKey: key != nil)
        try await limiter.acquire()

        var request = URLRequest(url: try query.url())
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key {
            request.setValue(key, forHTTPHeaderField: "apiKey")
        }

        let result = try await transport.send(request)

        switch result.statusCode {
        case 200:
            break
        case 403, 429:
            // NVD throttles with an error status. A 403 can also mean a rejected
            // API key, so the message stays generic about the cause.
            await limiter.noteThrottled()
            throw NetworkError.rateLimited(retryAfter: result.retryAfter)
        case 500...599:
            throw NetworkError.server(status: result.statusCode)
        default:
            throw NetworkError.rejected(status: result.statusCode)
        }

        let response: NVDResponse
        do {
            response = try JSONDecoder().decode(NVDResponse.self, from: result.data)
        } catch {
            throw NetworkError.decoding("The response was not valid NVD JSON.")
        }

        return NVDPage(
            vulnerabilities: NVDMapper.vulnerabilities(from: response),
            returnedCount: response.vulnerabilities.count,
            totalResults: response.totalResults ?? response.vulnerabilities.count,
            startIndex: response.startIndex ?? query.startIndex
        )
    }
}
