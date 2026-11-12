import SwiftUI

/// A small label stating how trustworthy a piece of information is.
struct ProvenanceLabel: View {
    let provenance: InformationProvenance

    var body: some View {
        Label(provenance.title, systemImage: provenance.systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Source type: \(provenance.title)")
    }
}

/// Banner for the development data screen. Sample data appears nowhere else in
/// the app, so this is the only place that needs to say what it is.
struct SampleDataNotice: View {
    var message = "These records are built-in development samples, not real intelligence. They are not stored in the database or the cache and are never used when a request fails."

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(SampleData.label)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: InformationProvenance.sample.systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        Section { SampleDataNotice() }
        Section { ProvenanceLabel(provenance: .officialAdvisory) }
    }
}
