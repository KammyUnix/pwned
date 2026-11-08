import SwiftUI
import SwiftData

struct RepositoriesView: View {
    @Environment(IntelligenceStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Query(sort: \RepositoryBookmark.createdAt, order: .reverse) private var bookmarks: [RepositoryBookmark]

    @State private var urlText = ""
    @State private var showsInvalidInput = false
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.repositoriesPath) {
            List {
                openSection

                Section("Bookmarks") {
                    if bookmarks.isEmpty {
                        Text("No bookmarked repositories.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bookmarks) { bookmark in
                            NavigationLink(value: AppRoute.repository(bookmark.reference)) {
                                Label(bookmark.fullName, systemImage: "bookmark")
                            }
                        }
                    }
                }

                Section {
                    ForEach(store.recentRepositories) { repository in
                        NavigationLink(value: AppRoute.repository(
                            GitHubRepositoryReference(owner: repository.owner, name: repository.name)
                        )) {
                            RepositoryRow(repository: repository)
                        }
                    }
                } header: {
                    Text(store.isShowingSampleData ? "Recently Updated (Sample)" : "Recently Updated")
                } footer: {
                    if store.isShowingSampleData {
                        Text("Sample entries are not real repositories.")
                    }
                }
            }
            .navigationTitle("Repositories")
            .appRouteDestinations()
        }
    }

    private var openSection: some View {
        Section {
            HStack {
                TextField("github.com/owner/repository", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($isURLFieldFocused)
                    .onSubmit(openRepository)
                    .onChange(of: urlText) { showsInvalidInput = false }

                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    urlText = pasted
                    openRepository()
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }

            Button("Inspect Repository", action: openRepository)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Open Repository")
        } footer: {
            if showsInvalidInput {
                Label("Enter a GitHub repository URL such as github.com/owner/repository.",
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            } else {
                Text("Repositories are inspected read-only. Pwned never runs downloaded code.")
            }
        }
    }

    private func openRepository() {
        guard let reference = SearchClassifier.parseGitHubRepository(urlText) else {
            showsInvalidInput = true
            return
        }
        isURLFieldFocused = false
        urlText = ""
        router.open(.repository(reference))
    }
}

struct RepositoryRow: View {
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
