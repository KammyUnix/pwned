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

extension Severity {
    /// A distinct shape per severity, for people who can't rely on color.
    var symbolName: String {
        switch self {
        case .critical: "octagon.fill"
        case .high: "triangle.fill"
        case .medium: "diamond.fill"
        case .low: "circle.fill"
        case .none, .unknown: "minus.circle"
        }
    }
}

/// Compact severity indicator: a colored dot, the rating name and, when
/// available, the CVSS base score. With "Severity Symbols" on, or when iOS
/// asks to differentiate without color, the dot becomes a shape that differs
/// by severity.
struct SeverityBadge: View {
    let severity: Severity
    var score: Double?

    @Environment(\.pwnedSeveritySymbols) private var usesSymbols
    @Environment(\.pwnedHighContrast) private var highContrast

    var body: some View {
        HStack(spacing: 6) {
            marker
                .accessibilityHidden(true)
            if let score {
                Text(score, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            Text(severity.title)
                .foregroundStyle(highContrast ? .primary : .secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var marker: some View {
        if usesSymbols {
            Image(systemName: severity.symbolName)
                .font(.caption2)
                .foregroundStyle(severity.tint)
        } else {
            Circle()
                .fill(severity.tint)
                .frame(width: highContrast ? 10 : 8, height: highContrast ? 10 : 8)
                .overlay(Circle().strokeBorder(.primary.opacity(highContrast ? 0.6 : 0), lineWidth: 1))
        }
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
