import SwiftUI
import SwiftData

@main
struct PwnedApp: App {
    private let container = PersistenceController.makeContainer()

    @State private var router = AppRouter(selectedTab: AppSettings.launchTab())
    @State private var store = IntelligenceStore(service: VulnerabilityService.live())
    @State private var connectivity = ConnectivityMonitor()
    @State private var updates = UpdateModel()
    @State private var appIcon = AppIconModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appPreferences()
                .environment(router)
                .environment(store)
                .environment(connectivity)
                .environment(updates)
                .environment(appIcon)
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
