import SwiftUI

/// Root view: the native tab bar with exactly three destinations. Each one owns
/// its own navigation stack.
struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab(AppTab.discover.title, systemImage: AppTab.discover.systemImage, value: AppTab.discover) {
                DiscoverView()
            }

            Tab(AppTab.saved.title, systemImage: AppTab.saved.systemImage, value: AppTab.saved) {
                SavedView()
            }

            Tab(AppTab.info.title, systemImage: AppTab.info.systemImage, value: AppTab.info) {
                InfoView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(IntelligenceStore())
        .environment(ConnectivityMonitor())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
