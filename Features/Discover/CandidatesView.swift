import SwiftUI

/// Records with some Apple evidence that isn't enough to list them as Apple
/// vulnerabilities. They are kept, not discarded: classification is recomputed
/// whenever a record changes, so one can move into the feed when better
/// evidence (an NVD analysis, an Apple advisory) arrives.
struct CandidatesView: View {
    @Environment(IntelligenceStore.self) private var store

    var body: some View {
        List {
            Section {
                Text("Pwned lists a vulnerability as Apple research only when more than a keyword points to Apple. These records have weaker evidence, such as a description that mentions an Apple platform, so they stay out of Discover until you say otherwise.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if store.candidates.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing to Review",
                        systemImage: "checkmark.circle",
                        description: Text("No saved records are waiting on better evidence.")
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.candidates) { vulnerability in
                        NavigationLink(value: AppRoute.vulnerability(vulnerability.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                VulnerabilityRow(
                                    vulnerability: vulnerability,
                                    classification: store.classification(for: vulnerability.id)
                                )
                                if let reason = store.classification(for: vulnerability.id)?.signals.first?.title {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(store.candidates.countLabel(singular: "Record", plural: "Records"))
                }
            }
        }
        .navigationTitle("Needs Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
