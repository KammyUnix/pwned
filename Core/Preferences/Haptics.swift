import UIKit

/// Haptic feedback, scaled by the user's preference.
///
/// Call sites say what happened; this decides whether and how strongly to
/// respond. With the preference off nothing is played.
@MainActor
enum Haptics {
    enum Event {
        /// A light confirmation, such as adding a bookmark.
        case tap
        /// Something finished that the user asked for.
        case success
        /// A destructive or irreversible action.
        case warning
    }

    static func play(_ event: Event, level: HapticLevel = AppSettings.hapticLevel()) {
        guard level.isEnabled else { return }
        switch event {
        case .tap:
            impact(for: level)
        case .success:
            // Notification haptics have no strength setting, so a subtle
            // preference uses a light tap instead.
            if level == .subtle {
                impact(for: level)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        case .warning:
            if level == .subtle {
                impact(for: level)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    private static func impact(for level: HapticLevel) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch level {
        case .off, .subtle: .light
        case .standard: .medium
        case .strong: .heavy
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
