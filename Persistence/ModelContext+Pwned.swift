import Foundation
import SwiftData
import OSLog

private let persistenceLogger = Logger(subsystem: "com.pwned.app", category: "UserData")

extension ModelContext {
    private static var recentlyViewedLimit: Int { 50 }
    private static var searchHistoryLimit: Int { 30 }

    /// Saves pending changes, logging (not crashing) on failure.
    func saveLoggingFailure() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            persistenceLogger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Recently viewed

    /// Records that the user opened an item, moving it to the top of the list.
    func recordView(_ kind: ViewedItem.Kind, id itemID: String, title: String) {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<ViewedItem>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.itemID == itemID }
        )
        if let existing = try? fetch(descriptor).first {
            existing.viewedAt = Date()
            existing.title = title
        } else {
            insert(ViewedItem(kind: kind, itemID: itemID, title: title))
        }
        trim(ViewedItem.self, sortedBy: \.viewedAt, keeping: Self.recentlyViewedLimit)
        saveLoggingFailure()
    }

    // MARK: Search history

    func recordSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let descriptor = FetchDescriptor<SearchHistoryEntry>(
            predicate: #Predicate { $0.query == trimmed }
        )
        if let existing = try? fetch(descriptor).first {
            existing.searchedAt = Date()
        } else {
            insert(SearchHistoryEntry(query: trimmed))
        }
        trim(SearchHistoryEntry.self, sortedBy: \.searchedAt, keeping: Self.searchHistoryLimit)
        saveLoggingFailure()
    }

    // MARK: Bookmarks

    func bookmarks(forCVE cveID: String) -> [VulnerabilityBookmark] {
        let descriptor = FetchDescriptor<VulnerabilityBookmark>(
            predicate: #Predicate { $0.cveID == cveID }
        )
        return (try? fetch(descriptor)) ?? []
    }

    /// Adds or removes a bookmark. Returns true if the CVE is bookmarked afterwards.
    @discardableResult
    func toggleVulnerabilityBookmark(_ cveID: String) -> Bool {
        let existing = bookmarks(forCVE: cveID)
        if existing.isEmpty {
            insert(VulnerabilityBookmark(cveID: cveID))
            saveLoggingFailure()
            return true
        }
        for bookmark in existing { delete(bookmark) }
        saveLoggingFailure()
        return false
    }

    // MARK: Helpers

    /// Deletes everything beyond the newest `limit` items.
    private func trim<T: PersistentModel>(
    _ type: T.Type,
    sortedBy keyPath: KeyPath<T, Date>,
    keeping limit: Int
) {
    let descriptor = FetchDescriptor<T>()
    guard let items = try? fetch(descriptor) else { return }

    let overflow = items
        .sorted { $0[keyPath: keyPath] > $1[keyPath: keyPath] }
        .dropFirst(limit)

    for item in overflow {
        delete(item)
    }
}
}
