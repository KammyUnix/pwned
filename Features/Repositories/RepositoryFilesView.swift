import SwiftUI

/// One folder of a repository's file tree. Folders open another instance of
/// this view; files open `RepositoryFileView`.
struct RepositoryFilesView: View {
    let reference: GitHubRepositoryReference
    let tree: GitHubTree
    /// Path of the folder shown, or "" for the top level.
    let directory: String

    var body: some View {
        let children = tree.children(of: directory)

        List {
            if tree.isTruncated {
                Section {
                    Label("GitHub returned only part of this very large repository's file list.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if children.isEmpty {
                Text("This folder is empty.")
                    .foregroundStyle(.secondary)
            }

            ForEach(children) { entry in
                row(for: entry)
            }
        }
        .navigationTitle(directory.isEmpty ? reference.name : (directory.split(separator: "/").last.map(String.init) ?? directory))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(for entry: GitHubTreeEntry) -> some View {
        switch entry.kind {
        case .directory:
            NavigationLink {
                RepositoryFilesView(reference: reference, tree: tree, directory: entry.path)
            } label: {
                Label(entry.name, systemImage: "folder")
            }
        case .file:
            NavigationLink {
                RepositoryFileView(reference: reference, entry: entry)
            } label: {
                LabeledContent {
                    if let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                } label: {
                    Label(entry.name, systemImage: "doc.text")
                }
            }
        case .submodule:
            LabeledContent {
                Text("Submodule")
            } label: {
                Label(entry.name, systemImage: "arrow.triangle.branch")
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// A file's text, fetched when it opens. Binary and oversized files say so
/// instead of showing anything.
struct RepositoryFileView: View {
    let reference: GitHubRepositoryReference
    let entry: GitHubTreeEntry

    @State private var state: Loadable<GitHubFile> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("Loading \(entry.name)…")
            case .failed(let error):
                ContentUnavailableView {
                    Label("Can't Open File", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    if error.isRetryable {
                        Button("Try Again") { Task { await load(force: true) } }
                    }
                }
            case .loaded(let file):
                content(for: file)
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = githubURL {
                ToolbarItem(placement: .primaryAction) {
                    Link(destination: url) {
                        Label("Open on GitHub", systemImage: "safari")
                    }
                }
            }
        }
        .task(id: entry.path) { await load(force: false) }
    }

    @ViewBuilder
    private func content(for file: GitHubFile) -> some View {
        if let text = file.text {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if file.byteCount > GitHubClient.maxDisplayBytes {
                        Label("Showing the first \(ByteCountFormatter.string(fromByteCount: Int64(GitHubClient.maxDisplayBytes), countStyle: .file)) of this file.",
                              systemImage: "scissors")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(text.isEmpty ? "This file is empty." : text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Not a Text File",
                systemImage: "doc.questionmark",
                description: Text("This file (\(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file))) isn't readable text, so it isn't shown here.")
            )
        }
    }

    private var githubURL: URL? {
        let encoded = entry.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.path
        return URL(string: "https://github.com/\(reference.owner)/\(reference.name)/blob/HEAD/\(encoded)")
    }

    private func load(force: Bool) async {
        if !force, case .loaded = state { return }
        state = .loading
        do {
            let file = try await GitHubClient.shared.file(reference, path: entry.path, size: entry.size)
            state = .loaded(file)
        } catch is CancellationError {
            state = .idle
        } catch {
            let mapped = GitHubError.map(error)
            state = mapped == .cancelled ? .idle : .failed(mapped)
        }
    }
}

/// A README, shown with inline Markdown (emphasis, code, links) applied.
/// Headings and lists keep their Markdown marks: this is a reader for
/// inspection, not a full Markdown renderer.
struct RepositoryReadmeView: View {
    let reference: GitHubRepositoryReference
    let text: String

    var body: some View {
        ScrollView {
            Text(rendered)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("README")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
