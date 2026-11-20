import Foundation
import SwiftData

/// History and data management that follow the user's preferences.
///
/// `recordView` and `recordSearch` (in `ModelContext+Pwned.swift`) always
/// record. Screens call the `note…` functions here instead, which check the
/// history preferences first.
extension ModelContext {
    /// Records that an item was opened, unless "Keep Recently Viewed" is off.
    /// Keeps at most the number of items the user chose.
    func noteViewed(
        _ kind: ViewedItem.Kind,
        id itemID: String,
        title: String,
        defaults: UserDefaults = .standard
    ) {
        guard AppSettings.bool(AppSettings.keepRecentKey, default: AppSettings.Default.keepRecent, in: defaults) else {
            return
        }
        recordView(kind, id: itemID, title: title)
        let limit = AppSettings.int(AppSettings.recentLimitKey, default: AppSettings.Default.recentLimit, in: defaults)
        trimViewedItems(keeping: limit)
        saveLoggingFailure()
    }

    /// Records a search, unless "Keep Search History" is off.
    func noteSearched(_ query: String, defaults: UserDefaults = .standard) {
        guard AppSettings.bool(AppSettings.keepSearchesKey, default: AppSettings.Default.keepSearches, in: defaults) else {
            return
        }
        recordSearch(query)
    }

    /// Deletes all but the newest `limit` recently viewed items.
    func trimViewedItems(keeping limit: Int) {
        guard let items = try? fetch(FetchDescriptor<ViewedItem>()) else { return }
        let overflow = items
            .sorted { $0.viewedAt > $1.viewedAt }
            .dropFirst(max(limit, 1))
        for item in overflow {
            delete(item)
        }
    }

    func clearRecentlyViewed() {
        try? delete(model: ViewedItem.self)
        saveLoggingFailure()
    }

    func clearSearchHistory() {
        try? delete(model: SearchHistoryEntry.self)
        saveLoggingFailure()
    }

    /// Deletes everything the user created: notes, links, bookmarks and history.
    /// Downloaded vulnerability records (the cache) and preferences are separate
    /// and are not touched.
    func eraseAllUserData() {
        try? delete(model: ResearchNote.self)
        try? delete(model: NoteReference.self)
        try? delete(model: VulnerabilityBookmark.self)
        try? delete(model: RepositoryBookmark.self)
        try? delete(model: ViewedItem.self)
        try? delete(model: SearchHistoryEntry.self)
        saveLoggingFailure()
    }
}

/// Notes as a single Markdown document, for sharing or backup.
enum NotesExport {
    /// Newest note first. Each note becomes a level-one heading followed by its text.
    static func markdown(for notes: [ResearchNote]) -> String {
        let ordered = notes.sorted { $0.modifiedAt > $1.modifiedAt }
        return ordered.map { note in
            var section = "# \(note.displayTitle)\n"
            section += "\nCreated \(note.createdAt.formatted(date: .abbreviated, time: .shortened)). "
            section += "Modified \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened)).\n"
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                section += "\n\(body)\n"
            }
            return section
        }
        .joined(separator: "\n---\n\n")
    }
}
