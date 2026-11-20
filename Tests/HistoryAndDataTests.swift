import XCTest
import SwiftData
@testable import Pwned

/// History and data management run against an in-memory store.
final class HistoryAndDataTests: XCTestCase {
    @MainActor
    private struct TestStore {
        let container = PersistenceController.makeInMemoryContainer()
        var context: ModelContext { container.mainContext }

        func count<Model: PersistentModel>(_ type: Model.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<Model>())) ?? -1
        }

        func viewedIDs() -> Set<String> {
            Set(((try? context.fetch(FetchDescriptor<ViewedItem>())) ?? []).map(\.itemID))
        }
    }

    // MARK: Recently viewed

    @MainActor
    func testViewingIsRecordedWhenHistoryIsOn() {
        let store = TestStore()
        let defaults = makeIsolatedDefaults()

        store.context.noteViewed(.vulnerability, id: "CVE-2026-1", title: "CVE-2026-1", defaults: defaults)

        XCTAssertEqual(store.viewedIDs(), ["CVE-2026-1"])
    }

    @MainActor
    func testViewingIsNotRecordedWhenHistoryIsOff() {
        let store = TestStore()
        let defaults = makeIsolatedDefaults()
        defaults.set(false, forKey: AppSettings.keepRecentKey)

        store.context.noteViewed(.vulnerability, id: "CVE-2026-1", title: "CVE-2026-1", defaults: defaults)

        XCTAssertEqual(store.count(ViewedItem.self), 0)
    }

    @MainActor
    func testOnlyTheChosenNumberOfItemsIsKept() {
        let store = TestStore()
        let defaults = makeIsolatedDefaults()
        defaults.set(10, forKey: AppSettings.recentLimitKey)

        for index in 0..<12 {
            store.context.noteViewed(.vulnerability, id: "item-\(index)", title: "Item \(index)", defaults: defaults)
            // Give each item a distinct, increasing time so "oldest" is certain.
            if let item = try? store.context.fetch(FetchDescriptor<ViewedItem>()).first(where: { $0.itemID == "item-\(index)" }) {
                item.viewedAt = Date(timeIntervalSince1970: 1_000_000 + Double(index))
            }
        }

        XCTAssertEqual(store.count(ViewedItem.self), 10)
        XCTAssertFalse(store.viewedIDs().contains("item-0"))
        XCTAssertFalse(store.viewedIDs().contains("item-1"))
        XCTAssertTrue(store.viewedIDs().contains("item-11"))
    }

    @MainActor
    func testClearingRecentlyViewedKeepsEverythingElse() {
        let store = TestStore()
        let defaults = makeIsolatedDefaults()
        store.context.noteViewed(.note, id: "n", title: "Note", defaults: defaults)
        store.context.insert(ResearchNote(title: "Keep me"))
        store.context.noteSearched("webkit", defaults: defaults)

        store.context.clearRecentlyViewed()

        XCTAssertEqual(store.count(ViewedItem.self), 0)
        XCTAssertEqual(store.count(ResearchNote.self), 1)
        XCTAssertEqual(store.count(SearchHistoryEntry.self), 1)
    }

    // MARK: Search history

    @MainActor
    func testSearchesAreRecordedOnlyWhenTheyAreKept() {
        let store = TestStore()
        let defaults = makeIsolatedDefaults()

        store.context.noteSearched("kernel", defaults: defaults)
        XCTAssertEqual(store.count(SearchHistoryEntry.self), 1)

        defaults.set(false, forKey: AppSettings.keepSearchesKey)
        store.context.noteSearched("secure enclave", defaults: defaults)
        XCTAssertEqual(store.count(SearchHistoryEntry.self), 1)
    }

    @MainActor
    func testClearingSearchHistory() {
        let store = TestStore()
        let defaults = makeIsolatedDefaults()
        store.context.noteSearched("kernel", defaults: defaults)
        store.context.noteSearched("webkit", defaults: defaults)

        store.context.clearSearchHistory()

        XCTAssertEqual(store.count(SearchHistoryEntry.self), 0)
    }

    // MARK: Erase everything

    @MainActor
    func testEraseAllRemovesWhatTheUserCreated() {
        let store = TestStore()
        let defaults = makeIsolatedDefaults()
        let note = ResearchNote(title: "Research", body: "CVE-2026-1234")
        store.context.insert(note)
        store.context.link(noteID: note.id, kind: .vulnerability, entityID: "CVE-2026-1234",
                           displayName: "CVE-2026-1234", origin: .manual)
        store.context.toggleVulnerabilityBookmark("CVE-2026-1234")
        store.context.insert(RepositoryBookmark(owner: "KammyUnix", name: "pwned"))
        store.context.noteViewed(.vulnerability, id: "CVE-2026-1234", title: "CVE-2026-1234", defaults: defaults)
        store.context.noteSearched("kernel", defaults: defaults)

        XCTAssertGreaterThan(store.count(NoteReference.self), 0)

        store.context.eraseAllUserData()

        XCTAssertEqual(store.count(ResearchNote.self), 0)
        XCTAssertEqual(store.count(NoteReference.self), 0)
        XCTAssertEqual(store.count(VulnerabilityBookmark.self), 0)
        XCTAssertEqual(store.count(RepositoryBookmark.self), 0)
        XCTAssertEqual(store.count(ViewedItem.self), 0)
        XCTAssertEqual(store.count(SearchHistoryEntry.self), 0)
    }

    // MARK: Export

    @MainActor
    func testExportListsNewestNoteFirstWithItsText() {
        let older = ResearchNote(title: "Older", body: "First body")
        older.modifiedAt = Date(timeIntervalSince1970: 1_000)
        let newer = ResearchNote(title: "Newer", body: "Second body")
        newer.modifiedAt = Date(timeIntervalSince1970: 2_000)

        let markdown = NotesExport.markdown(for: [older, newer])

        let newerRange = markdown.range(of: "# Newer")
        let olderRange = markdown.range(of: "# Older")
        XCTAssertNotNil(newerRange)
        XCTAssertNotNil(olderRange)
        if let newerRange, let olderRange {
            XCTAssertLessThan(newerRange.lowerBound, olderRange.lowerBound)
        }
        XCTAssertTrue(markdown.contains("Second body"))
        XCTAssertTrue(markdown.contains("First body"))
    }

    @MainActor
    func testExportNamesUntitledNotesAndSkipsEmptyBodies() {
        let note = ResearchNote(title: "  ", body: "")
        let markdown = NotesExport.markdown(for: [note])
        XCTAssertTrue(markdown.hasPrefix("# Untitled Note"))
        XCTAssertFalse(markdown.contains("\n\n\n"))
    }

    @MainActor
    func testExportOfNoNotesIsEmpty() {
        XCTAssertEqual(NotesExport.markdown(for: []), "")
    }
}
