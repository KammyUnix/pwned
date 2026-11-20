import SwiftUI

/// The app's identity, software updates, links, legal notes and the way into Settings.
struct InfoView: View {
    @Environment(AppRouter.self) private var router
    @Environment(UpdateModel.self) private var updates
    @Environment(AppIconModel.self) private var appIcon

    @AppStorage(AppSettings.checkUpdatesKey) private var checksOnOpen = AppSettings.Default.checkUpdates

    private let info = AppInfo()

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.infoPath) {
            List {
                heroSection
                updateSection

                Section {
                    NavigationLink(value: AppRoute.settings) {
                        Label {
                            Text("Settings")
                        } icon: {
                            SettingsTile(systemImage: "gearshape.fill", color: .gray)
                        }
                    }
                }

                aboutSection
                legalSection
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .appRouteDestinations()
            .task {
                await updates.checkAutomatically(enabled: checksOnOpen)
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        Section {
            VStack(spacing: 16) {
                AppIconView(choice: appIcon.current, size: 112)

                VStack(spacing: 6) {
                    Text(info.name)
                        .font(.largeTitle.weight(.bold))
                    Text(AppInfo.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        pill(title: "Version", value: info.version)
                        pill(title: "Build", value: info.build)
                            // Five quick taps on the build number open the development data.
                            .contentShape(Capsule())
                            .onTapGesture(count: 5) {
                                router.infoPath.append(AppRoute.sampleData)
                            }
                            .accessibilityAction(named: "Development data") {
                                router.infoPath.append(AppRoute.sampleData)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func pill(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    // MARK: Updates

    private var updateSection: some View {
        let status = updates.status
        return Section {
            statusRow(for: status)

            LabeledContent("Installed", value: "\(info.version) (\(info.build))")

            if let release = status.release {
                LabeledContent("Latest Release", value: release.versionLabel)
                if let published = release.publishedAt {
                    LabeledContent("Published", value: published.formatted(date: .long, time: .omitted))
                }
                if let notes = Self.notesText(release.notes) {
                    DisclosureGroup("Release Notes") {
                        Text(notes)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Button {
                Task { await updates.check() }
            } label: {
                Label(status == .checking ? "Checking\u{2026}" : "Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(status == .checking)

            if let release = status.release {
                Link(destination: release.pageURL) {
                    Label("View Release on GitHub", systemImage: "safari")
                }
            } else if status == .noRelease {
                Link(destination: AppInfo.releasesURL) {
                    Label("Open Releases on GitHub", systemImage: "safari")
                }
            }
        } header: {
            Text("Software Update")
        } footer: {
            if let checked = updates.lastChecked {
                Text("Last checked at \(checked.formatted(date: .omitted, time: .shortened)). Updates come from the releases of the project's GitHub repository.")
            } else {
                Text("Updates come from the releases of the project's GitHub repository.")
            }
        }
    }

    @ViewBuilder
    private func statusRow(for status: UpdateStatus) -> some View {
        switch status {
        case .idle:
            statusLabel("Not checked yet", detail: "Check to see whether a newer release exists.", systemImage: "questionmark.circle", color: .secondary)
        case .checking:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking for updates\u{2026}")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .upToDate(let release):
            statusLabel("Pwned is up to date", detail: "Version \(release.versionLabel) is the latest release.", systemImage: "checkmark.circle.fill", color: .green)
        case .updateAvailable(let release):
            statusLabel("Update available", detail: "Version \(release.versionLabel) is out. You have \(info.version).", systemImage: "arrow.down.circle.fill", color: .accentColor)
        case .ahead(let release):
            statusLabel("Newer than the latest release", detail: "You have \(info.version) and the latest release is \(release.versionLabel). That's normal for a development build.", systemImage: "hammer.circle.fill", color: .orange)
        case .noRelease:
            statusLabel("No release yet", detail: "No release has been published on GitHub, so there is nothing to compare with.", systemImage: "shippingbox", color: .secondary)
        case .networkError(let message):
            statusLabel("Couldn't reach GitHub", detail: message, systemImage: "wifi.exclamationmark", color: .orange)
        case .apiError(let message):
            statusLabel("GitHub sent a problem", detail: message, systemImage: "exclamationmark.triangle.fill", color: .orange)
        }
    }

    private func statusLabel(_ title: String, detail: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Release notes as inline Markdown, or nil when the release has none.
    static func notesText(_ notes: String) -> AttributedString? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: trimmed, options: options)) ?? AttributedString(trimmed)
    }

    // MARK: About and legal

    private var aboutSection: some View {
        Section {
            LabeledContent("Developer", value: AppInfo.developerName)
            Link(destination: AppInfo.developerURL) {
                Label("Developer on GitHub", systemImage: "person.crop.circle")
            }
            Link(destination: AppInfo.repositoryURL) {
                Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: AppInfo.issuesURL) {
                Label("Report an Issue", systemImage: "ladybug")
            }
        } header: {
            Text("About")
        }
    }

    private var legalSection: some View {
        Section {
            NavigationLink {
                InfoDocumentView(document: .license)
            } label: {
                Label("License", systemImage: "doc.text")
            }
            NavigationLink {
                InfoDocumentView(document: .privacy)
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
            NavigationLink {
                InfoDocumentView(document: .legal)
            } label: {
                Label("Legal Notices", systemImage: "scroll")
            }
        } header: {
            Text("License & Legal")
        } footer: {
            Text(InfoDocument.nvdNotice)
        }
    }
}

#Preview {
    InfoView()
        .environment(AppRouter())
        .environment(UpdateModel())
        .environment(AppIconModel())
}
