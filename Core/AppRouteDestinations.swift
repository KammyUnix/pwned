import SwiftUI

extension View {
    /// Registers every `AppRoute` destination on the enclosing navigation stack.
    /// Each tab's root view applies this once.
    func appRouteDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .vulnerability(let id):
                VulnerabilityDetailView(cveID: id)
            case .researchLibrary:
                ResearchLibraryView()
            case .researchTopic(let id):
                ResearchTopicView(topicID: id)
            case .repository(let reference):
                RepositoryPreviewView(reference: reference)
            case .note(let id):
                NoteEditorView(noteID: id)
            case .candidates:
                CandidatesView()
            case .openRepository:
                OpenRepositoryView()
            case .laboratory:
                LaboratoryView()
            case .settings:
                SettingsView()
            case .sampleData:
                SampleDataView()
            }
        }
    }
}

extension ViewedItem {
    /// The destination for reopening this item, if it can still be resolved.
    var route: AppRoute? {
        switch kind {
        case .vulnerability:
            return .vulnerability(itemID)
        case .researchTopic:
            return .researchTopic(itemID)
        case .repository:
            let parts = itemID.split(separator: "/").map(String.init)
            guard parts.count == 2 else { return nil }
            return .repository(GitHubRepositoryReference(owner: parts[0], name: parts[1]))
        case .note:
            guard let uuid = UUID(uuidString: itemID) else { return nil }
            return .note(uuid)
        }
    }

    var systemImage: String {
        switch kind {
        case .vulnerability: "exclamationmark.shield"
        case .repository: "shippingbox"
        case .researchTopic: "books.vertical"
        case .note: "note.text"
        }
    }
}
