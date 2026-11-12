import XCTest
import SwiftData
@testable import Pwned

/// Note links are stored as rows with stable IDs. These tests run against an
/// in-memory store, so they exercise the same SwiftData code the app uses.
final class NoteReferenceTests: XCTestCase {
    /// Keeps the container alive for as long as the test uses its context.
    @MainActor
    private struct TestStore {
        let container = PersistenceController.makeInMemoryContainer()
        var context: ModelContext { container.mainContext }

        func note(_ body: String = "", title: String = "Note") -> ResearchNote {
            let note = ResearchNote(title: title, body: body)
            context.insert(note)
            return note
        }
    }

    // MARK: Creating and removing links

    @MainActor
    func testLinkingTheSameTargetTwiceKeepsOneRow() {
        let store = TestStore()
        let note = store.note()

        let first = store.context.link(noteID: note.id, kind: .vulnerability, entityID: "CVE-2024-1111",
                                       displayName: "CVE-2024-1111", origin: .manual)
        let second = store.context.link(noteID: note.id, kind: .vulnerability, entityID: "CVE-2024-1111",
                                        displayName: "CVE-2024-1111", origin: .automatic)

        XCTAssertTrue(first === second)
        XCTAssertEqual(store.context.noteReferences(forNote: note.id).count, 1)
    }

    @MainActor
    func testUnlinkingACVEHidesItInsteadOfDeletingIt() {
        let store = TestStore()
        let note = store.note()
        let reference = store.context.link(noteID: note.id, kind: .vulnerability, entityID: "CVE-2024-1111",
                                           displayName: "CVE-2024-1111", origin: .automatic)

        store.context.unlink(reference)

        XCTAssertTrue(store.context.noteReferences(forNote: note.id).isEmpty)
        let all = store.context.noteReferences(forNote: note.id, includeDismissed: true)
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].isDismissed)
    }

    @MainActor
    func testLinkingADismissedTargetBringsItBack() {
        let store = TestStore()
        let note = store.note()
        let reference = store.context.link(noteID: note.id, kind: .repository, entityID: "apple/swift-nio",
                                           displayName: "apple/swift-nio", origin: .automatic)
        store.context.unlink(reference)

        store.context.link(noteID: note.id, kind: .repository, entityID: "apple/swift-nio",
                           displayName: "apple/swift-nio", origin: .manual)

        let visible = store.context.noteReferences(forNote: note.id)
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible[0].origin, .manual)
    }

    @MainActor
    func testUnlinkingATechnologyDeletesTheRow() {
        let store = TestStore()
        let note = store.note()
        let reference = store.context.link(noteID: note.id, kind: .technology, entityID: "bootrom",
                                           displayName: "BootROM", origin: .manual)

        store.context.unlink(reference)

        XCTAssertTrue(store.context.noteReferences(forNote: note.id, includeDismissed: true).isEmpty)
    }

    // MARK: Automatic links

    @MainActor
    func testSyncLinksCVEsAndRepositoriesButNotSuggestions() {
        let store = TestStore()
        let body = "CVE-2024-1111, github.com/apple/swift-nio, the BootROM and iOS 18."
        let note = store.note(body)

        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: body))

        let keys = Set(store.context.noteReferences(forNote: note.id).map { "\($0.kindRaw):\($0.entityID)" })
        XCTAssertEqual(keys, ["vulnerability:CVE-2024-1111", "repository:apple/swift-nio"])
    }

    @MainActor
    func testSyncingTwiceCreatesNoDuplicates() {
        let store = TestStore()
        let body = "CVE-2024-1111 and CVE-2024-1111 again"
        let note = store.note(body)

        for _ in 0..<3 {
            store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: body))
        }
        XCTAssertEqual(store.context.noteReferences(forNote: note.id).count, 1)
    }

    @MainActor
    func testRemovingTheTextRemovesTheAutomaticLink() {
        let store = TestStore()
        let note = store.note("CVE-2024-1111")
        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: note.body))

        note.body = "nothing here now"
        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: note.body))

        XCTAssertTrue(store.context.noteReferences(forNote: note.id, includeDismissed: true).isEmpty)
    }

    @MainActor
    func testManualLinksSurviveEditsToTheText() {
        let store = TestStore()
        let note = store.note("no identifiers in this text")
        store.context.link(noteID: note.id, kind: .vulnerability, entityID: "CVE-2024-2222",
                           displayName: "CVE-2024-2222", origin: .manual)

        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: note.body))

        XCTAssertEqual(store.context.noteReferences(forNote: note.id).count, 1)
    }

    @MainActor
    func testADismissedLinkStaysHiddenWhileTheTextRemainsAndIsForgottenAfter() {
        let store = TestStore()
        var body = "see CVE-2024-1111"
        let note = store.note(body)
        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: body))
        let reference = store.context.noteReferences(forNote: note.id)[0]
        store.context.unlink(reference)

        // Still in the text: the link must not come back by itself.
        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: body))
        XCTAssertTrue(store.context.noteReferences(forNote: note.id).isEmpty)

        // Gone from the text: the record is forgotten, so typing it again links it again.
        body = "nothing"
        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: body))
        XCTAssertTrue(store.context.noteReferences(forNote: note.id, includeDismissed: true).isEmpty)

        body = "CVE-2024-1111 is back"
        store.context.syncAutomaticReferences(noteID: note.id, mentions: NoteLinker.mentions(in: body))
        XCTAssertEqual(store.context.noteReferences(forNote: note.id).count, 1)
    }

    // MARK: Older notes and deletion

    @MainActor
    func testLegacyLinksAreImportedOnceAndTheOldFieldsEmptied() {
        let store = TestStore()
        let note = store.note()
        note.relatedCVEIDs = ["cve-2024-1111"]
        note.relatedRepositories = ["Apple/Swift-NIO"]
        note.relatedTopicIDs = ["bootrom", "ios", "no-such-topic"]

        store.context.importLegacyLinks(for: note)
        store.context.importLegacyLinks(for: note)

        let keys = Set(store.context.noteReferences(forNote: note.id).map { "\($0.kindRaw):\($0.entityID)" })
        XCTAssertEqual(keys, [
            "vulnerability:CVE-2024-1111",
            "repository:apple/swift-nio",
            "technology:bootrom",
            "product:ios"
        ])
        XCTAssertTrue(note.relatedCVEIDs.isEmpty && note.relatedRepositories.isEmpty && note.relatedTopicIDs.isEmpty)
    }

    @MainActor
    func testDeletingANoteRemovesItsLinksAndLinksPointingAtIt() {
        let store = TestStore()
        let doomed = store.note(title: "Doomed")
        let other = store.note(title: "Other")
        store.context.link(noteID: doomed.id, kind: .technology, entityID: "xnu", displayName: "XNU", origin: .manual)
        store.context.link(noteID: other.id, kind: .note, entityID: doomed.id.uuidString,
                           displayName: "Doomed", origin: .manual)
        store.context.link(noteID: other.id, kind: .technology, entityID: "xnu", displayName: "XNU", origin: .manual)

        store.context.deleteReferences(forNote: doomed.id)

        XCTAssertTrue(store.context.noteReferences(forNote: doomed.id, includeDismissed: true).isEmpty)
        let remaining = store.context.noteReferences(forNote: other.id)
        XCTAssertEqual(remaining.map(\.kindRaw), ["technology"])
    }

    // MARK: Backlinks and search

    @MainActor
    func testBacklinksListNotesThatLinkToATarget() {
        let store = TestStore()
        let older = store.note(title: "Older")
        older.modifiedAt = Date(timeIntervalSince1970: 1_000)
        let newer = store.note(title: "Newer")
        newer.modifiedAt = Date(timeIntervalSince1970: 2_000)
        let unrelated = store.note(title: "Unrelated")

        store.context.link(noteID: older.id, kind: .vulnerability, entityID: "CVE-2024-1111", displayName: "x", origin: .manual)
        store.context.link(noteID: newer.id, kind: .vulnerability, entityID: "CVE-2024-1111", displayName: "x", origin: .automatic)
        let hidden = store.context.link(noteID: unrelated.id, kind: .vulnerability, entityID: "CVE-2024-1111",
                                        displayName: "x", origin: .automatic)
        store.context.unlink(hidden)

        let references = (try? store.context.fetch(FetchDescriptor<NoteReference>())) ?? []
        let backlinks = NoteBacklinks(references: references, notes: [older, newer, unrelated])

        XCTAssertEqual(backlinks.notes(kinds: [.vulnerability], entityID: "CVE-2024-1111").map(\.title), ["Newer", "Older"])
        XCTAssertTrue(backlinks.notes(kinds: [.technology], entityID: "CVE-2024-1111").isEmpty)
    }

    @MainActor
    func testRelatedNotesShareLinkedTargets() {
        let store = TestStore()
        let first = store.note(title: "First")
        let second = store.note(title: "Second")
        let third = store.note(title: "Third")

        for note in [first, second] {
            store.context.link(noteID: note.id, kind: .technology, entityID: "xnu", displayName: "XNU", origin: .manual)
            store.context.link(noteID: note.id, kind: .vulnerability, entityID: "CVE-2024-1111", displayName: "x", origin: .manual)
        }
        store.context.link(noteID: third.id, kind: .technology, entityID: "xnu", displayName: "XNU", origin: .manual)

        let references = (try? store.context.fetch(FetchDescriptor<NoteReference>())) ?? []
        let related = NoteBacklinks(references: references, notes: [first, second, third])
            .notesSharingReferences(with: first.id)

        XCTAssertEqual(related.map(\.note.title), ["Second", "Third"])
        XCTAssertEqual(related.map(\.shared), [2, 1])
    }

    @MainActor
    func testTopicPagesListRepositoriesFromNotesThatLinkTheTopic() {
        let store = TestStore()
        let note = store.note()
        store.context.link(noteID: note.id, kind: .technology, entityID: "xnu", displayName: "XNU", origin: .manual)
        store.context.link(noteID: note.id, kind: .repository, entityID: "apple-oss-distributions/xnu",
                           displayName: "apple-oss-distributions/xnu", origin: .manual)

        let references = (try? store.context.fetch(FetchDescriptor<NoteReference>())) ?? []
        let backlinks = NoteBacklinks(references: references, notes: [note])
        XCTAssertEqual(backlinks.repositoryIDs(alongsideTopic: "xnu"), ["apple-oss-distributions/xnu"])
        XCTAssertTrue(backlinks.repositoryIDs(alongsideTopic: "webkit").isEmpty)
    }

    @MainActor
    func testNotesAreFoundThroughWhatTheyLinkTo() {
        let store = TestStore()
        let note = store.note("An unrelated body.", title: "Heap study")
        store.context.link(noteID: note.id, kind: .repository, entityID: "apple/swift-nio",
                           displayName: "apple/swift-nio", origin: .manual)
        let references = (try? store.context.fetch(FetchDescriptor<NoteReference>())) ?? []

        XCTAssertEqual(SearchEngine.noteMatches(for: "swift-nio", in: [note], references: references).count, 1)
        XCTAssertTrue(SearchEngine.noteMatches(for: "swift-nio", in: [note], references: []).isEmpty)
    }
}
