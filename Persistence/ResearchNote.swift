import Foundation
import SwiftData

/// A user-authored research note. Notes live in their own store and are never
/// touched by "Clear Cached Data".
@Model
final class ResearchNote {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var tags: [String] = []
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// CVE identifiers this note references.
    var relatedCVEIDs: [String] = []
    /// `owner/name` GitHub repository references.
    var relatedRepositories: [String] = []
    /// `ResearchTopic.id` slugs.
    var relatedTopicIDs: [String] = []

    init(title: String = "", body: String = "") {
        self.title = title
        self.body = body
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    func touch() {
        modifiedAt = Date()
    }
}
