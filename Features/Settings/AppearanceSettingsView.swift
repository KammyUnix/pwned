import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppIconModel.self) private var appIcon

    @AppStorage(AppSettings.appearanceKey) private var appearance = AppSettings.Default.appearance
    @AppStorage(AppSettings.accentKey) private var accent = AppSettings.Default.accent
    @AppStorage(AppSettings.surfaceKey) private var surface = AppSettings.Default.surface
    @AppStorage(AppSettings.densityKey) private var density = AppSettings.Default.density

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows the Light or Dark setting of your device.")
            }

            Section {
                AccentSwatches(selection: $accent)
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Used for buttons, links, the selected tab and switches. Currently \(accent.title).")
            }

            Section {
                Picker("Background", selection: $surface) {
                    ForEach(SurfaceStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Row Density", selection: $density) {
                    ForEach(RowDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
            } header: {
                Text("Surfaces")
            } footer: {
                Text("Grouped uses the gray backdrop of the system Settings app. Plain uses the regular background. Compact fits more rows on screen.")
            }

            iconSection
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var iconSection: some View {
        Section {
            if appIcon.isSupported {
                HStack(spacing: 18) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button {
                            Task { await appIcon.select(choice) }
                        } label: {
                            VStack(spacing: 8) {
                                AppIconView(choice: choice, size: 64)
                                    .overlay {
                                        if appIcon.current == choice {
                                            RoundedRectangle(cornerRadius: 64 * 0.2237, style: .continuous)
                                                .strokeBorder(.tint, lineWidth: 3)
                                                .padding(-5)
                                        }
                                    }
                                Text(choice.title)
                                    .font(.footnote)
                                    .foregroundStyle(appIcon.current == choice ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(choice.title) icon")
                        .accessibilityAddTraits(appIcon.current == choice ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Text("This device doesn't support alternate app icons.")
                    .foregroundStyle(.secondary)
            }

            if let message = appIcon.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("App Icon")
        } footer: {
            Text("All three use the same mark. iOS asks you to confirm when the icon changes.")
        }
    }
}

/// A row of color swatches. The chosen one carries a check and is announced as selected.
private struct AccentSwatches: View {
    @Binding var selection: AccentChoice

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 12) {
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    ZStack {
                        Circle().fill(choice.color)
                        if selection == choice {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(selection == choice ? 0.4 : 0), lineWidth: 2)
                            .padding(-4)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selection == choice ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environment(AppIconModel())
}
