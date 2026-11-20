import SwiftUI

/// A short document shown from the Info page: the license, privacy and legal notes.
///
/// The text states what Pwned actually does. If the app's behavior changes,
/// change the matching paragraph here in the same commit.
struct InfoDocument: Equatable, Sendable {
    struct Paragraph: Equatable, Sendable, Identifiable {
        let heading: String
        let body: String
        var id: String { heading }
    }

    let title: String
    let paragraphs: [Paragraph]
}

extension InfoDocument {
    /// The NVD requires this sentence wherever its API is used.
    static let nvdNotice = "This product uses the NVD API but is not endorsed or certified by the NVD."

    static let license = InfoDocument(
        title: "License",
        paragraphs: [
            Paragraph(
                heading: "Pwned",
                body: "No license file has been published in the Pwned repository. Without one, the source code stays under its author's default copyright. GitHub's Terms of Service let you view and fork a public repository on GitHub. Anything beyond that needs the developer's permission."
            ),
            Paragraph(
                heading: "Source code",
                body: "The source code and releases are at github.com/KammyUnix/pwned."
            )
        ]
    )

    static let privacy = InfoDocument(
        title: "Privacy",
        paragraphs: [
            Paragraph(
                heading: "What stays on this device",
                body: "Your notes, the links between notes and research items, bookmarks, recently viewed items, remembered searches, downloaded vulnerability records and settings are stored on this device. Pwned doesn't upload them and has no accounts."
            ),
            Paragraph(
                heading: "What is sent over the network",
                body: "Pwned contacts two services. NVD (services.nvd.nist.gov) receives requests for vulnerability records, which contain what is being looked up, such as a CVE number or a date range. GitHub (api.github.com) receives the owner and name of a repository when you open its page, and a request for the latest release when the app checks for updates. Both can see your IP address, as any website can. Links you tap open in Safari or in the in-app browser, and those sites have their own policies."
            ),
            Paragraph(
                heading: "What Pwned doesn't do",
                body: "It has no analytics, no advertising, no tracking and no third-party code."
            ),
            Paragraph(
                heading: "NVD API key",
                body: "If you add an NVD API key, it is kept in this device's Keychain and sent only to NVD."
            ),
            Paragraph(
                heading: "Your controls",
                body: "Settings, under Data & Privacy, lets you turn off recently viewed items and search history and clear them, clear downloaded data, export your notes, stop cellular use, turn off the automatic update check, and erase everything you created."
            )
        ]
    )

    static let legal = InfoDocument(
        title: "Legal Notices",
        paragraphs: [
            Paragraph(
                heading: "As is",
                body: "Pwned is provided as is, without warranty of any kind. Vulnerability data can be incomplete, late or wrong, and Pwned's Apple classification is a best guess from the evidence in each record. Check the original advisory before you rely on it."
            ),
            Paragraph(
                heading: "Use it responsibly",
                body: "Pwned is for research and learning. Only test systems you own or have permission to test."
            ),
            Paragraph(
                heading: "National Vulnerability Database",
                body: nvdNotice
            ),
            Paragraph(
                heading: "Trademarks",
                body: "Apple, iPhone, iPad, iOS, iPadOS, macOS, watchOS, tvOS and visionOS are trademarks of Apple Inc. GitHub is a trademark of GitHub, Inc. Pwned is an independent project and is not affiliated with or endorsed by Apple, GitHub or NIST."
            )
        ]
    )
}

struct InfoDocumentView: View {
    let document: InfoDocument

    var body: some View {
        List {
            ForEach(document.paragraphs) { paragraph in
                Section {
                    Text(paragraph.body)
                        .textSelection(.enabled)
                } header: {
                    Text(paragraph.heading)
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
