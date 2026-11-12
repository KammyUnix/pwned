import Foundation

enum ResearchCategory: String, CaseIterable, Identifiable, Sendable {
    case operatingSystems
    case bootAndFirmware
    case systemArchitecture
    case securityTechnologies
    case hardware
    case applicationSecurity
    case connectivity
    case processorArchitecture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .operatingSystems: "Operating Systems"
        case .bootAndFirmware: "Boot & Firmware"
        case .systemArchitecture: "System Architecture"
        case .securityTechnologies: "Security Technologies"
        case .hardware: "Hardware & Silicon"
        case .applicationSecurity: "Application & Browser Security"
        case .connectivity: "Wireless & Connectivity"
        case .processorArchitecture: "Processor Architecture"
        }
    }

    var systemImage: String {
        switch self {
        case .operatingSystems: "desktopcomputer.and.macbook"
        case .bootAndFirmware: "power"
        case .systemArchitecture: "square.stack.3d.up"
        case .securityTechnologies: "lock.shield"
        case .hardware: "memorychip"
        case .applicationSecurity: "safari"
        case .connectivity: "antenna.radiowaves.left.and.right"
        case .processorArchitecture: "cpu"
        }
    }
}

/// A named entry in the Apple Research Center catalog.
///
/// The catalog holds names, categories, aliases and the relationships between
/// topics. It makes no research claims: written content is added in Phase 4, and
/// everything a topic page shows beyond these fields is derived from the user's
/// own notes and from vulnerability records that name the topic.
struct ResearchTopic: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        /// A technology, component or concept (BootROM, WebKit, Sandbox).
        case technology
        /// An Apple operating system or product line (iOS, macOS).
        case product
    }

    /// Stable slug, for example `coretrust`.
    let id: String
    let name: String
    let category: ResearchCategory
    let aliases: [String]
    let kind: Kind
    /// IDs of topics that are related to this one. Related is not identical:
    /// BootROM relates to iBoot and Secure Boot, but they are different things.
    let related: [String]
    /// True when a mention of this term in a description is meaningful evidence
    /// of an Apple technology. Generic words such as "kernel" are not.
    let isAppleSpecific: Bool
    /// True for short or ambiguous names (SEP, PAC, TCC) that are only
    /// recognized with their exact capitalization.
    let isCaseSensitive: Bool

    init(
        _ name: String,
        id: String? = nil,
        category: ResearchCategory,
        aliases: [String] = [],
        kind: Kind = .technology,
        related: [String] = [],
        isAppleSpecific: Bool = false,
        isCaseSensitive: Bool = false
    ) {
        self.name = name
        self.id = id ?? ResearchCatalog.slug(for: name)
        self.category = category
        self.aliases = aliases
        self.kind = kind
        self.related = related
        self.isAppleSpecific = isAppleSpecific
        self.isCaseSensitive = isCaseSensitive
    }

    /// The name and every alias, as written.
    var allNames: [String] { [name] + aliases }
}

enum ResearchCatalog {
    static let topics: [ResearchTopic] = [
        // Operating systems
        ResearchTopic("iOS", category: .operatingSystems, kind: .product, related: ["ipados", "xnu"], isAppleSpecific: true),
        ResearchTopic("iPadOS", category: .operatingSystems, kind: .product, related: ["ios", "xnu"], isAppleSpecific: true),
        ResearchTopic("macOS", category: .operatingSystems, kind: .product, related: ["xnu"], isAppleSpecific: true),
        ResearchTopic("watchOS", category: .operatingSystems, kind: .product, related: ["xnu"], isAppleSpecific: true),
        ResearchTopic("tvOS", category: .operatingSystems, kind: .product, related: ["xnu"], isAppleSpecific: true),
        ResearchTopic("visionOS", category: .operatingSystems, kind: .product, related: ["xnu"], isAppleSpecific: true),

        // Boot and firmware
        ResearchTopic("BootROM", category: .bootAndFirmware, aliases: ["Boot ROM", "SecureROM"],
                      related: ["iboot", "secure-boot", "boot-chain"], isAppleSpecific: true),
        ResearchTopic("iBoot", category: .bootAndFirmware,
                      related: ["bootrom", "secure-boot", "boot-chain"], isAppleSpecific: true),
        ResearchTopic("Secure Boot", category: .bootAndFirmware,
                      related: ["bootrom", "iboot", "boot-chain"]),
        ResearchTopic("Boot Chain", category: .bootAndFirmware, aliases: ["chain of trust"],
                      related: ["bootrom", "iboot", "secure-boot"]),
        ResearchTopic("Peripheral Firmware", category: .bootAndFirmware, aliases: ["device firmware"]),

        // System architecture
        ResearchTopic("XNU", category: .systemArchitecture, aliases: ["X is Not Unix"],
                      related: ["kernel", "mach", "bsd", "iokit"], isAppleSpecific: true),
        ResearchTopic("Kernel", category: .systemArchitecture, related: ["xnu", "kernel-extensions"]),
        ResearchTopic("Kernel Extensions", category: .systemArchitecture, aliases: ["kext", "kexts"],
                      related: ["kernel", "iokit", "driverkit"]),
        ResearchTopic("DriverKit", category: .systemArchitecture,
                      related: ["iokit", "kernel-extensions"]),
        ResearchTopic("Mach", category: .systemArchitecture, related: ["xnu"], isCaseSensitive: true),
        ResearchTopic("BSD", category: .systemArchitecture, related: ["xnu"], isCaseSensitive: true),
        ResearchTopic("IOKit", category: .systemArchitecture, aliases: ["I/O Kit"],
                      related: ["xnu", "driverkit"], isAppleSpecific: true),
        ResearchTopic("launchd", category: .systemArchitecture, isAppleSpecific: true),
        ResearchTopic("SpringBoard", category: .systemArchitecture, isAppleSpecific: true),
        ResearchTopic("dyld", category: .systemArchitecture, aliases: ["dynamic linker"], isAppleSpecific: true),
        ResearchTopic("libSystem", category: .systemArchitecture, isAppleSpecific: true),
        ResearchTopic("Memory Management", category: .systemArchitecture, aliases: ["virtual memory"],
                      related: ["xnu", "security-mitigations"]),

        // Security technologies
        ResearchTopic("Secure Enclave", category: .securityTechnologies, related: ["sep"], isAppleSpecific: true),
        ResearchTopic("SEP", category: .securityTechnologies, aliases: ["Secure Enclave Processor"],
                      related: ["secure-enclave"], isAppleSpecific: true, isCaseSensitive: true),
        ResearchTopic("SPTM", category: .securityTechnologies, aliases: ["Secure Page Table Monitor"],
                      related: ["ppl", "apple-silicon"], isAppleSpecific: true, isCaseSensitive: true),
        ResearchTopic("PPL", category: .securityTechnologies, aliases: ["Page Protection Layer"],
                      related: ["sptm"], isAppleSpecific: true, isCaseSensitive: true),
        ResearchTopic("PAC", category: .securityTechnologies, aliases: ["Pointer Authentication"],
                      related: ["arm64e", "apple-silicon"], isCaseSensitive: true),
        ResearchTopic("AMFI", category: .securityTechnologies, aliases: ["AppleMobileFileIntegrity"],
                      related: ["code-signing", "coretrust", "entitlements"], isAppleSpecific: true),
        ResearchTopic("CoreTrust", category: .securityTechnologies, related: ["code-signing", "amfi"], isAppleSpecific: true),
        ResearchTopic("Code Signing", category: .securityTechnologies, related: ["coretrust", "amfi", "entitlements"]),
        ResearchTopic("Sandbox", category: .securityTechnologies, related: ["app-sandbox", "entitlements", "tcc"]),
        ResearchTopic("TCC", category: .securityTechnologies, aliases: ["Transparency, Consent, and Control"],
                      related: ["sandbox"], isAppleSpecific: true, isCaseSensitive: true),
        ResearchTopic("Data Protection", category: .securityTechnologies),
        ResearchTopic("Security Mitigations", category: .securityTechnologies, aliases: ["exploit mitigations"],
                      related: ["pac", "ppl", "sptm"]),

        // Hardware
        ResearchTopic("Apple Silicon", category: .hardware, aliases: ["A-series", "M-series"],
                      related: ["arm64e", "secure-enclave", "pac", "sptm"], isAppleSpecific: true),
        ResearchTopic("Baseband", category: .hardware, aliases: ["baseband processor", "cellular modem"]),

        // Application and browser security
        ResearchTopic("WebKit", category: .applicationSecurity, related: ["javascriptcore", "safari"], isAppleSpecific: true),
        ResearchTopic("JavaScriptCore", category: .applicationSecurity, related: ["webkit", "safari"], isAppleSpecific: true),
        ResearchTopic("Safari", category: .applicationSecurity, related: ["webkit", "javascriptcore"], isAppleSpecific: true),
        ResearchTopic("App Sandbox", category: .applicationSecurity, related: ["sandbox", "entitlements"]),
        ResearchTopic("Entitlements", category: .applicationSecurity, related: ["code-signing", "amfi", "app-sandbox"]),
        ResearchTopic("Launch Services", category: .applicationSecurity),
        ResearchTopic("Xcode", category: .applicationSecurity, aliases: ["developer tools"], isAppleSpecific: true),

        // Wireless and connectivity
        ResearchTopic("Bluetooth", category: .connectivity),
        ResearchTopic("Wi-Fi", category: .connectivity, aliases: ["WiFi", "802.11"]),
        ResearchTopic("NFC", category: .connectivity, isCaseSensitive: true),
        ResearchTopic("AirDrop", category: .connectivity, isAppleSpecific: true),
        ResearchTopic("Networking", category: .connectivity),

        // Processor architecture
        ResearchTopic("arm64", category: .processorArchitecture, aliases: ["AArch64"], related: ["arm64e"]),
        ResearchTopic("arm64e", category: .processorArchitecture, related: ["arm64", "pac"], isAppleSpecific: true)
    ]

    private static let topicsByID: [String: ResearchTopic] = Dictionary(
        topics.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func topic(withID id: String) -> ResearchTopic? {
        topicsByID[id]
    }

    static func topics(in category: ResearchCategory) -> [ResearchTopic] {
        topics.filter { $0.category == category }
    }

    /// Topics related to `topic`, resolved from its `related` IDs. These are
    /// related concepts, not duplicates, and are labelled that way in the UI.
    static func relatedTopics(of topic: ResearchTopic) -> [ResearchTopic] {
        topic.related.compactMap { topicsByID[$0] }
    }

    /// Ranks topics for a query: exact name/alias matches, then prefix matches,
    /// then (for queries of three or more characters) substring matches.
    static func topics(matching query: String) -> [ResearchTopic] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }

        var exact: [ResearchTopic] = []
        var prefix: [ResearchTopic] = []
        var substring: [ResearchTopic] = []

        for topic in topics {
            let keys = topic.allNames.map(normalize)
            if keys.contains(needle) {
                exact.append(topic)
            } else if keys.contains(where: { $0.hasPrefix(needle) }) {
                prefix.append(topic)
            } else if needle.count >= 3, keys.contains(where: { $0.contains(needle) }) {
                substring.append(topic)
            }
        }
        return exact + prefix + substring
    }

    static func slug(for name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
