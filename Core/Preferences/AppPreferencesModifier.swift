import SwiftUI

private struct HighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SeveritySymbolsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the user, or iOS, asks for stronger contrast.
    var pwnedHighContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }

    /// True when severity should also be shown by shape, not by color alone.
    var pwnedSeveritySymbols: Bool {
        get { self[SeveritySymbolsKey.self] }
        set { self[SeveritySymbolsKey.self] = newValue }
    }
}

extension View {
    /// Applies the appearance, text size, motion and accessibility preferences
    /// to everything below. Applied once, at the root.
    func appPreferences() -> some View {
        modifier(AppPreferencesModifier())
    }
}

struct AppPreferencesModifier: ViewModifier {
    @AppStorage(AppSettings.appearanceKey) private var appearance = AppSettings.Default.appearance
    @AppStorage(AppSettings.accentKey) private var accent = AppSettings.Default.accent
    @AppStorage(AppSettings.surfaceKey) private var surface = AppSettings.Default.surface
    @AppStorage(AppSettings.densityKey) private var density = AppSettings.Default.density
    @AppStorage(AppSettings.animationsKey) private var animations = AppSettings.Default.animations
    @AppStorage(AppSettings.textStepKey) private var textStep = AppSettings.Default.textStep
    @AppStorage(AppSettings.boldTextKey) private var boldText = AppSettings.Default.boldText
    @AppStorage(AppSettings.highContrastKey) private var highContrast = AppSettings.Default.highContrast
    @AppStorage(AppSettings.severitySymbolsKey) private var severitySymbols = AppSettings.Default.severitySymbols

    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.legibilityWeight) private var systemLegibility
    @Environment(\.defaultMinListRowHeight) private var systemRowHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            .tint(accent.color)
            .dynamicTypeSize(TextSize.adjusted(systemTypeSize, by: textStep))
            .environment(\.legibilityWeight, boldText ? .bold : systemLegibility)
            .environment(\.defaultMinListRowHeight, density.minimumRowHeight ?? systemRowHeight)
            .listSectionSpacing(density == .compact ? .compact : .default)
            .scrollContentBackground(surface == .plain ? .hidden : .automatic)
            .environment(\.pwnedHighContrast, highContrast || systemContrast == .increased)
            .environment(\.pwnedSeveritySymbols, severitySymbols || differentiateWithoutColor)
            .transaction { transaction in
                // The system's Reduce Motion always wins over this preference.
                if !animations || reduceMotion {
                    transaction.animation = nil
                }
            }
    }
}
