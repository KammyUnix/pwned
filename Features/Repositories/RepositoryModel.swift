import Foundation
import Observation

/// A value that is being fetched, has arrived, or failed.
enum Loadable<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(GitHubError)

    var isLoading: Bool {
        switch self {
        case .idle, .loading: true
        case .loaded, .failed: false
        }
    }

    var error: GitHubError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// What the repository page shows: metadata, README and file tree fetched from
/// GitHub, and the analysis derived from the tree.
///
/// Nothing is persisted. Each visit to the page fetches again, so what is
/// shown is never older than the visit, and an offline device shows the error
/// instead of stale data.
@MainActor
@Observable
final class RepositoryModel {
    let reference: GitHubRepositoryReference
    private let client: GitHubClient

    private(set) var details: Loadable<GitHubRepositoryDetails> = .idle
    private(set) var readme: Loadable<String?> = .idle
    private(set) var tree: Loadable<GitHubTree> = .idle
    private(set) var analysis: RepositoryAnalysis?
    private(set) var fetchedAt: Date?

    init(reference: GitHubRepositoryReference, client: GitHubClient = .shared) {
        self.reference = reference
        self.client = client
    }

    var readmeText: String? {
        if case .loaded(let text) = readme { return text }
        return nil
    }

    /// Fetches once per visit; later calls do nothing until `reload()`.
    func load() async {
        guard case .idle = details else { return }
        await fetch()
    }

    func reload() async {
        await fetch()
    }

    private func fetch() async {
        details = .loading
        readme = .loading
        tree = .loading
        analysis = nil

        let reference = self.reference
        let client = self.client

        async let detailsResult = Self.attempt { try await client.repository(reference) }
        async let readmeResult = Self.attempt { try await client.readme(reference) }
        // The analysis walks every path, so it runs here with the download,
        // away from the main thread.
        async let treeResult = Self.attempt {
            let tree = try await client.tree(reference)
            return LoadedTree(tree: tree, analysis: RepositoryAnalysis.analyze(tree))
        }

        let (fetchedDetails, fetchedReadme, fetchedTree) = await (detailsResult, readmeResult, treeResult)

        // The page went away mid-request. Leave no half-loaded state behind.
        if Task.isCancelled {
            details = .idle
            readme = .idle
            tree = .idle
            return
        }

        switch fetchedDetails {
        case .success(let value): details = .loaded(value)
        case .failure(let error): details = .failed(error)
        }
        switch fetchedReadme {
        case .success(let value): readme = .loaded(value)
        case .failure(let error): readme = .failed(error)
        }
        switch fetchedTree {
        case .success(let value):
            tree = .loaded(value.tree)
            analysis = value.analysis
        case .failure(let error):
            tree = .failed(error)
        }

        if case .loaded = details { fetchedAt = Date() }
    }

    private struct LoadedTree: Sendable {
        let tree: GitHubTree
        let analysis: RepositoryAnalysis
    }

    nonisolated private static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, GitHubError> {
        do {
            return .success(try await work())
        } catch {
            return .failure(GitHubError.map(error))
        }
    }
}
