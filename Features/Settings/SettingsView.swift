import SwiftUI

/// The settings hub, reached from the Info tab. Each row opens one page, in
/// the way the system Settings app is organised.
///
/// Every preference has exactly one home:
/// * showing uncertain Apple matches is a Discover filter, so it lives in
///   Discover's filter menu and is only described here;
/// * updates are checked from the Info tab, never from here.
///
/// Clearing cached data removes downloaded NVD records only. Notes, links,
/// bookmarks and search history live in a separate store and are never touched.
struct SettingsView: View {
    @Environment(AppIconModel.self) private var appIcon

    private let info = AppInfo()

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppIconView(choice: appIcon.current, size: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(.title3.weight(.semibold))
                        Text(info.versionLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                link("Appearance", systemImage: "paintpalette.fill", color: .pink) { AppearanceSettingsView() }
                link("Interface & Navigation", systemImage: "rectangle.3.group.fill", color: .indigo) { InterfaceSettingsView() }
                link("Accessibility", systemImage: "accessibility", color: .blue) { AccessibilitySettingsView() }
            }

            Section {
                link("Research & Content", systemImage: "books.vertical.fill", color: .orange) { ResearchSettingsView() }
                link("Vulnerability Data", systemImage: "arrow.down.circle.fill", color: .teal) { DataSourcesSettingsView() }
            }

            Section {
                link("Data & Privacy", systemImage: "hand.raised.fill", color: .green) { DataPrivacySettingsView() }
                link("General", systemImage: "gearshape.fill", color: .gray) { GeneralSettingsView() }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link<Destination: View>(
        _ title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                Text(title)
            } icon: {
                SettingsTile(systemImage: systemImage, color: color)
            }
        }
    }
}

/// The small colored square beside a settings row, as in the system Settings app.
struct SettingsTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(IntelligenceStore())
    .environment(AppIconModel())
    .modelContainer(PersistenceController.makeInMemoryContainer())
}
