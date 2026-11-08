import Foundation

/// Development sample data.
///
/// Everything here is synthetic and carries `InformationProvenance.sample`, so
/// the UI labels it as sample data. Identifiers use the year 2099
/// (`CVE-2099-…`), which cannot collide with a real CVE, and no record
/// describes a real vulnerability, advisory or repository. It is replaced by
/// live sources in later phases.
enum SampleData {
    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(calendar: Calendar(identifier: .gregorian),
                                        timeZone: TimeZone(secondsFromGMT: 0),
                                        year: year, month: month, day: day, hour: 12)
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private static let nvdHome = URL(string: "https://nvd.nist.gov/")!
    private static let appleReleases = URL(string: "https://support.apple.com/en-us/100100")!
    private static let cisaKEV = URL(string: "https://www.cisa.gov/known-exploited-vulnerabilities-catalog")!

    // MARK: Vulnerabilities

    static let vulnerabilities: [Vulnerability] = [
        Vulnerability(
            id: "CVE-2099-0001",
            summary: "Sample record: memory corruption in a media parsing component, used to exercise critical-severity layouts.",
            cvss: CVSSScore(version: "3.1", baseScore: 9.8, vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"),
            publishedAt: date(2026, 11, 3),
            modifiedAt: date(2026, 11, 5),
            affectedProducts: [
                AffectedProduct(vendor: "Example Vendor", product: "Sample iOS", versions: "before 26.3 (sample)")
            ],
            references: [
                ExternalReference(title: "NVD (sample reference)", url: nvdHome, kind: .report),
                ExternalReference(title: "Apple security releases", url: appleReleases, kind: .advisory)
            ],
            relatedIDs: ["CVE-2099-0002"],
            isKnownExploited: true,
            provenance: .sample
        ),
        Vulnerability(
            id: "CVE-2099-0002",
            summary: "Sample record: out-of-bounds read in a browser engine component, used to exercise high-severity layouts.",
            cvss: CVSSScore(version: "3.1", baseScore: 8.8, vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H"),
            publishedAt: date(2026, 11, 3),
            modifiedAt: date(2026, 11, 4),
            affectedProducts: [
                AffectedProduct(vendor: "Example Vendor", product: "Sample WebKit", versions: "before 26.3 (sample)")
            ],
            references: [
                ExternalReference(title: "Apple security releases", url: appleReleases, kind: .advisory)
            ],
            relatedIDs: ["CVE-2099-0001"],
            isKnownExploited: false,
            provenance: .sample
        ),
        Vulnerability(
            id: "CVE-2099-0003",
            summary: "Sample record: logic issue in an entitlement check, used to exercise medium-severity layouts.",
            cvss: CVSSScore(version: "3.1", baseScore: 5.5, vector: "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N"),
            publishedAt: date(2026, 10, 28),
            modifiedAt: date(2026, 10, 30),
            affectedProducts: [
                AffectedProduct(vendor: "Example Vendor", product: "Sample macOS", versions: "26.0 through 26.2 (sample)")
            ],
            references: [
                ExternalReference(title: "NVD (sample reference)", url: nvdHome, kind: .report)
            ],
            relatedIDs: [],
            isKnownExploited: false,
            provenance: .sample
        ),
        Vulnerability(
            id: "CVE-2099-0004",
            summary: "Sample record: information disclosure in a diagnostics log, used to exercise low-severity layouts.",
            cvss: CVSSScore(version: "3.1", baseScore: 3.3, vector: "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N"),
            publishedAt: date(2026, 10, 21),
            modifiedAt: date(2026, 10, 21),
            affectedProducts: [
                AffectedProduct(vendor: "Example Vendor", product: "Sample iPadOS", versions: "before 26.2 (sample)")
            ],
            references: [],
            relatedIDs: [],
            isKnownExploited: false,
            provenance: .sample
        ),
        Vulnerability(
            id: "CVE-2099-0005",
            summary: "Sample record: awaiting analysis; no score assigned, used to exercise the unrated state.",
            cvss: nil,
            publishedAt: date(2026, 11, 6),
            modifiedAt: date(2026, 11, 6),
            affectedProducts: [],
            references: [
                ExternalReference(title: "CISA Known Exploited Vulnerabilities catalog", url: cisaKEV, kind: .other)
            ],
            relatedIDs: [],
            isKnownExploited: false,
            provenance: .sample
        )
    ]

    // MARK: Apple advisories

    static let appleAdvisories: [AppleAdvisory] = [
        AppleAdvisory(
            id: "sample-advisory-1",
            title: "Sample: iOS and iPadOS security content",
            platforms: [.iOS, .iPadOS],
            updatedAt: date(2026, 11, 5),
            url: appleReleases,
            provenance: .sample
        ),
        AppleAdvisory(
            id: "sample-advisory-2",
            title: "Sample: macOS security content",
            platforms: [.macOS],
            updatedAt: date(2026, 11, 4),
            url: appleReleases,
            provenance: .sample
        ),
        AppleAdvisory(
            id: "sample-advisory-3",
            title: "Sample: watchOS and visionOS security content",
            platforms: [.watchOS, .visionOS],
            updatedAt: date(2026, 10, 30),
            url: appleReleases,
            provenance: .sample
        )
    ]

    // MARK: Announcements

    static let announcements: [SecurityAnnouncement] = [
        SecurityAnnouncement(
            id: "sample-announcement-1",
            title: "Sample: actively exploited vulnerability added to a catalog",
            detail: "Placeholder announcement used to exercise the dashboard layout.",
            source: "Sample source",
            date: date(2026, 11, 6),
            provenance: .sample
        ),
        SecurityAnnouncement(
            id: "sample-announcement-2",
            title: "Sample: coordinated disclosure notice",
            detail: "Placeholder announcement used to exercise the dashboard layout.",
            source: "Sample source",
            date: date(2026, 11, 2),
            provenance: .sample
        )
    ]

    // MARK: Repositories

    static let repositories: [RepositorySummary] = [
        RepositorySummary(
            owner: "example-org", name: "sample-kernel-notes",
            summary: "Sample repository entry. Not a real project.",
            primaryLanguage: "C", stars: 0,
            updatedAt: date(2026, 11, 5), provenance: .sample
        ),
        RepositorySummary(
            owner: "example-org", name: "sample-macho-tools",
            summary: "Sample repository entry. Not a real project.",
            primaryLanguage: "Swift", stars: 0,
            updatedAt: date(2026, 11, 1), provenance: .sample
        ),
        RepositorySummary(
            owner: "example-org", name: "sample-ipa-inspector",
            summary: "Sample repository entry. Not a real project.",
            primaryLanguage: "Python", stars: 0,
            updatedAt: date(2026, 10, 25), provenance: .sample
        )
    ]
}
