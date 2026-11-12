import Foundation
@testable import Pwned

/// Builders for test data. Records are made up for the test and use obviously
/// synthetic identifiers; nothing here is real intelligence.
enum Fixtures {
    static let day: TimeInterval = 86_400
    static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

    static func product(
        _ vendor: String,
        _ product: String,
        versions: String = "before 1.0",
        origin: AffectedProduct.Origin? = .nvdAnalysis
    ) -> AffectedProduct {
        AffectedProduct(vendor: vendor, product: product, versions: versions, origin: origin)
    }

    static func reference(_ urlText: String) -> ExternalReference {
        ExternalReference(title: urlText, url: URL(string: urlText)!, kind: .advisory)
    }

    static func vulnerability(
        id: String = "CVE-2026-0001",
        summary: String = "An unspecified issue.",
        score: Double? = nil,
        publishedDaysAgo: Double = 0,
        products: [AffectedProduct] = [],
        references: [ExternalReference] = [],
        source: String? = nil,
        kev: KnownExploitedInfo? = nil,
        runsOn: [AffectedProduct]? = nil
    ) -> Vulnerability {
        let published = referenceDate.addingTimeInterval(-publishedDaysAgo * day)
        return Vulnerability(
            id: id,
            summary: summary,
            cvss: score.map { CVSSScore(version: "3.1", baseScore: $0, vector: nil) },
            publishedAt: published,
            modifiedAt: published,
            affectedProducts: products,
            references: references,
            relatedIDs: [],
            isKnownExploited: kev != nil,
            provenance: .verified,
            kev: kev,
            sourceIdentifier: source,
            runsOn: runsOn
        )
    }

    /// A temporary directory that the test removes when it finishes.
    static func temporaryDirectory(for testCase: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PwnedTests-\(testCase)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
