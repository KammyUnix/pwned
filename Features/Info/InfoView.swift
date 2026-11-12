import SwiftUI

/// The app's identity, the one entry point to Settings, and credits.
struct InfoView: View {
    @Environment(AppRouter.self) private var router

    private let info = AppInfo()

    /// The exact credit line. Do not reword.
    static let specialThanks = "Special thanks to: underwell, painterindebt, mintchoco for supporting idea❤️"

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.infoPath) {
            List {
                identitySection

                Section {
                    NavigationLink(value: AppRoute.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                Section {
                    Text("Pwned reads public vulnerability data from the National Vulnerability Database and keeps what it downloads on this device. Your notes, bookmarks and history never leave it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }

                Section {
                    Text(Self.specialThanks)
                } header: {
                    Text("Special Thanks")
                }
            }
            .navigationTitle("Info")
            .appRouteDestinations()
        }
    }

    private var identitySection: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(info.name)
                    .font(.title2.weight(.semibold))
                Text("Apple security research")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            LabeledContent("Version", value: info.version)
            LabeledContent("Build", value: info.build)
                // Five quick taps on the build number open the development data.
                .contentShape(Rectangle())
                .onTapGesture(count: 5) {
                    router.infoPath.append(AppRoute.sampleData)
                }
                .accessibilityAction(named: "Development data") {
                    router.infoPath.append(AppRoute.sampleData)
                }
        }
    }
}

#Preview {
    InfoView()
        .environment(AppRouter())
}
