import SwiftUI
import SwiftData

@main
struct PwnedApp: App {
    private let container = PersistenceController.makeContainer()

    @State private var router = AppRouter()
    @State private var store = IntelligenceStore(service: VulnerabilityService.live())
    @State private var connectivity = ConnectivityMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(router)
                .environment(store)
                .environment(connectivity)
                .task {
                    connectivity.start()
                    await store.start()
                }
                .onChange(of: connectivity.isOnline) { _, isOnline in
                    if isOnline {
                        Task { await store.refreshIfStale() }
                    }
                }
        }
        .modelContainer(container)
    }
}
