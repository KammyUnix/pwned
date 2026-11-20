import SwiftUI
import SwiftData

// MARK: - Vulnerability data

/// Where the data comes from, when it refreshes, and the optional NVD API key.
struct DataSourcesSettingsView: View {
    @Environment(IntelligenceStore.self) private var store

    @AppStorage(AppSettings.autoRefreshKey) private var autoRefresh = AppSettings.Default.autoRefresh
    @AppStorage(AppSettings.refreshHoursKey) private var refreshHours = AppSettings.Default.refreshHours

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyError: String?

    private static let keyRequestURL = URL(string: "https://nvd.nist.gov/developers/request-an-api-key")

    var body: some View {
        Form {
            sourceSection
            refreshSection
            appleSection
            apiKeySection
        }
        .navigationTitle("Vulnerability Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hasStoredKey = NVDAPIKeyStore.hasKey
        }
    }

    private var sourceSection: some View {
        Section {
            LabeledContent("Source", value: "NVD CVE API 2.0")
            LabeledContent("Rate Limit", value: hasStoredKey ? "50 requests / 30 s" : "5 requests / 30 s")
        } header: {
            Text("Source")
        } footer: {
            Text(store.vulnerabilityState.summary)
        }
    }

    private var refreshSection: some View {
        Section {
            Toggle("Refresh Automatically", isOn: $autoRefresh)
            Picker("Refresh When Older Than", selection: $refreshHours) {
                ForEach(AppSettings.refreshHourChoices, id: \.self) { hours in
                    Text(hours == 1 ? "1 Hour" : "\(hours) Hours").tag(hours)
                }
            }
            .disabled(!autoRefresh)
        } header: {
            Text("Refresh")
        } footer: {
            Text("Pwned refreshes when it opens or reconnects, if the saved data is older than this. NVD asks clients not to poll often. With automatic refresh off, pull down on Discover to refresh.")
        }
    }

    private var appleSection: some View {
        let otherCount = max(store.vulnerabilities.count - store.appleFeed.count - store.candidates.count, 0)
        return Section {
            LabeledContent("Apple Records", value: store.appleFeed.count.formatted())
            LabeledContent("Needs Review", value: store.candidates.count.formatted())
            LabeledContent("Other Saved Records", value: otherCount.formatted())
        } header: {
            Text("Apple Research Feed")
        } footer: {
            Text("Discover lists records NVD or Apple's security team tie to an Apple product. Records with weaker evidence are kept for review, and everything else stays saved but out of the feed. Include uncertain matches from the filter menu in Discover.")
        }
    }

    private var apiKeySection: some View {
        Section {
            if hasStoredKey {
                LabeledContent("API Key", value: "Saved in Keychain")
                Button("Remove API Key", role: .destructive, action: removeKey)
            } else {
                SecureField("Paste NVD API key", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save API Key", action: saveKey)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let keyError {
                Label(keyError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("NVD API Key (Optional)")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pwned works without a key. NVD allows 5 requests per 30 seconds without one and 50 with a free key. The key is stored in this device's Keychain and is only sent to NVD.")
                if let url = Self.keyRequestURL {
                    Link("Request a free key from NVD", destination: url)
                }
            }
        }
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try NVDAPIKeyStore.save(key)
            apiKeyInput = ""
            hasStoredKey = true
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try NVDAPIKeyStore.remove()
            hasStoredKey = false
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }
}

// MARK: - Data and privacy

struct DataPrivacySettingsView: View {
    private enum PendingAction: Identifiable {
        case clearCache
        case clearViewed
        case clearSearches
        case eraseAll

        var id: Self { self }

        var title: String {
            switch self {
            case .clearCache: "Clear cached data?"
            case .clearViewed: "Clear recently viewed?"
            case .clearSearches: "Clear search history?"
            case .eraseAll: "Erase all your data?"
            }
        }

        var confirmTitle: String {
            switch self {
            case .clearCache: "Clear Cached Data"
            case .clearViewed: "Clear Recently Viewed"
            case .clearSearches: "Clear Search History"
            case .eraseAll: "Erase Everything"
            }
        }

        var message: String {
            switch self {
            case .clearCache:
                "Downloaded vulnerability records are removed from this device. Your notes, links, bookmarks and search history are kept. Nothing is shown in their place until you refresh."
            case .clearViewed:
                "The list of items you recently opened is emptied. Notes, bookmarks and cached data are kept."
            case .clearSearches:
                "The searches Pwned remembers are deleted. Notes, bookmarks and cached data are kept."
            case .eraseAll:
                "This deletes every note, every link between notes and research items, all bookmarks, recently viewed items and search history. It can't be undone. Cached vulnerability data and your settings are kept."
            }
        }
    }

    @Environment(IntelligenceStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]

    @AppStorage(AppSettings.cellularKey) private var allowsCellular = AppSettings.Default.cellular
    @AppStorage(AppSettings.checkUpdatesKey) private var checksUpdates = AppSettings.Default.checkUpdates
    @AppStorage(AppSettings.keepRecentKey) private var keepsRecent = AppSettings.Default.keepRecent
    @AppStorage(AppSettings.recentLimitKey) private var recentLimit = AppSettings.Default.recentLimit
    @AppStorage(AppSettings.keepSearchesKey) private var keepsSearches = AppSettings.Default.keepSearches
    @AppStorage(AppSettings.confirmNoteDeletionKey) private var confirmsNoteDeletion = AppSettings.Default.confirmNoteDeletion

    @State private var pending: PendingAction?

    var body: some View {
        Form {
            networkSection
            historySection
            notesSection
            cacheSection
            eraseSection
        }
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.updateCacheStatistics()
        }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending
        ) { action in
            Button(action.confirmTitle, role: .destructive) {
                perform(action)
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var networkSection: some View {
        Section {
            Toggle("Use Cellular Data", isOn: $allowsCellular)
            Toggle("Check for Updates When Info Opens", isOn: $checksUpdates)
        } header: {
            Text("Network")
        } footer: {
            Text("Pwned only talks to NVD (vulnerability data) and GitHub (repositories and update checks). It has no analytics and no account. Turn off cellular data to download only on Wi-Fi. The update check runs at most once per launch, and you can always check by hand from the Info tab.")
        }
    }

    private var historySection: some View {
        Section {
            Toggle("Keep Recently Viewed", isOn: $keepsRecent)
            Picker("Items to Keep", selection: $recentLimit) {
                ForEach(AppSettings.recentLimitChoices, id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
            .disabled(!keepsRecent)
            Toggle("Keep Search History", isOn: $keepsSearches)
            Button("Clear Recently Viewed", role: .destructive) {
                pending = .clearViewed
            }
            Button("Clear Search History", role: .destructive) {
                pending = .clearSearches
            }
        } header: {
            Text("History")
        } footer: {
            Text("Recently viewed items appear under Saved. Remembered searches are offered as suggestions in Discover. Both stay on this device.")
        }
    }

    private var notesSection: some View {
        Section {
            Toggle("Confirm Before Deleting Notes", isOn: $confirmsNoteDeletion)
            ShareLink(
                item: NotesExport.markdown(for: notes),
                subject: Text("Pwned notes")
            ) {
                Label("Export All Notes", systemImage: "square.and.arrow.up")
            }
            .disabled(notes.isEmpty)
        } header: {
            Text("Notes")
        } footer: {
            Text(notes.isEmpty
                 ? "You have no notes to export."
                 : "Exports \(notes.count.formatted()) \(notes.count == 1 ? "note" : "notes") as one Markdown text.")
        }
    }

    private var cacheSection: some View {
        Section {
            LabeledContent("Cached Records", value: store.cacheRecordCount.formatted())
            LabeledContent("Size on Disk") {
                Text(store.cacheSizeBytes, format: .byteCount(style: .file))
            }
            Button("Clear Cached Data", role: .destructive) {
                pending = .clearCache
            }
        } header: {
            Text("Cache")
        } footer: {
            Text("Clearing removes vulnerability records downloaded from NVD. Notes, links, bookmarks and search history are not affected.")
        }
    }

    private var eraseSection: some View {
        Section {
            Button("Erase All My Data", role: .destructive) {
                pending = .eraseAll
            }
        } header: {
            Text("Your Data")
        } footer: {
            Text("Removes everything you created in Pwned. Use this before handing the device to someone else.")
        }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .clearCache:
            Task { await store.clearCachedData() }
        case .clearViewed:
            modelContext.clearRecentlyViewed()
        case .clearSearches:
            modelContext.clearSearchHistory()
        case .eraseAll:
            modelContext.eraseAllUserData()
        }
        Haptics.play(.warning)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage(AppSettings.openLinksInAppKey) private var opensLinksInApp = AppSettings.Default.openLinksInApp

    @State private var confirmsReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Open Web Links in Pwned", isOn: $opensLinksInApp)
            } header: {
                Text("Links")
            } footer: {
                Text("Opens web pages in a browser sheet over the app instead of switching to Safari. This covers links in notes, vulnerability references and repository pages.")
            }

            Section {
                Button("Reset All Settings", role: .destructive) {
                    confirmsReset = true
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Puts every setting back to its default. Your notes, bookmarks, history, cached data and NVD API key are not changed.")
            }
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset all settings?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset All Settings", role: .destructive) {
                AppSettings.reset()
                Haptics.play(.success)
            }
        } message: {
            Text("Every setting returns to its default.")
        }
    }
}

#Preview {
    NavigationStack {
        DataPrivacySettingsView()
    }
    .environment(IntelligenceStore())
    .modelContainer(PersistenceController.makeInMemoryContainer())
}
