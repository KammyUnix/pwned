import XCTest
import SwiftUI
@testable import Pwned

final class AppSettingsTests: XCTestCase {
    func testEveryResettableKeyIsUnique() {
        let keys = AppSettings.resettableKeys
        XCTAssertEqual(keys.count, Set(keys).count, "Two preferences share a key")
    }

    func testResetRemovesEveryPreferenceAndNothingElse() {
        let defaults = makeIsolatedDefaults()
        for key in AppSettings.resettableKeys {
            defaults.set("changed", forKey: key)
        }
        defaults.set("saved", forKey: AppSettings.lastTabKey)
        defaults.set("unrelated", forKey: "someOtherKey")

        AppSettings.reset(in: defaults)

        for key in AppSettings.resettableKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be reset")
        }
        XCTAssertEqual(defaults.string(forKey: AppSettings.lastTabKey), "saved", "The last tab is state, not a preference")
        XCTAssertEqual(defaults.string(forKey: "someOtherKey"), "unrelated")
    }

    func testReadingAnUnsetPreferenceGivesItsDefault() {
        let defaults = makeIsolatedDefaults()
        XCTAssertEqual(AppSettings.hapticLevel(in: defaults), .standard)
        XCTAssertTrue(AppSettings.allowsCellular(in: defaults))
        XCTAssertFalse(AppSettings.opensLinksInApp(in: defaults))
        XCTAssertTrue(AppSettings.autoRefreshEnabled(in: defaults))
        XCTAssertEqual(AppSettings.refreshInterval(in: defaults), 2 * 3600)
    }

    func testReadingStoredPreferences() {
        let defaults = makeIsolatedDefaults()
        defaults.set(HapticLevel.strong.rawValue, forKey: AppSettings.hapticsKey)
        defaults.set(false, forKey: AppSettings.cellularKey)
        defaults.set(true, forKey: AppSettings.openLinksInAppKey)
        defaults.set(false, forKey: AppSettings.autoRefreshKey)

        XCTAssertEqual(AppSettings.hapticLevel(in: defaults), .strong)
        XCTAssertFalse(AppSettings.allowsCellular(in: defaults))
        XCTAssertTrue(AppSettings.opensLinksInApp(in: defaults))
        XCTAssertFalse(AppSettings.autoRefreshEnabled(in: defaults))
    }

    func testAnUnknownStoredChoiceFallsBackToTheDefault() {
        let defaults = makeIsolatedDefaults()
        defaults.set("loud", forKey: AppSettings.hapticsKey)
        XCTAssertEqual(AppSettings.hapticLevel(in: defaults), .standard)
    }

    func testRefreshIntervalFollowsTheChosenHours() {
        let defaults = makeIsolatedDefaults()
        defaults.set(6, forKey: AppSettings.refreshHoursKey)
        XCTAssertEqual(AppSettings.refreshInterval(in: defaults), 6 * 3600)
        defaults.set(0, forKey: AppSettings.refreshHoursKey)
        XCTAssertEqual(AppSettings.refreshInterval(in: defaults), 3600, "Never less than an hour")
    }

    func testTheDefaultsAreOfferedAsChoices() {
        XCTAssertTrue(AppSettings.recentLimitChoices.contains(AppSettings.Default.recentLimit))
        XCTAssertTrue(AppSettings.refreshHourChoices.contains(AppSettings.Default.refreshHours))
        XCTAssertTrue(AppSettings.textStepRange.contains(AppSettings.Default.textStep))
    }

    // MARK: Start tab

    func testLaunchTabFollowsTheChosenTab() {
        let defaults = makeIsolatedDefaults()
        XCTAssertEqual(AppSettings.launchTab(in: defaults), .discover)

        defaults.set(StartTab.saved.rawValue, forKey: AppSettings.startTabKey)
        XCTAssertEqual(AppSettings.launchTab(in: defaults), .saved)

        defaults.set(StartTab.info.rawValue, forKey: AppSettings.startTabKey)
        XCTAssertEqual(AppSettings.launchTab(in: defaults), .info)
    }

    func testLastUsedReturnsToTheTabLeftOpen() {
        let defaults = makeIsolatedDefaults()
        defaults.set(StartTab.lastUsed.rawValue, forKey: AppSettings.startTabKey)
        XCTAssertEqual(AppSettings.launchTab(in: defaults), .discover, "Nothing remembered yet")

        defaults.set(AppTab.info.rawValue, forKey: AppSettings.lastTabKey)
        XCTAssertEqual(AppSettings.launchTab(in: defaults), .info)

        defaults.set("not-a-tab", forKey: AppSettings.lastTabKey)
        XCTAssertEqual(AppSettings.launchTab(in: defaults), .discover)
    }

    func testEveryStartTabNamesARealTab() {
        for choice in StartTab.allCases where choice != .lastUsed {
            XCTAssertNotNil(AppTab(rawValue: choice.rawValue), "\(choice) has no matching tab")
        }
    }

    // MARK: Automatic refresh

    func testRefreshIsDueWhenNothingWasLoadedYet() {
        let defaults = makeIsolatedDefaults()
        XCTAssertTrue(IntelligenceStore.shouldRefresh(lastRefreshed: nil, defaults: defaults))
    }

    func testRefreshWaitsForTheChosenInterval() {
        let defaults = makeIsolatedDefaults()
        let now = Date()
        defaults.set(6, forKey: AppSettings.refreshHoursKey)

        XCTAssertFalse(IntelligenceStore.shouldRefresh(lastRefreshed: now.addingTimeInterval(-5 * 3600), now: now, defaults: defaults))
        XCTAssertTrue(IntelligenceStore.shouldRefresh(lastRefreshed: now.addingTimeInterval(-6 * 3600), now: now, defaults: defaults))
    }

    func testTurningAutomaticRefreshOffStopsIt() {
        let defaults = makeIsolatedDefaults()
        defaults.set(false, forKey: AppSettings.autoRefreshKey)
        XCTAssertFalse(IntelligenceStore.shouldRefresh(lastRefreshed: nil, defaults: defaults))
        XCTAssertFalse(IntelligenceStore.shouldRefresh(lastRefreshed: .distantPast, defaults: defaults))
    }
}

final class FilterPreferencesTests: XCTestCase {
    func testWithoutPreferencesTheFilterIsTheUsualOne() {
        let defaults = makeIsolatedDefaults()
        XCTAssertEqual(FilterPreferences.read(from: defaults).filter, VulnerabilityFilter())
    }

    func testPreferencesBuildTheStartingFilter() {
        let defaults = makeIsolatedDefaults()
        defaults.set(VulnerabilitySort.severity.rawValue, forKey: AppSettings.defaultSortKey)
        defaults.set(SeverityThreshold.high.rawValue, forKey: AppSettings.defaultSeverityKey)
        defaults.set(true, forKey: AppSettings.defaultExploitedKey)
        defaults.set("ios,macos", forKey: AppSettings.defaultPlatformsKey)

        let filter = FilterPreferences.read(from: defaults).filter

        XCTAssertEqual(filter.sort, .severity)
        XCTAssertEqual(filter.severities, [.high, .critical])
        XCTAssertTrue(filter.knownExploitedOnly)
        XCTAssertEqual(filter.platforms, [.iOS, .macOS])
        XCTAssertTrue(filter.isNarrowing)
    }

    func testEachSeverityThresholdListsItsLevelAndAbove() {
        XCTAssertEqual(SeverityThreshold.any.severities, [])
        XCTAssertEqual(SeverityThreshold.medium.severities, [.medium, .high, .critical])
        XCTAssertEqual(SeverityThreshold.high.severities, [.high, .critical])
        XCTAssertEqual(SeverityThreshold.critical.severities, [.critical])
    }

    func testUnknownStoredValuesFallBackToTheDefaults() {
        let preferences = FilterPreferences(sortRaw: "nonsense", severityRaw: "nonsense", knownExploitedOnly: false, platformsRaw: "ios,toaster")
        XCTAssertEqual(preferences.sort, .published)
        XCTAssertEqual(preferences.severity, .any)
        XCTAssertEqual(preferences.platforms, [.iOS], "Unknown platform names are ignored")
    }

    func testPlatformsSurviveAStoreAndReadRoundTrip() {
        let platforms: Set<ApplePlatform> = [.macOS, .watchOS, .iOS]
        let text = FilterPreferences.text(from: platforms)
        XCTAssertEqual(FilterPreferences.platforms(from: text), platforms)
        XCTAssertEqual(FilterPreferences.text(from: platforms), text, "Stable order, so the stored text doesn't flip")
        XCTAssertEqual(FilterPreferences.platforms(from: ""), [])
    }

    func testStartingFilterActuallyNarrowsTheList() throws {
        let vulnerabilities = try NVDFixtures.decode(NVDFixtures.appleRecordJSON)
        var preferences = FilterPreferences(sortRaw: "published", severityRaw: "critical", knownExploitedOnly: false, platformsRaw: "")
        XCTAssertTrue(preferences.filter.apply(to: vulnerabilities).isEmpty, "The fixture is High, not Critical")

        preferences.severity = .high
        XCTAssertEqual(preferences.filter.apply(to: vulnerabilities).count, 1)
    }
}

final class TextSizeTests: XCTestCase {
    func testStepsMoveThroughDynamicTypeSizes() {
        XCTAssertEqual(TextSize.adjusted(.large, by: 0), .large)
        XCTAssertEqual(TextSize.adjusted(.large, by: 1), .xLarge)
        XCTAssertEqual(TextSize.adjusted(.large, by: 2), .xxLarge)
        XCTAssertEqual(TextSize.adjusted(.large, by: -1), .medium)
        XCTAssertEqual(TextSize.adjusted(.large, by: -3), .xSmall)
    }

    func testStepsStayWithinTheAvailableSizes() {
        XCTAssertEqual(TextSize.adjusted(.xSmall, by: -3), .xSmall)
        XCTAssertEqual(TextSize.adjusted(.accessibility5, by: 3), .accessibility5)
        XCTAssertEqual(TextSize.adjusted(.accessibility4, by: 3), .accessibility5)
    }

    func testEveryStepInTheRangeIsDifferentFromItsNeighbour() {
        var previous: DynamicTypeSize?
        for step in AppSettings.textStepRange {
            let size = TextSize.adjusted(.large, by: step)
            if let previous { XCTAssertNotEqual(previous, size) }
            previous = size
        }
    }

    func testLabels() {
        XCTAssertEqual(TextSize.label(for: 0), "System")
        XCTAssertEqual(TextSize.label(for: 2), "+2")
        XCTAssertEqual(TextSize.label(for: -1), "\u{2212}1")
    }
}

final class AppearanceChoiceTests: XCTestCase {
    func testThemeMapsToAColorScheme() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }

    func testChoicesHaveDistinctTitles() {
        func assertDistinct<Value: CaseIterable>(_ type: Value.Type, _ title: (Value) -> String, line: UInt = #line) {
            let titles = type.allCases.map(title)
            XCTAssertEqual(titles.count, Set(titles).count, "\(type) has duplicate titles", line: line)
        }
        assertDistinct(AppearanceMode.self, \.title)
        assertDistinct(AccentChoice.self, \.title)
        assertDistinct(SurfaceStyle.self, \.title)
        assertDistinct(RowDensity.self, \.title)
        assertDistinct(StartTab.self, \.title)
        assertDistinct(HapticLevel.self, \.title)
        assertDistinct(DateStyle.self, \.title)
        assertDistinct(CodeSize.self, \.title)
        assertDistinct(SeverityThreshold.self, \.title)
    }

    func testCompactDensityShrinksRowsAndComfortableKeepsTheSystemHeight() {
        XCTAssertNil(RowDensity.comfortable.minimumRowHeight)
        XCTAssertNotNil(RowDensity.compact.minimumRowHeight)
    }

    func testOnlyOffDisablesHaptics() {
        XCTAssertFalse(HapticLevel.off.isEnabled)
        for level in [HapticLevel.subtle, .standard, .strong] {
            XCTAssertTrue(level.isEnabled)
        }
    }

    func testSeveritiesHaveDistinctSymbols() {
        let shown: [Severity] = [.critical, .high, .medium, .low]
        let symbols = shown.map(\.symbolName)
        XCTAssertEqual(symbols.count, Set(symbols).count, "Severity must differ by shape, not only by color")
    }

    func testRelativeAndAbsoluteDatesDiffer() {
        let date = Date(timeIntervalSinceNow: -3 * 24 * 3600)
        let absolute = date.label(style: .absolute)
        let relative = date.label(style: .relative)
        XCTAssertEqual(absolute, date.shortDateLabel)
        XCTAssertNotEqual(absolute, relative)
        XCTAssertTrue(relative.contains("3"), "Relative style says how many days: \(relative)")
    }
}
