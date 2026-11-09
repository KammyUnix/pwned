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

/// Inline notice shown above content that comes from built-in sample data.
struct SampleDataNotice: View {
    var message = "These records are built-in development samples, not real intelligence. Live sources are added in later phases."

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sample Data")
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
