import SwiftUI

/// The development data screen, reached through the Info tab's Easter egg.
///
/// This is the only place sample data is shown. The data is read straight from
/// `SampleData`, so it works offline and cannot mix with real records: it is
/// not in the vulnerability store, the on-disk cache, SwiftData or search.
struct SampleDataView: View {
    var body: some View {
        List {
            Section {
                SampleDataNotice()
            } header: {
                Text(SampleData.label)
            }

            Section("Vulnerabilities") {
                ForEach(SampleData.vulnerabilities) { vulnerability in
                    VulnerabilityRow(vulnerability: vulnerability)
                }
            }

            Section("Apple Security Advisories") {
                ForEach(SampleData.appleAdvisories) { advisory in
                    SampleAdvisoryRow(advisory: advisory)
                }
            }

            Section("Security Announcements") {
                ForEach(SampleData.announcements) { announcement in
                    SampleAnnouncementRow(announcement: announcement)
                }
            }

            Section("Repositories") {
                ForEach(SampleData.repositories) { repository in
                    SampleRepositoryRow(repository: repository)
                }
            }
        }
        .navigationTitle("Development Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SampleAdvisoryRow: View {
    let advisory: AppleAdvisory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(advisory.title)
                .font(.headline)
            HStack(spacing: 10) {
                Text(advisory.platforms.map(\.title).joined(separator: ", "))
                ProvenanceLabel(provenance: advisory.provenance)
                Text(advisory.updatedAt.shortDateLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct SampleAnnouncementRow: View {
    let announcement: SecurityAnnouncement

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(announcement.title)
                .font(.headline)
            Text(announcement.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProvenanceLabel(provenance: announcement.provenance)
                Text("\(announcement.source) · \(announcement.date.shortDateLabel)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct SampleRepositoryRow: View {
    let repository: RepositorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(repository.fullName)
                .font(.headline)
            Text(repository.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                if let language = repository.primaryLanguage {
                    Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
                }
                ProvenanceLabel(provenance: repository.provenance)
                Text(repository.updatedAt.shortDateLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
