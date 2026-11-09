import Foundation

/// Sliding-window limiter that spaces out requests so the app stays inside
/// NVD's published limits: 5 requests per rolling 30 seconds without an API
/// key, 50 with one. The window is padded by two seconds to absorb latency.
actor RateLimiter {
    private static let unauthenticatedLimit = 5
    private static let authenticatedLimit = 50
    private static let window: TimeInterval = 32

    private var maxRequests = RateLimiter.unauthenticatedLimit
    private var timestamps: [Date] = []

    func configure(hasAPIKey: Bool) {
        maxRequests = hasAPIKey ? Self.authenticatedLimit : Self.unauthenticatedLimit
    }

    /// Suspends until a request slot is free, then reserves it. Throws if the
    /// calling task is cancelled while waiting.
    func acquire() async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            timestamps.removeAll { now.timeIntervalSince($0) >= Self.window }
            if timestamps.count < maxRequests {
                timestamps.append(now)
                return
            }
            let oldest = timestamps[0]
            let wait = max(Self.window - now.timeIntervalSince(oldest), 0.05)
            try await Task.sleep(for: .seconds(wait))
        }
    }

    /// Called when the server reports throttling: treat the whole window as used
    /// so the next request waits it out.
    func noteThrottled() {
        let now = Date()
        timestamps = Array(repeating: now, count: maxRequests)
    }
}
