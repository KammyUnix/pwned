import Foundation

/// How much trust a piece of information deserves.
///
/// Every record Pwned shows carries one of these values so that verified data,
/// official advisories, community research and unconfirmed claims are never
/// visually conflated. `.sample` marks built-in development data that is not
/// real intelligence.
enum InformationProvenance: String, Codable, CaseIterable, Identifiable, Sendable {
    case verified
    case officialAdvisory
    case communityResearch
    case unconfirmed
    case sample

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verified: "Verified"
        case .officialAdvisory: "Official Advisory"
        case .communityResearch: "Community Research"
        case .unconfirmed: "Unconfirmed"
        case .sample: "Sample Data"
        }
    }

    var detail: String {
        switch self {
        case .verified:
            "Confirmed by an authoritative database such as NVD, OSV or the CISA Known Exploited Vulnerabilities catalog."
        case .officialAdvisory:
            "Published by the vendor or maintainer in an official security advisory or release note."
        case .communityResearch:
            "Published by independent researchers. Includes reverse-engineered and third-party findings."
        case .unconfirmed:
            "A claim that no authoritative source has confirmed. Treat with caution."
        case .sample:
            "Built-in development data used to exercise the interface. It is not real intelligence."
        }
    }

    var systemImage: String {
        switch self {
        case .verified: "checkmark.seal"
        case .officialAdvisory: "building.columns"
        case .communityResearch: "person.2"
        case .unconfirmed: "questionmark.circle"
        case .sample: "square.dashed"
        }
    }
}
