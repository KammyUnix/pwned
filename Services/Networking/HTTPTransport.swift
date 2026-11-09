import Foundation

/// The parts of an HTTP response the app cares about, as plain Sendable values.
struct HTTPResult: Sendable {
    let data: Data
    let statusCode: Int
    /// Parsed `Retry-After` header in seconds, when the server sent one.
    let retryAfter: TimeInterval?
}

/// Abstraction over URLSession so networking can be swapped out in tests.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            // Pwned keeps its own cache, so skip URLSession's HTTP cache and
            // fail fast when offline instead of waiting for connectivity.
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 60
            configuration.httpAdditionalHeaders = ["User-Agent": "Pwned/1.0 (iOS research app)"]
            self.session = URLSession(configuration: configuration)
        }
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            return HTTPResult(data: data, statusCode: http.statusCode, retryAfter: retryAfter)
        } catch {
            throw NetworkError.map(error)
        }
    }
}
