import Foundation

/// Keys for the few preferences stored in `UserDefaults`.
///
/// Each preference has one key and one place in the UI that changes it, and
/// every view reads it through `@AppStorage` with that key. The NVD API key is
/// the exception on purpose: it is a credential and lives in the Keychain
/// (`NVDAPIKeyStore`), never in defaults.
enum AppSettings {
    /// Whether Discover also lists records with some Apple evidence that isn't
    /// enough to call them Apple's. Changed from Discover's filter menu.
    static let includeUncertainKey = "discover.includeUncertainMatches"
}
