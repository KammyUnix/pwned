import SwiftUI
import SwiftData

/// Phase 1 repository page: shows what is known from the URL alone and lets the
/// user bookmark it. Metadata, README, file tree and analysis arrive in Phase 3.
struct RepositoryPreviewView: View {
    let reference: GitHubRepositoryReference

    @Environment(IntelligenceStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var bookmarks: [RepositoryBookmark]

    private var isSample: Bool {
        store.repositories.first {
            $0.fullName.caseInsensitiveCompare(reference.fullName) == .orderedSame
        }?.isSample ?? false
    }

    private var isBookmarked: Bool {
        bookmarks.contains { $0.fullName.caseInsensitiveCompare(reference.fullName) == .orderedSame }
    }

    var body: some View {
        List {
            if isSample {
                Section { SampleDataNotice() }
            }

            Section {
                LabeledContent("Owner", value: reference.owner)
                LabeledContent("Repository", value: reference.name)
                if !isSample {
                    Link(destination: reference.webURL) {
                        Label("Open on GitHub", systemImage: "safari")
                    }
                }
            }

            Section {
                Label("Stars, README, file tree, commits and build analysis require the GitHub API integration planned for Phase 3. Nothing has been fetched for this repository.",
                      systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        }
    }

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
}
