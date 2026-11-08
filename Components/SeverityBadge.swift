import SwiftUI

extension Severity {
    /// System colors only. Color never carries meaning alone: the title is always shown.
    var tint: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .green
        case .none, .unknown: .gray
        }
    }
}

/// Compact severity indicator: a colored dot, the rating name and, when
/// available, the CVSS base score.
struct SeverityBadge: View {
    let severity: Severity
    var score: Double?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(severity.tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            if let score {
                Text(score, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            Text(severity.title)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let score {
            return "Severity \(severity.title), CVSS \(score.formatted(.number.precision(.fractionLength(1))))"
        }
        return "Severity \(severity.title)"
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        SeverityBadge(severity: .critical, score: 9.8)
        SeverityBadge(severity: .medium, score: 5.5)
        SeverityBadge(severity: .unknown)
    }
    .padding()
}
