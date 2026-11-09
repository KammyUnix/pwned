import SwiftUI

/// Root view: the native tab bar with the five primary sections plus the
/// system search tab that hosts universal search. Each section owns its own
/// navigation stack.
struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab(AppTab.discover.title, systemImage: AppTab.discover.systemImage, value: AppTab.discover) {
                DiscoverView()
            }

            Tab(AppTab.vulnerabilities.title, systemImage: AppTab.vulnerabilities.systemImage, value: AppTab.vulnerabilities) {
                VulnerabilitiesView()
            }

            Tab(AppTab.repositories.title, systemImage: AppTab.repositories.systemImage, value: AppTab.repositories) {
                RepositoriesView()
            }

            Tab(AppTab.laboratory.title, systemImage: AppTab.laboratory.systemImage, value: AppTab.laboratory) {
                LaboratoryView()
            }

            Tab(AppTab.notebook.title, systemImage: AppTab.notebook.systemImage, value: AppTab.notebook) {
                NotebookView()
            }

            Tab(value: AppTab.search, role: .search) {
                UniversalSearchView()
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
