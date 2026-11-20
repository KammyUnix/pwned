import SwiftUI

struct InterfaceSettingsView: View {
    @AppStorage(AppSettings.startTabKey) private var startTab = AppSettings.Default.startTab
    @AppStorage(AppSettings.collapseTabBarKey) private var collapsesTabBar = AppSettings.Default.collapseTabBar
    @AppStorage(AppSettings.animationsKey) private var animations = AppSettings.Default.animations
    @AppStorage(AppSettings.hapticsKey) private var haptics = AppSettings.Default.haptics

    var body: some View {
        Form {
            Section {
                Picker("Open To", selection: $startTab) {
                    ForEach(StartTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
            } header: {
                Text("Start")
            } footer: {
                Text("The tab Pwned shows when it opens. Last Used returns to the tab you left open.")
            }

            Section {
                Toggle("Collapse Tab Bar While Scrolling", isOn: $collapsesTabBar)
            } header: {
                Text("Navigation")
            } footer: {
                Text("Shrinks the tab bar when you scroll down, to leave more room for the list.")
            }

            Section {
                Toggle("Animations", isOn: $animations)
            } header: {
                Text("Motion")
            } footer: {
                Text("Turn off to remove animation inside Pwned. The Reduce Motion setting in iOS is always respected, whatever this is set to.")
            }

            Section {
                Picker("Haptic Feedback", selection: $haptics) {
                    ForEach(HapticLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                Button("Try It") {
                    Haptics.play(.tap, level: haptics)
                }
                .disabled(!haptics.isEnabled)
            } header: {
                Text("Haptics")
            } footer: {
                Text("Played when you bookmark, add a link, delete a note, refresh, or check for updates.")
            }
        }
        .navigationTitle("Interface & Navigation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccessibilitySettingsView: View {
    @AppStorage(AppSettings.textStepKey) private var textStep = AppSettings.Default.textStep
    @AppStorage(AppSettings.boldTextKey) private var boldText = AppSettings.Default.boldText
    @AppStorage(AppSettings.highContrastKey) private var highContrast = AppSettings.Default.highContrast
    @AppStorage(AppSettings.severitySymbolsKey) private var severitySymbols = AppSettings.Default.severitySymbols

    var body: some View {
        Form {
            Section {
                Stepper(value: $textStep, in: AppSettings.textStepRange) {
                    LabeledContent("Text Size", value: TextSize.label(for: textStep))
                }
                Toggle("Bold Text", isOn: $boldText)
            } header: {
                Text("Text")
            } footer: {
                Text("Text Size moves Pwned's text up or down from the size set in iOS, one step at a time. System means no change. Bold Text is also on whenever it is on in iOS.")
            }

            Section {
                Toggle("Increase Contrast", isOn: $highContrast)
                Toggle("Severity Symbols", isOn: $severitySymbols)
            } header: {
                Text("Contrast & Color")
            } footer: {
                Text("Increase Contrast makes secondary text in vulnerability lists and the severity markers stronger. Severity Symbols show severity as a shape as well as a color. Both are also on when iOS asks for Increase Contrast or Differentiate Without Color.")
            }

            Section {
                EmptyView()
            } footer: {
                Text("Animations and haptics are under Interface & Navigation.")
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        InterfaceSettingsView()
    }
}
