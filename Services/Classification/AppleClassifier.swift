import Foundation

/// How strongly the evidence says a vulnerability concerns the Apple ecosystem.
enum AppleRelevance: Int, Codable, Comparable, CaseIterable, Sendable {
    /// No credible Apple evidence.
    case notApple = 0
    /// Some Apple-related evidence, but not enough to say the vulnerability
    /// affects an Apple platform. Kept as a candidate, not shown in Discover by default.
    case uncertain
    /// Solid evidence from more than a text match.
    case likely
    /// An authoritative source says an Apple product is affected.
    case confirmed

    static func < (lhs: AppleRelevance, rhs: AppleRelevance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// True when the record belongs in the Apple-focused Discover feed.
    var isAppleFocused: Bool { self >= .likely }

    var title: String {
        switch self {
        case .notApple: "Not Apple-Related"
        case .uncertain: "Needs Review"
        case .likely: "Likely Apple"
        case .confirmed: "Confirmed Apple"
        }
    }
}

/// One piece of evidence behind a classification, kept so the UI can show why a
/// record was (or was not) treated as Apple research.
struct AppleSignal: Hashable, Sendable {
    enum Kind: String, Sendable {
        case cpeVulnerableApple
        case appleCNA
        case vendorReportedApple
        case appleAdvisoryReference
        case knownExploitedApple
        case fixedInApplePlatform
        case platformContextApple
        case descriptionPlatform
        case descriptionComponent
        case appleHostedReference
        case webKitPort
    }

    let kind: Kind
    /// What the evidence refers to, for example a product name.
    let detail: String

    var title: String {
        switch kind {
        case .cpeVulnerableApple: "NVD lists \(detail) as affected"
        case .appleCNA: "Published by Apple's product security team"
        case .vendorReportedApple: "The publisher reports \(detail) as affected"
        case .appleAdvisoryReference: "References an Apple security release"
        case .knownExploitedApple: "Listed by CISA as an Apple vulnerability"
        case .fixedInApplePlatform: "The description says the fix shipped in \(detail)"
        case .platformContextApple: "Affects software running on \(detail)"
        case .descriptionPlatform: "The description mentions \(detail)"
        case .descriptionComponent: "The description mentions \(detail)"
        case .appleHostedReference: "References a page hosted by Apple"
        case .webKitPort: "Affects a WebKit port (\(detail)) that may share code with Apple's WebKit"
        }
    }
}

/// The result of classifying one vulnerability. Derived data: it is recomputed
/// from the stored record, so it improves whenever the record gains evidence.
struct AppleClassification: Equatable, Sendable {
    var relevance: AppleRelevance
    /// 0...1. How sure the classifier is of `relevance`, including for `.notApple`.
    var confidence: Double
    /// Apple operating systems the record concerns.
    var platforms: [ApplePlatform]
    /// `ResearchCatalog` topic IDs the record concerns.
    var componentIDs: [String]
    var signals: [AppleSignal]

    static let unclassified = AppleClassification(
        relevance: .notApple, confidence: 0, platforms: [], componentIDs: [], signals: []
    )

    var isAppleFocused: Bool { relevance.isAppleFocused }
}

/// Decides whether a vulnerability concerns the Apple ecosystem.
///
/// Classification uses several kinds of evidence and never rests on a keyword
/// alone:
///
/// * **Confirmed:** NVD's analysis lists an Apple product as vulnerable, or Apple's
///   own CNA published the record.
/// * **Likely:** the CNA reports an Apple product, the record cites an Apple
///   security release, CISA's catalog names it an Apple vulnerability, or the
///   description says the fix shipped in an Apple platform release.
/// * **Uncertain:** only weak evidence, such as a description that mentions an
///   Apple platform, third-party software running on an Apple platform, or a
///   WebKit port. These are kept as candidates but stay out of the Apple feed.
/// * **Not Apple:** no credible evidence. A description that merely says "Apple"
///   or names iOS is not proof the vulnerability affects an Apple product.
enum AppleClassifier {
    static let appleCNAIdentifier = "product-security@apple.com"

    private static let webKitPortVendors: Set<String> = ["webkitgtk", "wpewebkit"]

    // MARK: Entry points

    static func classify(_ records: [Vulnerability]) -> [String: AppleClassification] {
        var result: [String: AppleClassification] = [:]
        result.reserveCapacity(records.count)
        for record in records {
            result[record.id.uppercased()] = classify(record)
        }
        return result
    }

    static func classify(_ record: Vulnerability) -> AppleClassification {
        var signals: [AppleSignal] = []
        var platforms = Set<ApplePlatform>()
        var components = Set<String>()

        collectProductEvidence(from: record, signals: &signals, platforms: &platforms, components: &components)
        collectSourceEvidence(from: record, signals: &signals)
        collectReferenceEvidence(from: record, signals: &signals)
        collectDescriptionEvidence(from: record, signals: &signals, platforms: &platforms, components: &components)

        let kinds = Set(signals.map(\.kind))
        let strong: Set<AppleSignal.Kind> = [.cpeVulnerableApple, .appleCNA]
        let solid: Set<AppleSignal.Kind> = [
            .vendorReportedApple, .appleAdvisoryReference, .knownExploitedApple, .fixedInApplePlatform
        ]
        let weak: Set<AppleSignal.Kind> = [
            .platformContextApple, .descriptionPlatform, .descriptionComponent, .appleHostedReference, .webKitPort
        ]

        let relevance: AppleRelevance
        let confidence: Double

        if !kinds.isDisjoint(with: strong) {
            relevance = .confirmed
            confidence = kinds.isSuperset(of: strong) ? 0.99 : 0.95
        } else if !kinds.isDisjoint(with: solid) {
            relevance = .likely
            let extra = kinds.intersection(solid).count - 1
            confidence = min(0.8 + 0.05 * Double(extra), 0.92)
        } else if kinds.contains(.descriptionPlatform), kinds.contains(.descriptionComponent) {
            // An Apple platform and an Apple-specific component named together
            // is stronger than either alone, but still only the description.
            relevance = .likely
            confidence = 0.7
        } else if !kinds.isDisjoint(with: weak) {
            relevance = .uncertain
            confidence = min(0.3 + 0.1 * Double(kinds.intersection(weak).count), 0.6)
        } else {
            relevance = .notApple
            confidence = notAppleConfidence(for: record)
        }

        let keepsTags = relevance >= .likely
        return AppleClassification(
            relevance: relevance,
            confidence: confidence,
            platforms: keepsTags ? ApplePlatform.allCases.filter { platforms.contains($0) } : [],
            componentIDs: keepsTags ? components.sorted() : [],
            signals: orderedSignals(signals)
        )
    }

    // MARK: Evidence: products

    private static func collectProductEvidence(
        from record: Vulnerability,
        signals: inout [AppleSignal],
        platforms: inout Set<ApplePlatform>,
        components: inout Set<String>
    ) {
        for product in record.affectedProducts {
            if AppleNaming.isApple(product.vendor) {
                let name = AppleNaming.productName(vendor: product.vendor, product: product.product)
                // Products reported by the CNA are weaker than ones NVD's analysts matched.
                let kind: AppleSignal.Kind = (product.origin == .vendorReported)
                    ? .vendorReportedApple : .cpeVulnerableApple
                signals.append(AppleSignal(kind: kind, detail: name))
                note(productKey: AppleNaming.key(for: product.product), platforms: &platforms, components: &components)
            } else if webKitPortVendors.contains(AppleNaming.key(for: product.vendor)) {
                signals.append(AppleSignal(
                    kind: .webKitPort,
                    detail: AppleNaming.productName(vendor: product.vendor, product: product.product)
                ))
            }
        }

        // Non-vulnerable platform context from AND configurations: the
        // vulnerable software is someone else's, and it runs on an Apple OS.
        for context in record.runsOn ?? [] where AppleNaming.isApple(context.vendor) {
            signals.append(AppleSignal(
                kind: .platformContextApple,
                detail: AppleNaming.productName(vendor: context.vendor, product: context.product)
            ))
            note(productKey: AppleNaming.key(for: context.product), platforms: &platforms, components: &components)
        }
    }

    private static func note(
        productKey: String,
        platforms: inout Set<ApplePlatform>,
        components: inout Set<String>
    ) {
        switch productKey {
        case "ios", "iphoneos": platforms.insert(.iOS)
        case "ipados": platforms.insert(.iPadOS)
        case "macos", "macosx", "osx": platforms.insert(.macOS)
        case "watchos": platforms.insert(.watchOS)
        case "tvos": platforms.insert(.tvOS)
        case "visionos", "xros": platforms.insert(.visionOS)
        case "safari": components.insert("safari")
        case "xcode": components.insert("xcode")
        default: break
        }
    }

    // MARK: Evidence: source and KEV

    private static func collectSourceEvidence(from record: Vulnerability, signals: inout [AppleSignal]) {
        if record.sourceIdentifier?.lowercased() == appleCNAIdentifier {
            signals.append(AppleSignal(kind: .appleCNA, detail: appleCNAIdentifier))
        }
        if let name = record.kev?.name, name.lowercased().hasPrefix("apple") {
            signals.append(AppleSignal(kind: .knownExploitedApple, detail: name))
        }
    }

    // MARK: Evidence: references

    private static func collectReferenceEvidence(from record: Vulnerability, signals: inout [AppleSignal]) {
        var sawSecurityRelease = false
        var sawAppleHost = false

        for reference in record.references {
            guard let host = reference.url.host()?.lowercased() else { continue }
            let isApple = host == "apple.com" || host.hasSuffix(".apple.com")
            guard isApple else { continue }

            if host == "support.apple.com", isSecurityReleasePath(reference.url.path) {
                sawSecurityRelease = true
            } else {
                sawAppleHost = true
            }
        }

        if sawSecurityRelease {
            signals.append(AppleSignal(kind: .appleAdvisoryReference, detail: "support.apple.com"))
        } else if sawAppleHost {
            signals.append(AppleSignal(kind: .appleHostedReference, detail: "apple.com"))
        }
    }

    /// Apple security releases live at `support.apple.com/<locale>/<id>` with a
    /// six-digit ID (for example `/en-us/124567`) or the older `/HT201222` form.
    private static func isSecurityReleasePath(_ path: String) -> Bool {
        for component in path.split(separator: "/") {
            let text = component.lowercased()
            if text.hasPrefix("ht"), text.dropFirst(2).count >= 4, text.dropFirst(2).allSatisfy(\.isNumber) {
                return true
            }
            if text.count >= 5, text.count <= 7, text.allSatisfy(\.isNumber) {
                return true
            }
        }
        return false
    }

    // MARK: Evidence: description

    private static func collectDescriptionEvidence(
        from record: Vulnerability,
        signals: inout [AppleSignal],
        platforms: inout Set<ApplePlatform>,
        components: inout Set<String>
    ) {
        let text = record.summary
        let matches = TermMatcher.matches(in: text, mode: .description)
        var seenPlatformSignals = Set<String>()
        var seenComponentSignals = Set<String>()

        for match in matches {
            guard let topic = ResearchCatalog.topic(withID: match.topicID) else { continue }

            if topic.kind == .product {
                if let platform = ApplePlatform(searchToken: topic.name) {
                    platforms.insert(platform)
                }
                if seenPlatformSignals.insert(topic.id).inserted {
                    signals.append(AppleSignal(kind: .descriptionPlatform, detail: topic.name))
                }
                if isFixAnnouncement(in: text, before: match.range.lowerBound),
                   seenPlatformSignals.insert("fixed-\(topic.id)").inserted {
                    signals.append(AppleSignal(kind: .fixedInApplePlatform, detail: topic.name))
                }
            } else {
                components.insert(topic.id)
                if topic.isAppleSpecific, seenComponentSignals.insert(topic.id).inserted {
                    signals.append(AppleSignal(kind: .descriptionComponent, detail: topic.name))
                }
            }
        }
    }

    /// Apple's own descriptions announce fixes as "This issue is fixed in iOS 18.2".
    private static func isFixAnnouncement(in text: String, before index: String.Index) -> Bool {
        let lead = text[..<index].suffix(40).lowercased()
        return lead.contains("fixed in") || lead.contains("addressed in") || lead.contains("resolved in")
    }

    // MARK: Confidence for "not Apple"

    /// How sure we are that a record without Apple evidence is not Apple's.
    private static func notAppleConfidence(for record: Vulnerability) -> Double {
        if record.affectedProducts.contains(where: { $0.origin == .nvdAnalysis }) { return 0.95 }
        if record.affectedProducts.contains(where: { $0.origin == .vendorReported }) { return 0.85 }
        // No product data at all: nothing points to Apple, but the record is thin.
        return 0.6
    }

    // MARK: Ordering

    /// Strongest evidence first, without duplicates.
    private static func orderedSignals(_ signals: [AppleSignal]) -> [AppleSignal] {
        let order: [AppleSignal.Kind] = [
            .cpeVulnerableApple, .appleCNA, .vendorReportedApple, .appleAdvisoryReference,
            .knownExploitedApple, .fixedInApplePlatform, .platformContextApple,
            .descriptionPlatform, .descriptionComponent, .webKitPort, .appleHostedReference
        ]
        var seen = Set<AppleSignal>()
        let unique = signals.filter { seen.insert($0).inserted }
        return unique.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = order.firstIndex(of: lhs.element.kind) ?? order.count
                let rhsRank = order.firstIndex(of: rhs.element.kind) ?? order.count
                return lhsRank != rhsRank ? lhsRank < rhsRank : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
