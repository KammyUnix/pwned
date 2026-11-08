import Foundation
import Observation

/// Where the data currently shown in the app came from.
enum DataSourceState: Equatable {
    /// Built-in development data only. No live source has been queried.
    case sample
    /// Live data with the time it was last refreshed.
    case live(lastUpdated: Date)
}

/// Single source of truth for intelligence data shown across the app.
///
/// Phase 1 serves clearly labeled sample data. Phase 2 replaces the
/// vulnerability list with NVD/OSV/CISA data behind this same interface, so
/// views do not need to change.
@MainActor
@Observable
final class IntelligenceStore {
    private(set) var vulnerabilities: [Vulnerability]
    private(set) var appleAdvisories: [AppleAdvisory]
    private(set) var announcements: [SecurityAnnouncement]
    private(set) var repositories: [RepositorySummary]
    private(set) var state: DataSourceState

    init(
        vulnerabilities: [Vulnerability] = SampleData.vulnerabilities,
        appleAdvisories: [AppleAdvisory] = SampleData.appleAdvisories,
        announcements: [SecurityAnnouncement] = SampleData.announcements,
        repositories: [RepositorySummary] = SampleData.repositories,
        state: DataSourceState = .sample
    ) {
        self.vulnerabilities = vulnerabilities
        self.appleAdvisories = appleAdvisories
        self.announcements = announcements
        self.repositories = repositories
        self.state = state
    }

    var isShowingSampleData: Bool { state == .sample }

    var recentVulnerabilities: [Vulnerability] {
        vulnerabilities.sorted { $0.publishedAt > $1.publishedAt }
    }

    var recentAdvisories: [AppleAdvisory] {
        appleAdvisories.sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentRepositories: [RepositorySummary] {
        repositories.sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentAnnouncements: [SecurityAnnouncement] {
        announcements.sorted { $0.date > $1.date }
    }

    func vulnerability(id: String) -> Vulnerability? {
        vulnerabilities.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    func vulnerabilities(withIDs ids: [String]) -> [Vulnerability] {
        ids.compactMap { vulnerability(id: $0) }
    }
}
