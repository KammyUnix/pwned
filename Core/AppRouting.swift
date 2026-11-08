import SwiftUI
import Observation

/// The app's primary sections, in tab bar order. `search` is the system search
/// tab (`TabRole.search`) that hosts universal search.
enum AppTab: Hashable, CaseIterable {
    case discover
    case vulnerabilities
    case repositories
    case laboratory
    case notebook
    case search

    var title: String {
        switch self {
        case .discover: "Discover"
        case .vulnerabilities: "Vulnerabilities"
        case .repositories: "Repositories"
        case .laboratory: "Laboratory"
        case .notebook: "Notebook"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "binoculars"
        case .vulnerabilities: "exclamationmark.shield"
        case .repositories: "shippingbox"
        case .laboratory: "testtube.2"
        case .notebook: "note.text"
        case .search: "magnifyingglass"
        }
    }
}

/// A destination that can be pushed onto any tab's navigation stack.
enum AppRoute: Hashable {
    case vulnerability(String)
    case researchLibrary
    case researchTopic(String)
    case repository(GitHubRepositoryReference)
    case note(UUID)
}

/// Owns tab selection and per-tab navigation state so that search results and
/// dashboard items can jump to the right section.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .discover

    var discoverPath = NavigationPath()
    var vulnerabilitiesPath = NavigationPath()
    var repositoriesPath = NavigationPath()
    var notebookPath = NavigationPath()

    /// Text handed to the Vulnerabilities tab by a "Search In" result.
    var pendingVulnerabilityQuery: String?

    func open(_ target: SearchTarget) {
        switch target {
        case .vulnerability(let id):
            vulnerabilitiesPath = NavigationPath([AppRoute.vulnerability(id)])
            selectedTab = .vulnerabilities
        case .vulnerabilityQuery(let query):
            vulnerabilitiesPath = NavigationPath()
            pendingVulnerabilityQuery = query
            selectedTab = .vulnerabilities
        case .researchTopic(let id):
            discoverPath = NavigationPath([AppRoute.researchTopic(id)])
            selectedTab = .discover
        case .repository(let reference):
            repositoriesPath = NavigationPath([AppRoute.repository(reference)])
            selectedTab = .repositories
        case .note(let id):
            notebookPath = NavigationPath([AppRoute.note(id)])
            selectedTab = .notebook
        }
    }
}
