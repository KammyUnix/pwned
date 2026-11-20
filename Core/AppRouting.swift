import SwiftUI
import Observation

/// The app's three primary destinations, in tab bar order.
///
/// Search lives inside Discover, and everything else (repositories, the
/// laboratory, settings) is pushed onto one of these three stacks, so the tab
/// bar never grows.
enum AppTab: String, Hashable, CaseIterable {
    case discover
    case saved
    case info

    var title: String {
        switch self {
        case .discover: "Discover"
        case .saved: "Saved"
        case .info: "Info"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "binoculars"
        case .saved: "bookmark"
        case .info: "info.circle"
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
    /// Uncertain Apple candidates the classifier kept out of the feed.
    case candidates
    case openRepository
    case laboratory
    case settings
    /// The development sample data screen (reached only through the Info tab).
    case sampleData
}

/// Owns tab selection and per-tab navigation state so that search results,
/// note links and dashboard items can jump to the right place.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab

    /// A web page shown in an in-app browser sheet, when the user prefers that
    /// to leaving the app.
    var presentedWebPage: WebPage?

    init(selectedTab: AppTab = .discover) {
        self.selectedTab = selectedTab
    }

    var discoverPath = NavigationPath()
    var savedPath = NavigationPath()
    var infoPath = NavigationPath()

    /// Text handed to Discover's search field by a "search for" link.
    var pendingDiscoverQuery: String?

    /// Opens a search result in the tab that owns it.
    func open(_ target: SearchTarget) {
        switch target {
        case .vulnerability(let id):
            discoverPath = NavigationPath([AppRoute.vulnerability(id)])
            selectedTab = .discover
        case .vulnerabilityQuery(let query):
            discoverPath = NavigationPath()
            pendingDiscoverQuery = query
            selectedTab = .discover
        case .researchTopic(let id):
            discoverPath = NavigationPath([AppRoute.researchTopic(id)])
            selectedTab = .discover
        case .repository(let reference):
            discoverPath = NavigationPath([AppRoute.repository(reference)])
            selectedTab = .discover
        case .note(let id):
            savedPath = NavigationPath([AppRoute.note(id)])
            selectedTab = .saved
        }
    }

    /// Decides what happens when a link is tapped. Web links open in the
    /// in-app browser when that preference is on; everything else goes to the system.
    func handleLink(_ url: URL, opensInApp: Bool = AppSettings.opensLinksInApp()) -> OpenURLAction.Result {
        if let route = AppRoute(linkURL: url) {
            push(route)
            return .handled
        }
        guard opensInApp, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .systemAction
        }
        presentedWebPage = WebPage(url: url)
        return .handled
    }

    /// Pushes a route onto the stack of the tab the user is looking at, so
    /// following a link from a note keeps "Back" returning to the note.
    func push(_ route: AppRoute) {
        switch selectedTab {
        case .discover: discoverPath.append(route)
        case .saved: savedPath.append(route)
        case .info: infoPath.append(route)
        }
    }
}

/// A web page to show in the in-app browser.
struct WebPage: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}
