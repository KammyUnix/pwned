import SwiftUI
import SwiftData

/// Research dashboard. Every section is backed by the local data layer: sample
/// intelligence from `IntelligenceStore` (clearly labeled) and real user data
/// from SwiftData.
struct DiscoverView: View {
    @Environment(IntelligenceStore.self) private var store
    @Environment(AppRouter.self) private var router

    @Query(sort: \ResearchNote.modifiedAt, order: .reverse) private var notes: [ResearchNote]
    @Query(sort: \VulnerabilityBookmark.createdAt, order: .reverse) private var vulnerabilityBookmarks: [VulnerabilityBookmark]
    @Query private var repositoryBookmarks: [RepositoryBookmark]
    @Query(sort: \ViewedItem.viewedAt, order: .reverse) private var viewedItems: [ViewedItem]

    @State private var showsSettings = false

    private let previewCount = 3

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.discoverPath) {
            List {
                if store.isShowingSampleData {
                    Section {
                        if store.isShowingSampleVulnerabilities {
                            SampleDataNotice()
                        } else {
                            SampleDataNotice(
                                message: "Apple advisories, announcements and repositories below are built-in samples, not real intelligence. Vulnerabilities come from NVD."
                            )
                        }
                    }
                }

                activitySection
                announcementsSection
                vulnerabilitiesSection
                advisoriesSection
                repositoriesSection
                notesSection
                bookmarksSection
                recentlyViewedSection
                librarySection
                statusSection
            }
            .navigationTitle("Discover")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Data & Cache", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                DataSettingsView()
            }
            .appRouteDestinations()
        }
    }

    // MARK: Research activity (real counts from local storage)

    private var activitySection: some View {
        Section("Research Activity") {
            LabeledContent("Notes", value: "\(notes.count)")
            LabeledContent("Bookmarked Vulnerabilities", value: "\(vulnerabilityBookmarks.count)")
            LabeledContent("Bookmarked Repositories", value: "\(repositoryBookmarks.count)")
            LabeledContent("Items Viewed", value: "\(viewedItems.count)")
        }
    }

    // MARK: Intelligence sections

    private var announcementsSection: some View {
        Section("Security Announcements") {
            ForEach(store.recentAnnouncements.prefix(previewCount)) { announcement in
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
    }

    private var vulnerabilitiesSection: some View {
        Section("Recently Published Vulnerabilities") {
            switch store.refreshPhase {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading from NVD…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if store.recentVulnerabilities.isEmpty {
                Text("No vulnerabilities loaded yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.recentVulnerabilities.prefix(previewCount)) { vulnerability in
                NavigationLink(value: AppRoute.vulnerability(vulnerability.id)) {
                    VulnerabilityRow(vulnerability: vulnerability)
                }
            }
            Button {
                router.selectedTab = .vulnerabilities
            } label: {
                Label("All Vulnerabilities", systemImage: "list.bullet")
            }
        }
    }

    private var advisoriesSection: some View {
        Section("Apple Security Advisories") {
            ForEach(store.recentAdvisories.prefix(previewCount)) { advisory in
                AdvisoryRow(advisory: advisory)
            }
        }
    }

    private var repositoriesSection: some View {
        Section("Recently Updated Repositories") {
            ForEach(store.recentRepositories.prefix(previewCount)) { repository in
                NavigationLink(value: AppRoute.repository(
                    GitHubRepositoryReference(owner: repository.owner, name: repository.name)
                )) {
                    RepositoryRow(repository: repository)
                }
            }
        }
    }

    // MARK: User data sections

    private var notesSection: some View {
        Section("Recently Modified Notes") {
            if notes.isEmpty {
                Text("No notes yet. Create one in the Notebook tab.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes.prefix(previewCount)) { note in
                    NavigationLink(value: AppRoute.note(note.id)) {
                        NoteRow(note: note)
                    }
                }
            }
        }
    }

    private var bookmarksSection: some View {
        Section("Bookmarked Vulnerabilities") {
            if vulnerabilityBookmarks.isEmpty {
                Text("No bookmarks yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vulnerabilityBookmarks.prefix(previewCount)) { bookmark in
                    NavigationLink(value: AppRoute.vulnerability(bookmark.cveID)) {
                        if let vulnerability = store.vulnerability(id: bookmark.cveID) {
                            VulnerabilityRow(vulnerability: vulnerability)
                        } else {
                            Label(bookmark.cveID, systemImage: "bookmark")
                        }
                    }
                }
            }
        }
    }

    private var recentlyViewedSection: some View {
        Section("Recently Viewed") {
            if viewedItems.isEmpty {
                Text("Items you open appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewedItems.prefix(5)) { item in
                    if let route = item.route {
                        NavigationLink(value: route) {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
            }
        }
    }

    private var librarySection: some View {
        Section("Apple Research Center") {
            NavigationLink(value: AppRoute.researchLibrary) {
                Label("Browse Apple Platforms and Security", systemImage: "books.vertical")
            }
        }
    }

    private var statusSection: some View {
        Section {
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vulnerabilities: \(store.vulnerabilityState.summary)")
                if store.isShowingSampleData {
                    Text("Apple advisories, announcements and repositories: sample data.")
                }
            }
        }
    }
}

struct AdvisoryRow: View {
    let advisory: AppleAdvisory

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 4) {
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

        if let url = advisory.url {
            Link(destination: url) { content }
                .foregroundStyle(.primary)
        } else {
            content
        }
    }
}
