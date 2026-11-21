import XCTest

/// Drives the real app in the iOS Simulator: the Info page, the update checker,
/// every Settings page, and a preference that must survive a relaunch.
///
/// Each test saves screenshots as attachments. The Test Pwned workflow exports
/// them, so the layout can be checked by eye as well as by assertion.
///
/// The launch arguments `-interface.startTab <tab>` use the same `UserDefaults`
/// key as the Start Tab setting, so they open the app on that tab without
/// writing anything to the stored preferences.
@MainActor
final class PwnedUITests: XCTestCase {
    // MARK: Helpers

    private func launch(tab: String = "info") -> XCUIApplication {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-interface.startTab", tab]
        app.launch()
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Saves the on-screen element tree, with every frame, as a text attachment.
    /// The Test Pwned workflow prints these into its log.
    private func layoutReport(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(string: "== \(name) ==\nwindow \(app.windows.firstMatch.frame)\n\(app.debugDescription)")
        attachment.name = "layout-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The first element, of any type, whose label is exactly `label`.
    private func item(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    /// The first element whose label starts with `prefix`.
    private func item(startingWith prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    /// True when the element is inside the visible part of the screen, between the
    /// navigation bar and the tab bar. Unlike `isHittable`, this never reports a
    /// failure for rows that a lazy list has not scrolled into view yet.
    private func isVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isEmpty else { return false }
        let window = app.windows.firstMatch.frame
        let navigation = app.navigationBars.firstMatch
        let top = navigation.exists ? navigation.frame.maxY : window.minY
        let tabs = app.tabBars.firstMatch
        let bottom = tabs.exists ? tabs.frame.minY : window.maxY
        return frame.midY > top + 4 && frame.midY < bottom - 4 && frame.midX > window.minX && frame.midX < window.maxX
    }

    /// Scrolls up the list until the element is visible.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) -> Bool {
        let list = app.collectionViews.firstMatch
        for _ in 0..<attempts {
            if isVisible(element, in: app) { return true }
            (list.exists ? list : app).swipeUp()
        }
        return isVisible(element, in: app)
    }

    /// Flips a switch by tapping its right-hand end, where the control is.
    /// A tap in the middle of a settings row can land on the label instead.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Info"].waitForExistence(timeout: 10))
        let settings = item(startingWith: "Settings", in: app)
        XCTAssertTrue(reveal(settings, in: app), "The Settings row is missing from Info")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open")
    }

    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openPage(_ title: String, in app: XCUIApplication) {
        let row = item(startingWith: title, in: app)
        XCTAssertTrue(reveal(row, in: app), "\(title) is missing from the Settings hub")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) did not open")
    }

    /// Opens a Settings page from the hub, saves a screenshot and returns to the hub.
    private func visitPage(_ title: String, in app: XCUIApplication, screenshot: String) {
        openPage(title, in: app)
        snapshot(screenshot)
        layoutReport(screenshot, in: app)
        goBack(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Did not return to Settings")
    }

    // MARK: Tabs

    func testThereAreExactlyThreeTabs() {
        let app = launch(tab: "discover")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        for name in ["Discover", "Saved", "Info"] {
            XCTAssertTrue(app.tabBars.buttons[name].exists, "\(name) tab is missing")
        }
    }

    func testStartTabOpensTheChosenTab() {
        for (tab, title) in [("saved", "Saved"), ("info", "Info"), ("discover", "Discover")] {
            let app = launch(tab: tab)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10),
                          "Start tab \(tab) did not open \(title)")
            app.terminate()
        }
    }

    func testDiscoverScreenshot() {
        let app = launch(tab: "discover")
        XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 10))
        // Live data may take a few seconds; the screenshot is taken either way.
        _ = app.cells.firstMatch.waitForExistence(timeout: 25)
        snapshot("discover")
    }

    func testSavedScreenshot() {
        let app = launch(tab: "saved")
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 10))
        snapshot("saved")
    }

    // MARK: Info

    func testInfoPageShowsIdentityLinksAndNoSpecialThanks() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Info"].waitForExistence(timeout: 10))

        XCTAssertTrue(item(startingWith: "Pwned app icon", in: app).waitForExistence(timeout: 5),
                      "The app icon is not shown on the Info page")
        XCTAssertTrue(item(startingWith: "Version", in: app).exists, "The version is not shown")
        XCTAssertTrue(item(startingWith: "Build", in: app).exists, "The build is not shown")
        snapshot("info-top")
        layoutReport("info-top", in: app)

        // The app fills the screen. Without a launch screen iOS letterboxes it in a
        // 2:3 window with empty bars above and below.
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(window.minY, 0, accuracy: 1, "The app is letterboxed: \(window)")
        XCTAssertGreaterThan(window.height / window.width, 1.7, "The app is not using the full screen: \(window)")

        // Layout: the icon is large, centred and in the upper part of the page; the
        // pills fit on screen; Settings is reachable without scrolling.
        let icon = item(startingWith: "Pwned app icon", in: app).frame
        XCTAssertGreaterThanOrEqual(icon.width, 100, "The icon should be prominent")
        XCTAssertEqual(icon.midX, window.midX, accuracy: 3, "The icon should be centred")
        XCTAssertLessThan(icon.minY - window.minY, window.height * 0.3, "The icon should be at the top of the page")
        for prefix in ["Version", "Build"] {
            let pill = item(startingWith: prefix, in: app).frame
            XCTAssertTrue(window.contains(pill), "The \(prefix) pill runs off the screen: \(pill)")
        }
        XCTAssertTrue(isVisible(item(startingWith: "Settings", in: app), in: app),
                      "Settings should be on screen without scrolling")

        XCTAssertTrue(reveal(item("Check for Updates", in: app), in: app), "The update checker is not on the Info page")
        snapshot("info-updates")

        XCTAssertTrue(reveal(item("Source Code on GitHub", in: app), in: app), "The repository link is missing")
        XCTAssertTrue(reveal(item("Legal Notices", in: app), in: app))
        XCTAssertTrue(item("Privacy", in: app).exists)
        XCTAssertTrue(item("License", in: app).exists)
        snapshot("info-bottom")

        let thanks = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'special thanks'"))
        XCTAssertEqual(thanks.count, 0, "The Special Thanks section should be gone")
    }

    func testLegalPagesOpen() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Info"].waitForExistence(timeout: 10))
        for title in ["License", "Privacy", "Legal Notices"] {
            let row = item(title, in: app)
            XCTAssertTrue(reveal(row, in: app), "\(title) row missing")
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) did not open")
            if title == "Legal Notices" { snapshot("legal") }
            goBack(app)
            XCTAssertTrue(app.navigationBars["Info"].waitForExistence(timeout: 5))
        }
    }

    func testUpdateCheckFinishesWithAClearResult() {
        let app = launch()
        let button = item("Check for Updates", in: app)
        XCTAssertTrue(reveal(button, in: app), "The Check for Updates button is missing")
        button.tap()

        let results = [
            "No release yet", "Pwned is up to date", "Update available",
            "Newer than the latest release", "Couldn't reach GitHub", "GitHub sent a problem"
        ]
        let deadline = Date().addingTimeInterval(30)
        var found: String?
        while Date() < deadline, found == nil {
            found = results.first { item(startingWith: $0, in: app).exists }
            if found == nil { Thread.sleep(forTimeInterval: 0.5) }
        }
        snapshot("update-result")
        XCTAssertNotNil(found, "The update check never reached a result")
        XCTAssertFalse(item(startingWith: "Checking for updates", in: app).exists, "Still checking")
        XCTAssertTrue(item("Check for Updates", in: app).isEnabled, "The button should come back after a check")
    }

    // MARK: Settings

    func testEverySettingsPageOpens() {
        let app = launch()
        openSettings(app)
        snapshot("settings-hub")
        layoutReport("settings-hub", in: app)

        visitPage("Appearance", in: app, screenshot: "settings-appearance")
        visitPage("Interface & Navigation", in: app, screenshot: "settings-interface")
        visitPage("Accessibility", in: app, screenshot: "settings-accessibility")
        visitPage("Research & Content", in: app, screenshot: "settings-research")
        visitPage("Vulnerability Data", in: app, screenshot: "settings-data-sources")
        visitPage("Data & Privacy", in: app, screenshot: "settings-data-privacy")
        visitPage("General", in: app, screenshot: "settings-general")
    }

    func testAppearancePageOffersThreeIcons() {
        let app = launch()
        openSettings(app)
        openPage("Appearance", in: app)
        for name in ["Slate icon", "Graphite icon", "Silver icon"] {
            XCTAssertTrue(reveal(item(name, in: app), in: app), "\(name) is not offered")
        }
        snapshot("settings-app-icons")
    }

    func testChangedSettingsApplyAndResetPutsThemBack() {
        let app = launch()
        openSettings(app)

        // Dark theme and an indigo accent.
        openPage("Appearance", in: app)
        let dark = app.segmentedControls.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        dark.tap()
        let indigo = item("Indigo", in: app)
        XCTAssertTrue(reveal(indigo, in: app), "The Indigo swatch is missing")
        indigo.tap()
        snapshot("custom-appearance")
        goBack(app)

        // A larger text size.
        openPage("Accessibility", in: app)
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons["Increment"].tap()
        stepper.buttons["Increment"].tap()
        snapshot("custom-text-size")
        goBack(app)

        // The hub, as customised.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snapshot("custom-settings-hub")

        // Reset from General.
        openPage("General", in: app)
        let reset = app.buttons["Reset All Settings"].firstMatch
        XCTAssertTrue(reveal(reset, in: app))
        reset.tap()
        XCTAssertTrue(item("Reset all settings?", in: app).waitForExistence(timeout: 5),
                      "No confirmation before resetting")
        snapshot("reset-confirmation")
        // The confirmation button is the last one with this name.
        app.buttons.matching(identifier: "Reset All Settings").allElementsBoundByIndex.last?.tap()

        // The theme control is back on System after a reset.
        goBack(app)
        openPage("Appearance", in: app)
        let system = app.segmentedControls.buttons["System"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        XCTAssertTrue(system.isSelected, "Reset did not restore the System theme")
        snapshot("after-reset")
    }

    func testAPreferenceSurvivesRelaunch() {
        var app = launch()
        openSettings(app)
        openPage("Accessibility", in: app)

        var toggle = app.switches["Bold Text"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let before = toggle.value as? String
        flip(toggle)
        let changed = app.switches["Bold Text"].value as? String
        XCTAssertNotEqual(before, changed, "The switch did not change")

        // Quit and open the app again.
        app.terminate()
        app = launch()
        openSettings(app)
        openPage("Accessibility", in: app)
        toggle = app.switches["Bold Text"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, changed, "The preference was lost after relaunch")
        snapshot("persisted-bold-text")
    }

    func testDangerousActionsAskFirst() {
        let app = launch()
        openSettings(app)
        openPage("Data & Privacy", in: app)

        let erase = app.buttons["Erase All My Data"].firstMatch
        XCTAssertTrue(reveal(erase, in: app), "Erase All My Data is missing")
        erase.tap()
        XCTAssertTrue(item("Erase all your data?", in: app).waitForExistence(timeout: 5),
                      "Erasing must ask for confirmation")
        snapshot("erase-confirmation")
        // Cancel: nothing is deleted.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() }
    }
}
