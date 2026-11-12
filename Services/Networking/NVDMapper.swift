import Foundation

/// Converts NVD wire records into the app's `Vulnerability` model.
///
/// Nothing here invents data: a field NVD doesn't provide stays empty or nil.
enum NVDMapper {
    private static let maxProducts = 60
    private static let maxVersionsPerProduct = 8
    private static let maxReferences = 100
    private static let maxRelatedIDs = 10

    static func vulnerabilities(from response: NVDResponse) -> [Vulnerability] {
        response.vulnerabilities.compactMap { vulnerability(from: $0.cve) }
    }

    static func vulnerability(from cve: NVDResponse.CVE) -> Vulnerability? {
        let published = NVDDate.parse(cve.published)
        let modified = NVDDate.parse(cve.lastModified)
        guard let publishedAt = published ?? modified else { return nil }
        let modifiedAt = modified ?? publishedAt

        let summary = englishText(cve.descriptions) ?? "No description available."
        let scoreSet = scores(from: cve.metrics)
        let products = affectedProducts(from: cve)

        return Vulnerability(
            id: cve.id.uppercased(),
            summary: summary,
            cvss: scoreSet.first,
            publishedAt: publishedAt,
            modifiedAt: modifiedAt,
            affectedProducts: products.items,
            references: references(from: cve.references),
            relatedIDs: relatedIDs(in: summary, excluding: cve.id),
            isKnownExploited: cve.cisaExploitAdd != nil,
            provenance: .verified,
            analysisStatus: cve.vulnStatus,
            weaknesses: weaknesses(from: cve.weaknesses),
            additionalScores: Array(scoreSet.dropFirst()),
            kev: knownExploited(from: cve),
            sourceIdentifier: cve.sourceIdentifier,
            omittedProductCount: products.omitted,
            runsOn: platformContext(from: cve)
        )
    }

    // MARK: Description

    private static func englishText(_ strings: [NVDResponse.LangString]) -> String? {
        let preferred = strings.first { $0.lang?.lowercased().hasPrefix("en") == true } ?? strings.first
        let text = preferred?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    // MARK: Scores

    /// All scores, headline first. Preference: CVSS 3.1, 4.0, 3.0, then 2.0.
    /// Within a version, NVD's own ("Primary") score comes before CNA ("Secondary") scores.
    private static func scores(from metrics: NVDResponse.Metrics?) -> [CVSSScore] {
        guard let metrics else { return [] }
        let groups: [(String, [NVDResponse.Metric])] = [
            ("3.1", metrics.cvssMetricV31),
            ("4.0", metrics.cvssMetricV40),
            ("3.0", metrics.cvssMetricV30),
            ("2.0", metrics.cvssMetricV2)
        ]

        var result: [CVSSScore] = []
        for (fallbackVersion, metricList) in groups {
            let converted = metricList.compactMap { score(from: $0, fallbackVersion: fallbackVersion) }
            let primary = converted.filter { $0.isPrimary == true }
            let others = converted.filter { $0.isPrimary != true }
            result += primary + others
        }
        return result
    }

    private static func score(from metric: NVDResponse.Metric, fallbackVersion: String) -> CVSSScore? {
        guard let data = metric.cvssData, let baseScore = data.baseScore else { return nil }
        let isPrimary: Bool? = metric.type.map { $0.caseInsensitiveCompare("Primary") == .orderedSame }
        return CVSSScore(
            version: data.version ?? fallbackVersion,
            baseScore: baseScore,
            vector: data.vectorString,
            source: metric.source,
            isPrimary: isPrimary
        )
    }

    // MARK: Weaknesses

    private static func weaknesses(from weaknesses: [NVDResponse.Weakness]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for weakness in weaknesses {
            for entry in weakness.description ?? [] {
                guard let value = entry.value?.trimmingCharacters(in: .whitespaces),
                      value.hasPrefix("CWE-") || value.hasPrefix("NVD-CWE-"),
                      seen.insert(value).inserted else { continue }
                result.append(value)
            }
        }
        return result
    }

    // MARK: Known exploited

    private static func knownExploited(from cve: NVDResponse.CVE) -> KnownExploitedInfo? {
        guard cve.cisaExploitAdd != nil else { return nil }
        return KnownExploitedInfo(
            name: cve.cisaVulnerabilityName,
            dateAdded: NVDDate.parse(cve.cisaExploitAdd),
            dueDate: NVDDate.parse(cve.cisaActionDue),
            requiredAction: cve.cisaRequiredAction
        )
    }

    // MARK: References

    private static func references(from references: [NVDResponse.Reference]) -> [ExternalReference] {
        var seen = Set<String>()
        var result: [ExternalReference] = []
        for reference in references {
            guard let text = reference.url,
                  let url = URL(string: text),
                  seen.insert(url.absoluteString).inserted else { continue }
            let tags = reference.tags ?? []
            result.append(ExternalReference(
                title: url.host() ?? text,
                url: url,
                kind: kind(for: tags),
                tags: tags,
                source: reference.source
            ))
            if result.count >= maxReferences { break }
        }
        // Stable ordering: official advisories first, then patches, exploits, reports.
        return result.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs.element.kind)
                let rhsRank = rank(rhs.element.kind)
                return lhsRank != rhsRank ? lhsRank < rhsRank : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func kind(for tags: [String]) -> ExternalReference.Kind {
        let lowered = Set(tags.map { $0.lowercased() })
        if lowered.contains("vendor advisory") || lowered.contains("us government resource") {
            return .advisory
        }
        if lowered.contains("patch") || lowered.contains("mitigation") {
            return .patch
        }
        if lowered.contains("exploit") {
            return .exploit
        }
        if lowered.contains("third party advisory") || lowered.contains("issue tracking")
            || lowered.contains("technical description") || lowered.contains("release notes") {
            return .report
        }
        return .other
    }

    private static func rank(_ kind: ExternalReference.Kind) -> Int {
        switch kind {
        case .advisory: 0
        case .patch: 1
        case .exploit: 2
        case .report: 3
        case .other: 4
        }
    }

    // MARK: Related CVEs

    /// CVE identifiers mentioned in the description, which is what NVD records
    /// use to point at related issues ("a bypass of CVE-2023-…").
    private static func relatedIDs(in text: String, excluding id: String) -> [String] {
        var seen = Set<String>([id.uppercased()])
        var result: [String] = []
        let tokens = text.split { !($0.isLetter || $0.isNumber || $0 == "-") }
        for token in tokens {
            guard let cve = SearchClassifier.normalizedCVE(String(token)),
                  seen.insert(cve).inserted else { continue }
            result.append(cve)
            if result.count >= maxRelatedIDs { break }
        }
        return result
    }

    // MARK: Affected products

    private struct ProductAccumulator {
        var vendor: String
        var product: String
        var versions: [String] = []
        var origin: AffectedProduct.Origin
    }

    private static func affectedProducts(from cve: NVDResponse.CVE) -> (items: [AffectedProduct], omitted: Int) {
        var order: [String] = []
        var table: [String: ProductAccumulator] = [:]

        func add(vendor: String, product: String, version: String, origin: AffectedProduct.Origin) {
            let key = "\(vendor.lowercased())|\(product.lowercased())"
            if table[key] == nil {
                table[key] = ProductAccumulator(vendor: vendor, product: product, origin: origin)
                order.append(key)
            }
            if !version.isEmpty, table[key]?.versions.contains(version) == false {
                table[key]?.versions.append(version)
            }
        }

        // 1. Products NVD analysts matched to CPE configurations. A negated node
        //    lists what must NOT be present, so it never names an affected product.
        for configuration in cve.configurations {
            for node in configuration.nodes ?? [] where node.negate != true {
                for match in node.cpeMatch ?? [] where match.vulnerable == true {
                    guard let criteria = match.criteria, let cpe = CPEName(criteria) else { continue }
                    add(vendor: cpe.vendor, product: cpe.product,
                        version: describe(match, cpe: cpe), origin: .nvdAnalysis)
                }
            }
        }

        // 2. Otherwise, products reported by the CNA (typical for CVEs NVD hasn't analyzed yet).
        if table.isEmpty {
            for entry in cve.affected {
                for data in entry.affectedData ?? [] {
                    guard let vendor = clean(data.vendor), let product = clean(data.product) else { continue }
                    let versions = (data.versions ?? []).compactMap { describeVersion($0) }
                    if versions.isEmpty {
                        add(vendor: vendor, product: product, version: "", origin: .vendorReported)
                    }
                    for version in versions {
                        add(vendor: vendor, product: product, version: version, origin: .vendorReported)
                    }
                }
            }
        }

        let keys = Array(order.prefix(maxProducts))
        let items = keys.compactMap { key -> AffectedProduct? in
            guard let entry = table[key] else { return nil }
            let shown = entry.versions.prefix(maxVersionsPerProduct)
            var text = shown.joined(separator: "; ")
            if entry.versions.count > shown.count {
                text += "; and \(entry.versions.count - shown.count) more"
            }
            return AffectedProduct(
                vendor: entry.vendor,
                product: entry.product,
                versions: text.isEmpty ? "Versions not specified" : text,
                origin: entry.origin
            )
        }
        return (items, max(order.count - keys.count, 0))
    }

    /// Apple platforms that appear in a configuration as non-vulnerable context.
    ///
    /// NVD expresses "software X running on iOS" as an AND configuration: X is
    /// marked vulnerable and iOS is listed alongside it as *not* vulnerable.
    /// That is the difference between a vulnerability in iOS and one in an app
    /// that merely runs on it, so it is recorded separately and only for Apple
    /// vendors (the one case classification needs).
    private static func platformContext(from cve: NVDResponse.CVE) -> [AffectedProduct]? {
        var order: [String] = []
        var table: [String: ProductAccumulator] = [:]

        for configuration in cve.configurations {
            // Only AND configurations pair a vulnerable product with a platform.
            guard configuration.configurationOperator?.uppercased() == "AND" else { continue }
            for node in configuration.nodes ?? [] where node.negate != true {
                for match in node.cpeMatch ?? [] where match.vulnerable != true {
                    guard let criteria = match.criteria,
                          let cpe = CPEName(criteria),
                          AppleNaming.isApple(cpe.vendor) else { continue }
                    let key = "\(cpe.vendor.lowercased())|\(cpe.product.lowercased())"
                    if table[key] == nil {
                        table[key] = ProductAccumulator(vendor: cpe.vendor, product: cpe.product, origin: .nvdAnalysis)
                        order.append(key)
                    }
                    let version = describe(match, cpe: cpe)
                    if table[key]?.versions.contains(version) == false {
                        table[key]?.versions.append(version)
                    }
                }
            }
        }

        let items = order.prefix(12).compactMap { key -> AffectedProduct? in
            guard let entry = table[key] else { return nil }
            return AffectedProduct(
                vendor: entry.vendor,
                product: entry.product,
                versions: entry.versions.prefix(maxVersionsPerProduct).joined(separator: "; "),
                origin: .nvdAnalysis
            )
        }
        return items.isEmpty ? nil : items
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Describes the version scope of a CPE match, for example "before 26.3".
    private static func describe(_ match: NVDResponse.CPEMatch, cpe: CPEName) -> String {
        var parts: [String] = []
        if let value = match.versionStartIncluding { parts.append("from \(value)") }
        if let value = match.versionStartExcluding { parts.append("after \(value)") }
        if let value = match.versionEndIncluding { parts.append("through \(value)") }
        if let value = match.versionEndExcluding { parts.append("before \(value)") }
        if !parts.isEmpty { return parts.joined(separator: " ") }

        switch cpe.version {
        case "*": return "All versions"
        case "-": return "Not applicable"
        default:
            let update = (cpe.update == "*" || cpe.update == "-" || cpe.update.isEmpty) ? "" : " \(cpe.update)"
            return cpe.version + update
        }
    }

    /// Describes one CNA-reported version entry.
    private static func describeVersion(_ version: NVDResponse.AffectedVersion) -> String? {
        let base = clean(version.version)

        // A lower bound of "0" means "from the first release", so it adds nothing.
        var lowerBound = ""
        if let base, base != "0" {
            lowerBound = "from \(base) "
        }

        if let upper = clean(version.lessThan) {
            return lowerBound + "before \(upper)"
        }
        if let upper = clean(version.lessThanOrEqual) {
            return lowerBound + "through \(upper)"
        }
        return base
    }
}

/// A parsed CPE 2.3 name: `cpe:2.3:part:vendor:product:version:update:...`.
struct CPEName: Equatable, Sendable {
    let part: String
    let vendor: String
    let product: String
    let version: String
    let update: String

    init?(_ text: String) {
        let fields = Self.split(text)
        guard fields.count >= 7, fields[0] == "cpe", fields[1] == "2.3" else { return nil }
        part = fields[2]
        vendor = fields[3].replacingOccurrences(of: "_", with: " ")
        product = fields[4].replacingOccurrences(of: "_", with: " ")
        version = fields[5]
        update = fields[6]
    }

    /// Splits on `:` while honoring backslash escapes (`\:` is a literal colon).
    private static func split(_ text: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var escaping = false
        for character in text {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == ":" {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }
}
