import Foundation
import SwiftData
import OSLog

/// Builds the app's SwiftData container.
///
/// Every model here is user data (notes, note references, bookmarks, history),
/// so they share one on-disk store. Cached API responses live in a separate file
/// (`VulnerabilityCache`) so that clearing caches can never delete notes.
///
/// `NoteReference` was added after the first release. A new entity is a
/// lightweight addition: existing notes, bookmarks and history are untouched.
enum PersistenceController {
    private static let logger = Logger(subsystem: "com.pwned.app", category: "Persistence")

    static let userDataSchema = Schema([
        ResearchNote.self,
        NoteReference.self,
        VulnerabilityBookmark.self,
        RepositoryBookmark.self,
        ViewedItem.self,
        SearchHistoryEntry.self
    ])

    /// The on-disk container. If the store cannot be opened, the app falls back
    /// to an in-memory container and logs the failure rather than crashing.
    @MainActor
    static func makeContainer() -> ModelContainer {
        do {
            // Local-only store. No CloudKit entitlement is requested.
            let configuration = ModelConfiguration("UserData", schema: userDataSchema, cloudKitDatabase: .none)
            return try ModelContainer(for: userDataSchema, configurations: [configuration])
        } catch {
            logger.error("Persistent store failed to open: \(error.localizedDescription, privacy: .public)")
            return makeInMemoryContainer()
        }
    }

    @MainActor
    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: userDataSchema, configurations: [configuration])
        } catch {
            fatalError("Unable to create an in-memory ModelContainer: \(error)")
        }
    }
}
