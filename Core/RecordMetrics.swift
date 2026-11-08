import Foundation

extension Date {
    /// Compact absolute date such as "Nov 7, 2026".
    var shortDateLabel: String {
        formatted(date: .abbreviated, time: .omitted)
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
