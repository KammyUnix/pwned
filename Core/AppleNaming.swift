import Foundation

/// The one place that decides how Apple product, platform and technology names
/// are displayed.
///
/// Source data is never rewritten: CPE names arrive lowercase
/// (`apple` / `iphone os`), NVD descriptions use the vendor's own casing, and
/// both are stored exactly as received. Formatting happens here, at
/// presentation time, so a screen shows `iOS` while the cached record still says
/// `iphone os`.
///
/// Only names this file knows are corrected. Free text such as a CVE
/// description is deliberately never passed through it, because blindly
/// re-casing prose would turn "Cisco IOS" into "Cisco iOS".
enum AppleNaming {
    // MARK: Canonical spellings

    /// Canonical display names, keyed by `key(for:)` (lowercased letters and
    /// digits only), so `iphone os`, `iphone_os` and `iPhoneOS` all find `iOS`.
    private static let canonical: [String: String] = [
        // Operating systems. NVD's CPE product for iOS is `iphone_os`.
        "ios": "iOS",
        "iphoneos": "iOS",
        "ipados": "iPadOS",
        "macos": "macOS",
        "macosx": "Mac OS X",
        "osx": "OS X",
        "watchos": "watchOS",
        "tvos": "tvOS",
        "visionos": "visionOS",
        "xros": "visionOS",
        "audioos": "audioOS",
        "bridgeos": "bridgeOS",

        // Devices and silicon
        "iphone": "iPhone",
        "ipad": "iPad",
        "ipod": "iPod",
        "ipodtouch": "iPod touch",
        "applewatch": "Apple Watch",
        "appletv": "Apple TV",
        "visionpro": "Vision Pro",
        "homepod": "HomePod",
        "macbook": "MacBook",
        "macbookpro": "MacBook Pro",
        "macbookair": "MacBook Air",
        "imac": "iMac",
        "macmini": "Mac mini",
        "macpro": "Mac Pro",
        "macstudio": "Mac Studio",
        "airpods": "AirPods",
        "airtag": "AirTag",
        "applesilicon": "Apple Silicon",

        // Boot chain, kernel and low-level technologies
        "bootrom": "BootROM",
        "iboot": "iBoot",
        "secureboot": "Secure Boot",
        "bootchain": "Boot Chain",
        "xnu": "XNU",
        "iokit": "IOKit",
        "launchd": "launchd",
        "dyld": "dyld",
        "springboard": "SpringBoard",
        "sep": "SEP",
        "secureenclave": "Secure Enclave",
        "sptm": "SPTM",
        "ppl": "PPL",
        "pac": "PAC",
        "amfi": "AMFI",
        "coretrust": "CoreTrust",
        "tcc": "TCC",
        "arm64": "arm64",
        "arm64e": "arm64e",
        "aarch64": "AArch64",

        // Software, frameworks and services
        "webkit": "WebKit",
        "javascriptcore": "JavaScriptCore",
        "safari": "Safari",
        "xcode": "Xcode",
        "itunes": "iTunes",
        "icloud": "iCloud",
        "imessage": "iMessage",
        "facetime": "FaceTime",
        "airdrop": "AirDrop",
        "airplay": "AirPlay",
        "appstore": "App Store",
        "swiftnio": "SwiftNIO",
        "swiftui": "SwiftUI",
        "coreml": "Core ML",
        "coreaudio": "Core Audio",
        "coregraphics": "Core Graphics",
        "coremedia": "Core Media",
        "imageio": "ImageIO",
        "imagecapture": "Image Capture",
        "wificalling": "Wi-Fi Calling",
        "wifi": "Wi-Fi",
        "nfc": "NFC",
        "bluetooth": "Bluetooth",
        "sandbox": "Sandbox",
        "kernel": "Kernel",
        "mach": "Mach",
        "bsd": "BSD"
    ]

    /// Operating system names that only mean Apple's when Apple is the vendor.
    /// `ios` is also Cisco's operating system, so a product called `ios` from
    /// any other vendor is not renamed to "iOS".
    private static let appleOnlyNames: Set<String> = [
        "ios", "iphoneos", "ipados", "macos", "macosx", "osx", "watchos", "tvos", "visionos",
        "xros", "audioos", "bridgeos"
    ]

    /// Lowercase words that are acronyms in third-party CPE names.
    private static let acronyms: Set<String> = [
        "php", "gnu", "sql", "ssl", "tls", "ssh", "dns", "http", "https", "ftp", "smb",
        "xml", "json", "yaml", "api", "sdk", "cms", "vpn", "pdf", "usb", "cpu", "gpu",
        "ldap", "smtp", "imap", "pop3", "rpc", "nfs", "tcp", "udp", "ip", "os", "ui"
    ]

    /// Words kept lowercase inside a multi-word title.
    private static let smallWords: Set<String> = ["of", "for", "and", "the", "to", "in", "on"]

    // MARK: Public API

    /// The key used to look a name up: lowercased letters and digits only.
    static func key(for text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The canonical spelling of a known Apple name, or nil when the name is not
    /// one this formatter recognizes.
    static func canonicalName(for text: String) -> String? {
        canonical[key(for: text)]
    }

    /// True when `text` is one of the names above (in any casing or spacing).
    static func isKnownName(_ text: String) -> Bool {
        canonicalName(for: text) != nil
    }

    /// Display name for a CPE vendor/product pair, for example
    /// (`apple`, `iphone os`) → `iOS` and (`apache`, `airflow`) → `Apache Airflow`.
    ///
    /// Apple's own products are shown without the vendor, matching how Apple
    /// names them. Anything the formatter doesn't recognize is title-cased word
    /// by word, because CPE names are lowercase by construction.
    static func productName(vendor: String, product: String) -> String {
        let vendorIsApple = isApple(vendor)
        let productText = displayName(product, vendorIsApple: vendorIsApple)
        guard !vendorIsApple else { return productText }

        let vendorText = displayName(vendor, vendorIsApple: false)
        if productText.localizedCaseInsensitiveContains(vendorText) {
            return productText
        }
        return "\(vendorText) \(productText)"
    }

    /// Display name for a single vendor, product or component string.
    static func displayName(_ raw: String) -> String {
        displayName(raw, vendorIsApple: true)
    }

    /// - Parameter vendorIsApple: False for another company's product. Names
    ///   that are Apple's only because Apple makes them (`ios`) are then left
    ///   alone, so Cisco's `ios` is shown as "IOS", never as "iOS".
    private static func displayName(_ raw: String, vendorIsApple: Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let known = canonicalName(key(for: trimmed), vendorIsApple: vendorIsApple) {
            return known
        }

        let words = trimmed
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        var formatted: [String] = []
        for (index, word) in words.enumerated() {
            formatted.append(formatWord(word, isFirst: index == 0, vendorIsApple: vendorIsApple))
        }
        return formatted.joined(separator: " ")
    }

    /// Presents a version scope such as `before 26.7.2; from 27.0 before 27.2`
    /// with a leading capital on each clause. The version numbers and the
    /// source's wording are otherwise untouched.
    static func versionText(_ raw: String) -> String {
        raw.split(separator: ";", omittingEmptySubsequences: true)
            .map { clause -> String in
                let trimmed = clause.trimmingCharacters(in: .whitespaces)
                guard let first = trimmed.first else { return trimmed }
                return first.uppercased() + trimmed.dropFirst()
            }
            .joined(separator: "; ")
    }

    /// True for the CPE vendor string NVD uses for Apple.
    static func isApple(_ vendor: String) -> Bool {
        let vendorKey = key(for: vendor)
        return vendorKey == "apple" || vendorKey == "appleinc"
    }

    /// Platform names as they appear in running text, for building labels.
    static func platformTitle(_ platform: ApplePlatform) -> String {
        platform.title
    }

    // MARK: Private

    /// The canonical spelling for an already-keyed name, unless the name is one
    /// that only means Apple's when Apple is the vendor.
    private static func canonicalName(_ key: String, vendorIsApple: Bool) -> String? {
        if !vendorIsApple, appleOnlyNames.contains(key) { return nil }
        return canonical[key]
    }

    private static func formatWord(_ word: String, isFirst: Bool, vendorIsApple: Bool) -> String {
        if !vendorIsApple, appleOnlyNames.contains(key(for: word)) {
            // Another company's product that shares an Apple OS name: Cisco's IOS.
            return word.uppercased()
        }
        if let known = canonicalName(key(for: word), vendorIsApple: vendorIsApple) {
            return known
        }
        // Leave anything that already has capitals or digits mixed in alone
        // ("Neo4j", "OpenSSL"): it was cased by a human.
        if word.contains(where: \.isUppercase) {
            return word
        }
        if acronyms.contains(word) {
            return word.uppercased()
        }
        if !isFirst, smallWords.contains(word) {
            return word
        }
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
