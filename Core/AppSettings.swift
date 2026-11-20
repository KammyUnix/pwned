import SwiftUI

/// Keys and defaults for every preference stored in `UserDefaults`.
///
/// Each preference has one key and one place in the UI that changes it. Views
/// read them with `@AppStorage`; code outside views reads them through the
/// functions here, which take a `UserDefaults` so tests can use a private suite.
///
/// The NVD API key is the exception on purpose: it is a credential and lives
/// in the Keychain (`NVDAPIKeyStore`), never in defaults.
enum AppSettings {
    // MARK: Keys

    /// Whether Discover also lists records with some Apple evidence that isn't
    /// enough to call them Apple's. Changed from Discover's filter menu, so it
    /// has no row in Settings.
    static let includeUncertainKey = "discover.includeUncertainMatches"

    // Appearance
    static let appearanceKey = "appearance.mode"
    static let accentKey = "appearance.accent"
    static let surfaceKey = "appearance.surface"
    static let densityKey = "appearance.density"

    // Interface and navigation
    static let startTabKey = "interface.startTab"
    /// The tab that was open last. Written by the app, not shown in Settings.
    static let lastTabKey = "interface.lastTab"
    static let collapseTabBarKey = "interface.collapseTabBar"
    static let animationsKey = "interface.animations"
    static let hapticsKey = "interface.haptics"
    static let openLinksInAppKey = "interface.openLinksInApp"

    // Accessibility
    static let textStepKey = "accessibility.textStep"
    static let boldTextKey = "accessibility.boldText"
    static let highContrastKey = "accessibility.highContrast"
    static let severitySymbolsKey = "accessibility.severitySymbols"

    // Research and content
    static let defaultSortKey = "research.defaultSort"
    static let defaultSeverityKey = "research.defaultSeverity"
    static let defaultExploitedKey = "research.defaultKnownExploited"
    static let defaultPlatformsKey = "research.defaultPlatforms"
    static let rowSummaryLinesKey = "research.rowSummaryLines"
    static let rowShowPlatformsKey = "research.rowShowPlatforms"
    static let rowShowDateKey = "research.rowShowDate"
    static let dateStyleKey = "research.dateStyle"
    static let repoWrapLinesKey = "research.repoWrapLines"
    static let repoCodeSizeKey = "research.repoCodeSize"
    static let repoShowAnalysisKey = "research.repoShowAnalysis"

    // History
    static let keepRecentKey = "history.keepRecent"
    static let recentLimitKey = "history.recentLimit"
    static let keepSearchesKey = "history.keepSearches"

    // Data and privacy
    static let confirmNoteDeletionKey = "data.confirmNoteDeletion"
    static let cellularKey = "network.allowCellular"
    static let autoRefreshKey = "network.autoRefresh"
    static let refreshHoursKey = "network.refreshHours"
    static let checkUpdatesKey = "network.checkUpdatesOnOpen"

    /// Every key Settings can change. "Reset Settings" removes exactly these.
    /// `includeUncertainKey` is included because it is a stored preference even
    /// though Discover's menu is where it is changed. `lastTabKey` is state,
    /// not a preference, and is left alone.
    static let resettableKeys: [String] = [
        includeUncertainKey,
        appearanceKey, accentKey, surfaceKey, densityKey,
        startTabKey, collapseTabBarKey, animationsKey, hapticsKey, openLinksInAppKey,
        textStepKey, boldTextKey, highContrastKey, severitySymbolsKey,
        defaultSortKey, defaultSeverityKey, defaultExploitedKey, defaultPlatformsKey,
        rowSummaryLinesKey, rowShowPlatformsKey, rowShowDateKey, dateStyleKey,
        repoWrapLinesKey, repoCodeSizeKey, repoShowAnalysisKey,
        keepRecentKey, recentLimitKey, keepSearchesKey,
        confirmNoteDeletionKey, cellularKey, autoRefreshKey, refreshHoursKey, checkUpdatesKey
    ]

    // MARK: Defaults

    enum Default {
        static let appearance = AppearanceMode.system
        static let accent = AccentChoice.blue
        static let surface = SurfaceStyle.grouped
        static let density = RowDensity.comfortable
        static let startTab = StartTab.discover
        static let collapseTabBar = false
        static let animations = true
        static let haptics = HapticLevel.standard
        static let openLinksInApp = false
        static let textStep = 0
        static let boldText = false
        static let highContrast = false
        static let severitySymbols = false
        static let defaultSort = VulnerabilitySort.published
        static let defaultSeverity = SeverityThreshold.any
        static let defaultExploited = false
        static let defaultPlatforms = ""
        static let rowSummaryLines = 2
        static let rowShowPlatforms = true
        static let rowShowDate = true
        static let dateStyle = DateStyle.absolute
        static let repoWrapLines = true
        static let repoCodeSize = CodeSize.standard
        static let repoShowAnalysis = true
        static let keepRecent = true
        static let recentLimit = 50
        static let keepSearches = true
        static let confirmNoteDeletion = true
        static let cellular = true
        static let autoRefresh = true
        static let refreshHours = 2
        static let checkUpdates = true
    }

    /// Choices offered for the number of recently viewed items kept.
    static let recentLimitChoices = [10, 25, 50]
    /// Choices offered for how old data may get before an automatic refresh.
    static let refreshHourChoices = [1, 2, 6, 12, 24]
    /// The text size adjustment range, in Dynamic Type steps.
    static let textStepRange = -3...3

    // MARK: Reading outside views

    static func bool(_ key: String, default fallback: Bool, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    static func int(_ key: String, default fallback: Int, in defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    static func choice<Value: RawRepresentable>(
        _ key: String,
        default fallback: Value,
        in defaults: UserDefaults = .standard
    ) -> Value where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:)) ?? fallback
    }

    static func hapticLevel(in defaults: UserDefaults = .standard) -> HapticLevel {
        choice(hapticsKey, default: Default.haptics, in: defaults)
    }

    static func allowsCellular(in defaults: UserDefaults = .standard) -> Bool {
        bool(cellularKey, default: Default.cellular, in: defaults)
    }

    static func opensLinksInApp(in defaults: UserDefaults = .standard) -> Bool {
        bool(openLinksInAppKey, default: Default.openLinksInApp, in: defaults)
    }

    static func autoRefreshEnabled(in defaults: UserDefaults = .standard) -> Bool {
        bool(autoRefreshKey, default: Default.autoRefresh, in: defaults)
    }

    /// How old data may get before an automatic refresh, in seconds.
    static func refreshInterval(in defaults: UserDefaults = .standard) -> TimeInterval {
        let hours = int(refreshHoursKey, default: Default.refreshHours, in: defaults)
        return TimeInterval(max(hours, 1)) * 3600
    }

    /// The tab to show at launch: the chosen one, or the one open last time.
    static func launchTab(in defaults: UserDefaults = .standard) -> AppTab {
        switch choice(startTabKey, default: Default.startTab, in: defaults) {
        case .discover: return .discover
        case .saved: return .saved
        case .info: return .info
        case .lastUsed:
            return defaults.string(forKey: lastTabKey).flatMap(AppTab.init(rawValue:)) ?? .discover
        }
    }

    /// Removes every preference so each one reads its default again.
    static func reset(in defaults: UserDefaults = .standard) {
        for key in resettableKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Choices

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, green, teal, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .green: "Green"
        case .teal: "Teal"
        case .graphite: "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }
}

/// The background behind list screens.
enum SurfaceStyle: String, CaseIterable, Identifiable, Sendable {
    /// The grouped gray the system uses for Settings-style lists.
    case grouped
    /// The plain system background, with no tinted backdrop.
    case plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grouped: "Grouped"
        case .plain: "Plain"
        }
    }
}

enum RowDensity: String, CaseIterable, Identifiable, Sendable {
    case comfortable, compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }

    /// Minimum height of a list row, in points. Nil keeps the system default.
    var minimumRowHeight: CGFloat? {
        switch self {
        case .comfortable: nil
        case .compact: 34
        }
    }
}

enum StartTab: String, CaseIterable, Identifiable, Sendable {
    case discover, saved, info, lastUsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .saved: "Saved"
        case .info: "Info"
        case .lastUsed: "Last Used"
        }
    }
}

enum HapticLevel: String, CaseIterable, Identifiable, Sendable {
    case off, subtle, standard, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .subtle: "Subtle"
        case .standard: "Standard"
        case .strong: "Strong"
        }
    }

    var isEnabled: Bool { self != .off }
}

enum DateStyle: String, CaseIterable, Identifiable, Sendable {
    case absolute, relative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .absolute: "Date"
        case .relative: "Time Ago"
        }
    }
}

enum CodeSize: String, CaseIterable, Identifiable, Sendable {
    case small, standard, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    var font: Font {
        switch self {
        case .small: .system(.caption, design: .monospaced)
        case .standard: .system(.footnote, design: .monospaced)
        case .large: .system(.callout, design: .monospaced)
        }
    }
}

/// The lowest severity Discover lists by default.
enum SeverityThreshold: String, CaseIterable, Identifiable, Sendable {
    case any, medium, high, critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .medium: "Medium and Above"
        case .high: "High and Above"
        case .critical: "Critical Only"
        }
    }

    /// The severities to show. Empty means no narrowing.
    var severities: Set<Severity> {
        switch self {
        case .any: []
        case .medium: [.medium, .high, .critical]
        case .high: [.high, .critical]
        case .critical: [.critical]
        }
    }
}

// MARK: - Default filter

/// The filter Discover starts with, built from the research preferences.
struct FilterPreferences: Equatable, Sendable {
    var sort: VulnerabilitySort
    var severity: SeverityThreshold
    var knownExploitedOnly: Bool
    var platforms: Set<ApplePlatform>

    init(sortRaw: String, severityRaw: String, knownExploitedOnly: Bool, platformsRaw: String) {
        sort = VulnerabilitySort(rawValue: sortRaw) ?? AppSettings.Default.defaultSort
        severity = SeverityThreshold(rawValue: severityRaw) ?? AppSettings.Default.defaultSeverity
        self.knownExploitedOnly = knownExploitedOnly
        platforms = Self.platforms(from: platformsRaw)
    }

    static func read(from defaults: UserDefaults = .standard) -> FilterPreferences {
        FilterPreferences(
            sortRaw: defaults.string(forKey: AppSettings.defaultSortKey) ?? AppSettings.Default.defaultSort.rawValue,
            severityRaw: defaults.string(forKey: AppSettings.defaultSeverityKey) ?? AppSettings.Default.defaultSeverity.rawValue,
            knownExploitedOnly: AppSettings.bool(AppSettings.defaultExploitedKey, default: AppSettings.Default.defaultExploited, in: defaults),
            platformsRaw: defaults.string(forKey: AppSettings.defaultPlatformsKey) ?? AppSettings.Default.defaultPlatforms
        )
    }

    var filter: VulnerabilityFilter {
        var filter = VulnerabilityFilter()
        filter.sort = sort
        filter.severities = severity.severities
        filter.knownExploitedOnly = knownExploitedOnly
        filter.platforms = platforms
        return filter
    }

    /// Platforms are stored as their names joined by commas. Unknown names are ignored.
    static func platforms(from text: String) -> Set<ApplePlatform> {
        Set(text.split(separator: ",").compactMap { ApplePlatform(rawValue: String($0)) })
    }

    static func text(from platforms: Set<ApplePlatform>) -> String {
        ApplePlatform.allCases.filter(platforms.contains).map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Text size

enum TextSize {
    /// Moves `size` by `step` Dynamic Type steps, staying within the available sizes.
    static func adjusted(_ size: DynamicTypeSize, by step: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: size) else { return size }
        let target = min(max(index + step, 0), all.count - 1)
        return all[target]
    }

    /// A short label for a step, such as "System", "+2" or "-1".
    static func label(for step: Int) -> String {
        switch step {
        case 0: "System"
        case ..<0: "\u{2212}\(-step)"
        default: "+\(step)"
        }
    }
}
