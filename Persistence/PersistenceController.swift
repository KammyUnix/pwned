import Foundation
import SwiftData
import OSLog

/// Builds the app's SwiftData container.
///
/// All Phase 1 models are user data (notes, bookmarks, history), so they share
/// one on-disk store. Cached API responses introduced in Phase 2 will live in a
/// separate store so that clearing caches can never delete notes.
enum PersistenceController {
    private static let logger = Logger(subsystem: "com.pwned.app", category: "Persistence")

    static let userDataSchema = Schema([
        ResearchNote.self,
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
