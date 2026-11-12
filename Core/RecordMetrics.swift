import Foundation

extension Date {
    /// Compact absolute date such as "Nov 7, 2026".
    var shortDateLabel: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

extension DataSourceState {
    /// One-line, user-facing description of where the data came from.
    var summary: String {
        switch self {
        case .empty:
            return "Nothing is saved on this device yet."
        case .cached(let lastUpdated):
            guard let lastUpdated else { return "Saved on this device." }
            return "Saved on this device. Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))."
        case .live(let lastUpdated):
            return "Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))."
        }
    }
}

extension Collection {
    /// Singular/plural helper: `3.countLabel("note")` style callers use
    /// `items.countLabel(singular:plural:)`.
    func countLabel(singular: String, plural: String? = nil) -> String {
        let word = count == 1 ? singular : (plural ?? singular + "s")
        return "\(count) \(word)"
    }
}
