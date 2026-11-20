import SwiftUI

/// Root view: the native tab bar with exactly three destinations. Each one owns
/// its own navigation stack.
struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppSettings.collapseTabBarKey) private var collapsesTabBar = AppSettings.Default.collapseTabBar

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
        .tabBarMinimizeBehavior(collapsesTabBar ? .onScrollDown : .never)
        .environment(\.openURL, OpenURLAction { url in
            router.handleLink(url)
        })
        .sheet(item: $router.presentedWebPage) { page in
            SafariView(url: page.url)
                .ignoresSafeArea()
        }
        .onChange(of: router.selectedTab) { _, tab in
            // "Last Used" under Start Tab reads this at the next launch.
            UserDefaults.standard.set(tab.rawValue, forKey: AppSettings.lastTabKey)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(IntelligenceStore())
        .environment(ConnectivityMonitor())
        .environment(UpdateModel())
        .environment(AppIconModel())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
