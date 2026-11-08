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

    var severity: Severity { Severity(cvssBaseScore: baseScore) }
}
