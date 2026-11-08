import SwiftUI
import SwiftData

@main
struct PwnedApp: App {
    private let container = PersistenceController.makeContainer()

    @State private var router = AppRouter()
    @State private var store = IntelligenceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .environment(store)
        }
        .modelContainer(container)
    }
}
