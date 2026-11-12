import SwiftUI
import SwiftData

/// A GitHub repository, read from the GitHub API when the page opens.
///
/// The page shows what GitHub reports (metadata, README, files) and what Pwned
/// can tell from the file names (build systems, dependency managers, CI). It
/// never builds or runs anything from the repository, and stores nothing from
/// it on the device apart from the user's own bookmark and notes.
struct RepositoryPreviewView: View {
    let reference: GitHubRepositoryReference

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query private var bookmarks: [RepositoryBookmark]
    @State private var model: RepositoryModel

    init(reference: GitHubRepositoryReference) {
        self.reference = reference
        _model = State(initialValue: RepositoryModel(reference: reference))
    }

    private var isBookmarked: Bool {
        bookmarks.contains { $0.fullName.caseInsensitiveCompare(reference.fullName) == .orderedSame }
    }

    var body: some View {
        List {
            identitySection

            switch model.details {
            case .idle, .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Fetching from GitHub…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            case .failed(let error):
                failureSection(error)
            case .loaded(let details):
                metadataSection(details)
                sourceSection
                analysisSections
            }

            BacklinksSection(kinds: [.repository], entityID: reference.fullName.lowercased())

            Section {
                Button(action: startNote) {
                    Label("New Note About This Repository", systemImage: "square.and.pencil")
                }
            }
        }
        .navigationTitle(reference.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleBookmark) {
                    Label(isBookmarked ? "Remove Bookmark" : "Bookmark",
                          systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .task(id: reference) {
            modelContext.recordView(.repository, id: reference.fullName, title: reference.fullName)
            await model.load()
        }
        .refreshable {
            await model.reload()
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section {
            LabeledContent("Owner", value: reference.owner)
            LabeledContent("Repository", value: reference.name)
            Link(destination: reference.webURL) {
                Label("Open on GitHub", systemImage: "safari")
            }
        }
    }

    private func failureSection(_ error: GitHubError) -> some View {
        Section {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            if error.isRetryable {
                Button("Try Again") {
                    Task { await model.reload() }
                }
            }
        }
    }

    private func metadataSection(_ details: GitHubRepositoryDetails) -> some View {
        Section {
            if let description = details.description, !description.isEmpty {
                Text(description)
            }
            if details.isArchived || details.isFork {
                LabeledContent("Status", value: statusText(for: details))
            }
            if let language = details.language {
                LabeledContent("Language", value: language)
            }
            LabeledContent("Stars", value: details.stars.formatted())
            LabeledContent("Forks", value: details.forks.formatted())
            LabeledContent("Open Issues", value: details.openIssues.formatted())
            LabeledContent("Default Branch", value: details.defaultBranch)
            if let license = details.license {
                LabeledContent("License", value: license)
            }
            if let pushedAt = details.pushedAt {
                LabeledContent("Last Push", value: pushedAt.formatted(date: .abbreviated, time: .omitted))
            }
            if let createdAt = details.createdAt {
                LabeledContent("Created", value: createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            LabeledContent(
                "Size",
                value: ByteCountFormatter.string(fromByteCount: Int64(details.sizeKilobytes) * 1024, countStyle: .file)
            )
            if !details.topics.isEmpty {
                LabeledContent("Topics", value: details.topics.joined(separator: ", "))
            }
            if let homepage = details.homepage {
                Link(destination: homepage) {
                    Label(homepage.host ?? homepage.absoluteString, systemImage: "link")
                }
            }
        } header: {
            Text("About")
        } footer: {
            if let fetchedAt = model.fetchedAt {
                Text("From the GitHub API at \(fetchedAt.formatted(date: .omitted, time: .shortened)). Pwned doesn't keep this on your device.")
            }
        }
    }

    private func statusText(for details: GitHubRepositoryDetails) -> String {
        [details.isArchived ? "Archived" : nil, details.isFork ? "Fork" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section {
            if let readme = model.readmeText, !readme.isEmpty {
                NavigationLink {
                    RepositoryReadmeView(reference: reference, text: readme)
                } label: {
                    Label("README", systemImage: "doc.richtext")
                }
            }

            switch model.tree {
            case .idle, .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading files…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                if error.isRetryable {
                    Button("Try Again") {
                        Task { await model.reload() }
                    }
                }
            case .loaded(let tree):
                NavigationLink {
                    RepositoryFilesView(reference: reference, tree: tree, directory: "")
                } label: {
                    LabeledContent {
                        Text(tree.entries.filter { $0.kind == .file }.count.formatted())
                    } label: {
                        Label("Browse Files", systemImage: "folder")
                    }
                }
            }
        } header: {
            Text("Source")
        } footer: {
            if case .loaded(let tree) = model.tree, tree.isTruncated {
                Text("This repository is very large, so GitHub returned only part of its file list.")
            }
        }
    }

    @ViewBuilder
    private var analysisSections: some View {
        if let analysis = model.analysis {
            ForEach(RepositoryAnalysis.Category.allCases, id: \.self) { category in
                let findings = analysis.findings(in: category)
                if !findings.isEmpty {
                    Section(category.title) {
                        ForEach(findings) { finding in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(finding.title)
                                Text(finding.evidence.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            if !analysis.languages.isEmpty {
                Section("Languages") {
                    ForEach(analysis.languages) { share in
                        LabeledContent(share.name, value: "\(share.fileCount.formatted()) files")
                    }
                }
            }

            Section {
                Label(analysisNote(analysis), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func analysisNote(_ analysis: RepositoryAnalysis) -> String {
        var text = "Found from file names only (\(analysis.fileCount.formatted()) files). Nothing was built or run, so a build system listed here is not proof the project builds. Languages are counted by file, not by lines of code."
        if analysis.isIncomplete {
            text += " The file list was cut short, so this may be incomplete."
        }
        return text
    }

    // MARK: Actions

    private func toggleBookmark() {
        let existing = bookmarks.filter {
            $0.fullName.caseInsensitiveCompare(reference.fullName) == .orderedSame
        }
        if existing.isEmpty {
            modelContext.insert(RepositoryBookmark(owner: reference.owner, name: reference.name))
        } else {
            for bookmark in existing { modelContext.delete(bookmark) }
        }
        modelContext.saveLoggingFailure()
    }

    private func startNote() {
        let note = ResearchNote(title: reference.fullName)
        modelContext.insert(note)
        modelContext.link(
            noteID: note.id,
            kind: .repository,
            entityID: reference.fullName.lowercased(),
            displayName: reference.fullName,
            origin: .manual
        )
        modelContext.saveLoggingFailure()
        router.push(.note(note.id))
    }
}
