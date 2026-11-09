import Foundation

/// Failures from talking to a remote data source, reduced to cases the UI can
/// explain to the user.
enum NetworkError: Error, Equatable, Sendable {
    case offline
    case timedOut
    /// The server asked us to slow down (HTTP 403 or 429 from NVD).
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case rejected(status: Int)
    case invalidResponse
    case decoding(String)
    case cancelled

    /// Converts any error thrown by URLSession or Swift concurrency.
    static func map(_ error: Error) -> NetworkError {
        if let network = error as? NetworkError { return network }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost,
                 .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed:
                return .offline
            case .timedOut:
                return .timedOut
            case .cancelled:
                return .cancelled
            default:
                return .invalidResponse
            }
        }
        return .invalidResponse
    }
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .offline:
            "You're offline. Showing data saved on this device."
        case .timedOut:
            "NVD took too long to respond. Try again in a moment."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter >= 1 {
                "NVD rate limit reached. Try again in about \(Int(retryAfter.rounded(.up))) seconds."
            } else {
                "NVD rate limit reached. Try again in about 30 seconds."
            }
        case .server(let status):
            "NVD is unavailable right now (HTTP \(status)). Try again later."
        case .rejected(let status):
            "NVD rejected the request (HTTP \(status))."
        case .invalidResponse:
            "The response from NVD couldn't be read."
        case .decoding(let detail):
            "The data from NVD couldn't be decoded. \(detail)"
        case .cancelled:
            "The request was cancelled."
        }
    }
}
