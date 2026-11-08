import Foundation

/// A parsed reference to a GitHub repository, derived purely from user input.
/// Holding one of these does not imply the repository exists.
struct GitHubRepositoryReference: Codable, Hashable, Sendable {
    var owner: String
    var name: String

    var fullName: String { "\(owner)/\(name)" }

    var webURL: URL {
        URL(string: "https://github.com")!
            .appendingPathComponent(owner)
            .appendingPathComponent(name)
    }
}

/// Lightweight repository metadata shown in lists.
struct RepositorySummary: Codable, Hashable, Identifiable, Sendable {
    var owner: String
    var name: String
    var summary: String
    var primaryLanguage: String?
    var stars: Int
    var updatedAt: Date
    var provenance: InformationProvenance

    var id: String { "\(owner)/\(name)" }
    var fullName: String { id }
    var isSample: Bool { provenance == .sample }
}
