import SwiftUI
import SwiftData

/// Enter a GitHub repository URL, or reopen a bookmarked repository.
struct OpenRepositoryView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \RepositoryBookmark.createdAt, order: .reverse) private var bookmarks: [RepositoryBookmark]

    @State private var urlText = ""
    @State private var showsInvalidInput = false
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        List {
            openSection

            if !bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(bookmarks) { bookmark in
                        NavigationLink(value: AppRoute.repository(bookmark.reference)) {
                            Label(bookmark.fullName, systemImage: "bookmark")
                        }
                    }
                }
            }
        }
        .navigationTitle("GitHub Repositories")
        .navigationBarTitleDisplayMode(.inline)
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
        router.push(.repository(reference))
    }
}
