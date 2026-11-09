import Foundation

/// Qualitative severity derived from a CVSS base score using the standard
/// CVSS v3.x rating bands (None 0.0, Low 0.1–3.9, Medium 4.0–6.9,
/// High 7.0–8.9, Critical 9.0–10.0).
enum Severity: Int, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case unknown = 0
    case none
    case low
    case medium
    case high
    case critical

    var id: Int { rawValue }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(cvssBaseScore score: Double) {
        switch score {
        case ..<0.1: self = .none
        case ..<4.0: self = .low
        case ..<7.0: self = .medium
        case ..<9.0: self = .high
        default: self = .critical
        }
    }

    /// CVSS v2 has no Critical band: Low 0.0–3.9, Medium 4.0–6.9, High 7.0–10.0.
    init(cvssV2BaseScore score: Double) {
        switch score {
        case ..<4.0: self = .low
        case ..<7.0: self = .medium
        default: self = .high
        }
    }

    /// Severities offered by the filter menu, most severe first.
    static let filterOptions: [Severity] = [.critical, .high, .medium, .low, .unknown]

    /// Filter bucket for this severity. A score of exactly 0.0 is grouped with unrated.
    var filterBucket: Severity { self == .none ? .unknown : self }

    var title: String {
        switch self {
        case .unknown: "Unrated"
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }
}

struct CVSSScore: Codable, Hashable, Sendable {
    /// CVSS specification version, for example "3.1".
    var version: String
    var baseScore: Double
    /// Vector string such as `CVSS:3.1/AV:N/AC:L/...`, when available.
    var vector: String?
    /// Who supplied the score, for example `nvd@nist.gov` or a CNA address.
    var source: String? = nil
    /// True when NVD labels the score "Primary" (its own analysis), false for
    /// "Secondary" (a CNA or other source), nil when unknown.
    var isPrimary: Bool? = nil

    var severity: Severity {
        version.hasPrefix("2")
            ? Severity(cvssV2BaseScore: baseScore)
            : Severity(cvssBaseScore: baseScore)
    }

    var label: String { "CVSS \(version)" }
}
