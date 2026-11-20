import SwiftUI

struct ResearchSettingsView: View {
    @AppStorage(AppSettings.defaultSortKey) private var defaultSort = AppSettings.Default.defaultSort
    @AppStorage(AppSettings.defaultSeverityKey) private var defaultSeverity = AppSettings.Default.defaultSeverity
    @AppStorage(AppSettings.defaultExploitedKey) private var defaultExploited = AppSettings.Default.defaultExploited
    @AppStorage(AppSettings.defaultPlatformsKey) private var platformsRaw = AppSettings.Default.defaultPlatforms

    @AppStorage(AppSettings.rowSummaryLinesKey) private var summaryLines = AppSettings.Default.rowSummaryLines
    @AppStorage(AppSettings.rowShowPlatformsKey) private var showsPlatforms = AppSettings.Default.rowShowPlatforms
    @AppStorage(AppSettings.rowShowDateKey) private var showsDate = AppSettings.Default.rowShowDate
    @AppStorage(AppSettings.dateStyleKey) private var dateStyle = AppSettings.Default.dateStyle

    @AppStorage(AppSettings.repoWrapLinesKey) private var wrapsLines = AppSettings.Default.repoWrapLines
    @AppStorage(AppSettings.repoCodeSizeKey) private var codeSize = AppSettings.Default.repoCodeSize
    @AppStorage(AppSettings.repoShowAnalysisKey) private var showsAnalysis = AppSettings.Default.repoShowAnalysis

    private var platformSummary: String {
        let platforms = FilterPreferences.platforms(from: platformsRaw)
        guard !platforms.isEmpty else { return "All" }
        return ApplePlatform.allCases.filter(platforms.contains).map(\.title).joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section {
                Picker("Sort By", selection: $defaultSort) {
                    ForEach(VulnerabilitySort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                Picker("Minimum Severity", selection: $defaultSeverity) {
                    ForEach(SeverityThreshold.allCases) { threshold in
                        Text(threshold.title).tag(threshold)
                    }
                }
                Toggle("Known Exploited Only", isOn: $defaultExploited)
                NavigationLink {
                    PlatformDefaultsView()
                } label: {
                    LabeledContent("Platforms", value: platformSummary)
                }
            } header: {
                Text("Discover Starts With")
            } footer: {
                Text("Discover opens with these filters, and Reset Filters returns to them. Whether uncertain Apple matches are listed is a switch in Discover's own filter menu.")
            }

            Section {
                Picker("Summary", selection: $summaryLines) {
                    Text("Hidden").tag(0)
                    Text("1 Line").tag(1)
                    Text("2 Lines").tag(2)
                    Text("3 Lines").tag(3)
                    Text("4 Lines").tag(4)
                }
                Toggle("Show Platforms", isOn: $showsPlatforms)
                Toggle("Show Date", isOn: $showsDate)
                Picker("Date Style", selection: $dateStyle) {
                    ForEach(DateStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .disabled(!showsDate)
            } header: {
                Text("Vulnerability Rows")
            } footer: {
                Text("How each vulnerability looks in Discover, Saved and search results. Known Exploited and Rejected labels always show.")
            }

            Section {
                Toggle("Wrap Long Lines", isOn: $wrapsLines)
                Picker("Code Text Size", selection: $codeSize) {
                    ForEach(CodeSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                Toggle("Show Build Analysis", isOn: $showsAnalysis)
            } header: {
                Text("Repositories")
            } footer: {
                Text("Wrap Long Lines and Code Text Size apply to files opened from a repository. Build Analysis lists build systems and dependency managers found from file names.")
            }
        }
        .navigationTitle("Research & Content")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Which Apple platforms Discover starts with. None checked means all of them.
struct PlatformDefaultsView: View {
    @AppStorage(AppSettings.defaultPlatformsKey) private var raw = AppSettings.Default.defaultPlatforms

    var body: some View {
        let selected = FilterPreferences.platforms(from: raw)

        Form {
            Section {
                ForEach(ApplePlatform.allCases) { platform in
                    Button {
                        var updated = selected
                        if updated.contains(platform) {
                            updated.remove(platform)
                        } else {
                            updated.insert(platform)
                        }
                        raw = FilterPreferences.text(from: updated)
                    } label: {
                        HStack {
                            Label(platform.title, systemImage: platform.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(platform) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(selected.contains(platform) ? .isSelected : [])
                }
            } footer: {
                Text("Leave every platform unchecked to start with all of them.")
            }
        }
        .navigationTitle("Platforms")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ResearchSettingsView()
    }
}
