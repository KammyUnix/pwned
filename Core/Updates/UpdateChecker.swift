import Foundation
import Observation

/// A published GitHub release.
struct ReleaseInfo: Equatable, Sendable {
    let tagName: String
    let name: String?
    /// The release notes, as Markdown.
    let notes: String
    let publishedAt: Date?
    let pageURL: URL
    let isPrerelease: Bool

    /// Nil when the tag isn't a version number.
    var version: SemanticVersion? { SemanticVersion(tagName) }

    var title: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? tagName : trimmed
    }

    /// The version as shown to people: the tag without a leading "v".
    var versionLabel: String {
        version?.description ?? tagName
    }
}

/// Where an update check stands.
enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    /// The installed version is the latest release.
    case upToDate(ReleaseInfo)
    case updateAvailable(ReleaseInfo)
    /// The installed version is newer than the latest release, as in a development build.
    case ahead(ReleaseInfo)
    /// The repository has no published release yet.
    case noRelease
    /// The device couldn't reach GitHub.
    case networkError(String)
    /// GitHub answered, but not with a usable release.
    case apiError(String)

    var release: ReleaseInfo? {
        switch self {
        case .upToDate(let release), .updateAvailable(let release), .ahead(let release): release
        default: nil
        }
    }
}

/// Reads the newest release of Pwned's repository from the GitHub Releases API.
///
/// `/releases/latest` returns the newest published release that is neither a
/// draft nor a pre-release, so development builds and pre-releases never count
/// as updates. Requests are anonymous and sent only when the user checks.
struct UpdateChecker: Sendable {
    static let shared = UpdateChecker()

    private let transport: any HTTPTransport
    private let repository: GitHubRepositoryReference

    init(
        transport: any HTTPTransport = URLSessionTransport(),
        repository: GitHubRepositoryReference = AppInfo.repository
    ) {
        self.transport = transport
        self.repository = repository
    }

    /// The latest release, or nil when none has been published.
    func latestRelease() async throws -> ReleaseInfo? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(repository.owner)/\(repository.name)/releases/latest"
        guard let url = components.url else { throw GitHubError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let result: HTTPResult
        do {
            result = try await transport.send(request)
        } catch {
            throw GitHubError.map(error)
        }

        switch result.statusCode {
        case 200:
            break
        case 404:
            return nil
        case 403, 429:
            throw GitHubError.rateLimited(retryAfter: result.retryAfter)
        case 500...599:
            throw GitHubError.server(status: result.statusCode)
        default:
            throw GitHubError.rejected(status: result.statusCode)
        }

        let dto: ReleaseDTO
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            dto = try decoder.decode(ReleaseDTO.self, from: result.data)
        } catch {
            throw GitHubError.invalidResponse
        }
        guard !dto.draft, let page = URL(string: dto.htmlUrl) else { return nil }

        return ReleaseInfo(
            tagName: dto.tagName,
            name: dto.name,
            notes: dto.body ?? "",
            publishedAt: NVDDate.parse(dto.publishedAt),
            pageURL: page,
            isPrerelease: dto.prerelease
        )
    }

    private struct ReleaseDTO: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let publishedAt: String?
        let htmlUrl: String
        let draft: Bool
        let prerelease: Bool
    }

    // MARK: Evaluation

    /// Compares the installed version with a release.
    static func status(installedVersion: String, release: ReleaseInfo) -> UpdateStatus {
        if release.isPrerelease { return .noRelease }
        guard let latest = release.version else {
            return .apiError("The latest release is tagged \u{201C}\(release.tagName)\u{201D}, which isn't a version number Pwned can compare.")
        }
        guard let installed = SemanticVersion(installedVersion) else {
            return .apiError("Pwned couldn't read its own version number (\(installedVersion)), so it can't compare it with the latest release.")
        }
        if latest > installed { return .updateAvailable(release) }
        if latest == installed { return .upToDate(release) }
        return .ahead(release)
    }

    /// The status to show for a failed request. Nil when the request was cancelled.
    static func status(for error: GitHubError) -> UpdateStatus? {
        switch error {
        case .cancelled:
            return nil
        case .offline:
            return .networkError("You're offline. Connect to the internet and check again.")
        case .timedOut:
            return .networkError("GitHub took too long to respond. Check again in a moment.")
        case .notFound:
            return .noRelease
        case .rateLimited, .server, .rejected, .invalidResponse, .emptyRepository, .tooLarge:
            return .apiError(error.localizedDescription)
        }
    }
}

/// Holds the update status for the Info page.
///
/// A check happens when the user asks, and optionally once per launch when
/// the Info page first appears. There is no background polling.
@MainActor
@Observable
final class UpdateModel {
    private(set) var status: UpdateStatus = .idle
    private(set) var lastChecked: Date?

    private let checker: UpdateChecker
    private let installedVersion: String
    private var hasChecked = false

    init(checker: UpdateChecker = .shared, installedVersion: String = AppInfo().version) {
        self.checker = checker
        self.installedVersion = installedVersion
    }

    /// Checks now, whatever happened before. Ignored while a check is running.
    func check(userInitiated: Bool = true) async {
        guard status != .checking else { return }
        let previous = status
        status = .checking
        hasChecked = true

        do {
            if let release = try await checker.latestRelease() {
                status = UpdateChecker.status(installedVersion: installedVersion, release: release)
            } else {
                status = .noRelease
            }
            lastChecked = Date()
            if userInitiated { Haptics.play(.success) }
        } catch {
            if let failed = UpdateChecker.status(for: GitHubError.map(error)) {
                status = failed
                lastChecked = Date()
            } else {
                status = previous
            }
        }
    }

    /// The once-per-launch check, when the preference allows it.
    func checkAutomatically(enabled: Bool) async {
        guard enabled, !hasChecked else { return }
        await check(userInitiated: false)
    }
}
