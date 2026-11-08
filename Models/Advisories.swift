import Foundation

/// An entry from Apple's security releases listing.
struct AppleAdvisory: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var platforms: [ApplePlatform]
    var updatedAt: Date
    var url: URL?
    var provenance: InformationProvenance

    var isSample: Bool { provenance == .sample }
}

/// A notable security announcement (CISA alert, vendor blog post, and so on).
struct SecurityAnnouncement: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
    var source: String
    var date: Date
    var provenance: InformationProvenance

    var isSample: Bool { provenance == .sample }
}
