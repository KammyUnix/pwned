import SwiftUI

/// Data sources, the optional NVD API key and cache management.
///
/// Clearing cached data removes downloaded NVD records only. Notes, bookmarks
/// and search history live in a separate store and are never touched here.
struct DataSettingsView: View {
    @Environment(IntelligenceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyError: String?
    @State private var confirmsClear = false

    private static let keyRequestURL = URL(string: "https://nvd.nist.gov/developers/request-an-api-key")

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                apiKeySection
                cacheSection
            }
            .navigationTitle("Data & Cache")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                hasStoredKey = NVDAPIKeyStore.hasKey
                await store.updateCacheStatistics()
            }
            .confirmationDialog("Clear cached data?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear Cached Data", role: .destructive) {
                    Task { await store.clearCachedData() }
                }
            } message: {
                Text("Downloaded vulnerability records are removed from this device. Your notes, bookmarks and search history are kept.")
            }
        }
    }

    // MARK: Sections

    private var sourceSection: some View {
        Section {
            LabeledContent("Source", value: "NVD CVE API 2.0")
            LabeledContent("Rate Limit", value: hasStoredKey ? "50 requests / 30 s" : "5 requests / 30 s")
        } header: {
            Text("Vulnerability Data")
        } footer: {
            Text(store.vulnerabilityState.summary)
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

    private var cacheSection: some View {
        Section {
            LabeledContent("Cached Records", value: store.cacheRecordCount.formatted())
            LabeledContent("Size on Disk") {
                Text(store.cacheSizeBytes, format: .byteCount(style: .file))
            }
            Button("Clear Cached Data", role: .destructive) {
                confirmsClear = true
            }
        } header: {
            Text("Cache")
        } footer: {
            Text("Clearing removes vulnerability records downloaded from NVD. Notes, bookmarks and search history are not affected.")
        }
    }

    // MARK: Actions

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
