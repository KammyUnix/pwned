import Foundation

// MARK: - Models

/// Metadata for one repository, as GitHub reports it. Nothing here is stored
/// on the device: it is fetched when a repository page opens.
struct GitHubRepositoryDetails: Equatable, Sendable {
    let fullName: String
    let description: String?
    let htmlURL: URL?
    let homepage: URL?
    let language: String?
    let stars: Int
    let forks: Int
    let openIssues: Int
    let defaultBranch: String
    let license: String?
    let topics: [String]
    let isArchived: Bool
    let isFork: Bool
    let sizeKilobytes: Int
    let createdAt: Date?
    let pushedAt: Date?
}

/// One path in a repository's file tree.
struct GitHubTreeEntry: Equatable, Hashable, Identifiable, Sendable {
    enum Kind: Sendable {
        case file
        case directory
        /// A pinned reference to another repository. Its contents aren't in this tree.
        case submodule
    }

    let path: String
    let kind: Kind
    /// Size in bytes. GitHub reports it for files only.
    let size: Int?

    var id: String { path }

    var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The directory that contains this entry, or "" for the top level.
    var parentPath: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }
}

/// The full file tree of the default branch.
struct GitHubTree: Equatable, Sendable {
    let entries: [GitHubTreeEntry]
    /// True when GitHub cut the listing short (very large repositories). What
    /// is shown is then a part of the repository, and is labelled that way.
    let isTruncated: Bool

    /// Entries directly inside `directory` ("" for the top level),
    /// folders first, then files, each in name order.
    func children(of directory: String) -> [GitHubTreeEntry] {
        entries
            .filter { $0.parentPath == directory }
            .sorted { lhs, rhs in
                let lhsIsFolder = lhs.kind != .file
                let rhsIsFolder = rhs.kind != .file
                if lhsIsFolder != rhsIsFolder { return lhsIsFolder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

/// A file's text, or the reason there is none.
struct GitHubFile: Equatable, Sendable {
    let path: String
    /// Nil when the file isn't text.
    let text: String?
    let byteCount: Int
}

// MARK: - Errors

enum GitHubError: Error, Equatable, Sendable {
    case notFound
    /// The repository exists but has no commits yet.
    case emptyRepository
    case offline
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case rejected(status: Int)
    case invalidResponse
    case tooLarge(byteCount: Int)
    case cancelled

    static func map(_ error: Error) -> GitHubError {
        if let github = error as? GitHubError { return github }
        switch NetworkError.map(error) {
        case .offline: return .offline
        case .timedOut: return .timedOut
        case .cancelled: return .cancelled
        case .rateLimited(let retryAfter): return .rateLimited(retryAfter: retryAfter)
        case .server(let status): return .server(status: status)
        case .rejected(let status): return .rejected(status: status)
        case .invalidResponse, .decoding: return .invalidResponse
        }
    }
}

extension GitHubError {
    /// False when asking again can't change the answer.
    var isRetryable: Bool {
        switch self {
        case .notFound, .emptyRepository, .tooLarge: false
        default: true
        }
    }
}

extension GitHubError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound:
            "GitHub has no public repository or file at this address. It may be private, renamed or deleted."
        case .emptyRepository:
            "This repository has no commits yet, so there are no files to show."
        case .offline:
            "You're offline. Pwned doesn't keep repository data on this device, so there is nothing to show until you reconnect."
        case .timedOut:
            "GitHub took too long to respond. Try again in a moment."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter >= 1 {
                "GitHub's limit for requests without an account was reached. Try again in about \(Int(retryAfter.rounded(.up))) seconds."
            } else {
                "GitHub's limit for requests without an account was reached (60 per hour). Try again later."
            }
        case .server(let status):
            "GitHub is unavailable right now (HTTP \(status)). Try again later."
        case .rejected(let status):
            "GitHub rejected the request (HTTP \(status))."
        case .invalidResponse:
            "The response from GitHub couldn't be read."
        case .tooLarge(let byteCount):
            "This file is \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)), too large to open here."
        case .cancelled:
            "The request was cancelled."
        }
    }
}

// MARK: - Client

/// Reads public repository data from the GitHub REST API without an account.
///
/// Requests are read-only and anonymous (60 per hour per network address). No
/// credentials are sent or stored. The response shapes used here were checked
/// against the live API: `/repos/{o}/{r}`, `/readme` and `/contents/{path}`
/// with the raw media type, and `/git/trees/HEAD?recursive=1`.
struct GitHubClient: Sendable {
    /// Files larger than this aren't downloaded for inspection.
    static let maxFileBytes = 512 * 1024
    /// Text beyond this many bytes is cut when shown.
    static let maxDisplayBytes = 200 * 1024

    /// The client the app uses. Stateless, so one is shared.
    static let shared = GitHubClient()

    private let transport: any HTTPTransport

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func repository(_ reference: GitHubRepositoryReference) async throws -> GitHubRepositoryDetails {
        let data = try await get(path: Self.repositoryPath(reference), accept: Self.jsonType)
        let dto: RepositoryDTO
        do {
            dto = try Self.makeDecoder().decode(RepositoryDTO.self, from: data)
        } catch {
            throw GitHubError.invalidResponse
        }
        return dto.details
    }

    /// The README as text, or nil when the repository has none.
    func readme(_ reference: GitHubRepositoryReference) async throws -> String? {
        do {
            let data = try await get(path: Self.repositoryPath(reference) + "/readme", accept: Self.rawType)
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return Self.truncated(text)
        } catch GitHubError.notFound {
            return nil
        }
    }

    /// Every path on the default branch.
    func tree(_ reference: GitHubRepositoryReference) async throws -> GitHubTree {
        let data = try await get(
            path: Self.repositoryPath(reference) + "/git/trees/HEAD",
            query: [URLQueryItem(name: "recursive", value: "1")],
            accept: Self.jsonType
        )
        let dto: TreeDTO
        do {
            dto = try Self.makeDecoder().decode(TreeDTO.self, from: data)
        } catch {
            throw GitHubError.invalidResponse
        }
        return GitHubTree(entries: dto.tree.compactMap(\.entry), isTruncated: dto.truncated ?? false)
    }

    /// One file from the default branch. `size` is the size the tree reported,
    /// used to refuse oversized files before downloading them.
    func file(_ reference: GitHubRepositoryReference, path: String, size: Int?) async throws -> GitHubFile {
        if let size, size > Self.maxFileBytes {
            throw GitHubError.tooLarge(byteCount: size)
        }
        let data = try await get(
            path: Self.repositoryPath(reference) + "/contents/" + path,
            accept: Self.rawType
        )
        if data.count > Self.maxFileBytes {
            throw GitHubError.tooLarge(byteCount: data.count)
        }
        // A NUL byte or invalid UTF-8 means this is not source text.
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            return GitHubFile(path: path, text: nil, byteCount: data.count)
        }
        return GitHubFile(path: path, text: Self.truncated(text), byteCount: data.count)
    }

    // MARK: Requests

    private static let jsonType = "application/vnd.github+json"
    private static let rawType = "application/vnd.github.raw+json"

    private static func repositoryPath(_ reference: GitHubRepositoryReference) -> String {
        "/repos/\(reference.owner)/\(reference.name)"
    }

    private func get(path: String, query: [URLQueryItem] = [], accept: String) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GitHubError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let result: HTTPResult
        do {
            result = try await transport.send(request)
        } catch {
            throw GitHubError.map(error)
        }

        switch result.statusCode {
        case 200:
            return result.data
        case 404:
            throw GitHubError.notFound
        case 409:
            throw GitHubError.emptyRepository
        case 403, 429:
            // GitHub signals its request limit with 403 or 429; a 403 can also
            // mean the resource is blocked, so the message stays general.
            throw GitHubError.rateLimited(retryAfter: result.retryAfter)
        case 500...599:
            throw GitHubError.server(status: result.statusCode)
        default:
            throw GitHubError.rejected(status: result.statusCode)
        }
    }

    private static func truncated(_ text: String) -> String {
        guard text.utf8.count > maxDisplayBytes else { return text }
        // Cut on a character boundary, never in the middle of one.
        var end = text.startIndex
        var count = 0
        for index in text.indices {
            count += text[index].utf8.count
            if count > maxDisplayBytes { break }
            end = text.index(after: index)
        }
        return String(text[..<end])
    }

    // MARK: Decoding

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private struct RepositoryDTO: Decodable {
        struct License: Decodable {
            let name: String?
            let spdxId: String?
        }

        let fullName: String
        let description: String?
        let htmlUrl: String?
        let homepage: String?
        let language: String?
        let stargazersCount: Int?
        let forksCount: Int?
        let openIssuesCount: Int?
        let defaultBranch: String?
        let license: License?
        let topics: [String]?
        let archived: Bool?
        let fork: Bool?
        let size: Int?
        let createdAt: String?
        let pushedAt: String?

        var details: GitHubRepositoryDetails {
            let licenseName: String?
            if let spdx = license?.spdxId, spdx != "NOASSERTION" {
                licenseName = spdx
            } else {
                licenseName = license?.name
            }
            let homepageText = homepage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return GitHubRepositoryDetails(
                fullName: fullName,
                description: description,
                htmlURL: htmlUrl.flatMap { URL(string: $0) },
                homepage: homepageText.isEmpty ? nil : URL(string: homepageText),
                language: language,
                stars: stargazersCount ?? 0,
                forks: forksCount ?? 0,
                openIssues: openIssuesCount ?? 0,
                defaultBranch: defaultBranch ?? "HEAD",
                license: licenseName,
                topics: topics ?? [],
                isArchived: archived ?? false,
                isFork: fork ?? false,
                sizeKilobytes: size ?? 0,
                createdAt: createdAt.flatMap(GitHubClient.date(from:)),
                pushedAt: pushedAt.flatMap(GitHubClient.date(from:))
            )
        }
    }

    private struct TreeDTO: Decodable {
        struct Node: Decodable {
            let path: String
            let type: String
            let size: Int?

            var entry: GitHubTreeEntry? {
                switch type {
                case "blob": GitHubTreeEntry(path: path, kind: .file, size: size)
                case "tree": GitHubTreeEntry(path: path, kind: .directory, size: nil)
                case "commit": GitHubTreeEntry(path: path, kind: .submodule, size: nil)
                default: nil
                }
            }
        }

        let tree: [Node]
        let truncated: Bool?
    }

    /// GitHub timestamps look like `2026-11-08T06:09:55Z`, which `NVDDate`
    /// reads as UTC.
    static func date(from text: String) -> Date? {
        NVDDate.parse(text)
    }
}
