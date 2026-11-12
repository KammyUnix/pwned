import Foundation

/// The app's identity, read from the bundle at run time.
///
/// Nothing here is hardcoded: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
/// in `project.yml` flow into the generated Info.plist, and this reads them
/// back, so a change to either shows up without touching Swift code.
struct AppInfo: Equatable, Sendable {
    /// The product name. Used only when the bundle has no display name.
    static let fallbackName = "Pwned"
    /// Shown when the bundle doesn't carry a value, rather than a made-up one.
    static let unavailable = "Unavailable"

    let name: String
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        name = Self.nonEmpty(info["CFBundleDisplayName"] as? String)
            ?? Self.nonEmpty(info["CFBundleName"] as? String)
            ?? Self.fallbackName
        version = Self.nonEmpty(info["CFBundleShortVersionString"] as? String) ?? Self.unavailable
        build = Self.nonEmpty(info["CFBundleVersion"] as? String) ?? Self.unavailable
    }

    init(name: String, version: String, build: String) {
        self.name = name
        self.version = version
        self.build = build
    }

    /// For example "Version 0.3.0 (1)".
    var versionLabel: String {
        "Version \(version) (\(build))"
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
