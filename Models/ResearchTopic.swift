import Foundation

enum ResearchCategory: String, CaseIterable, Identifiable, Sendable {
    case operatingSystems
    case systemArchitecture
    case securityTechnologies
    case applicationSecurity
    case processorArchitecture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .operatingSystems: "Operating Systems"
        case .systemArchitecture: "System Architecture"
        case .securityTechnologies: "Security Technologies"
        case .applicationSecurity: "Application & Browser Security"
        case .processorArchitecture: "Processor Architecture"
        }
    }

    var systemImage: String {
        switch self {
        case .operatingSystems: "desktopcomputer.and.macbook"
        case .systemArchitecture: "square.stack.3d.up"
        case .securityTechnologies: "lock.shield"
        case .applicationSecurity: "safari"
        case .processorArchitecture: "cpu"
        }
    }
}

/// A named entry in the Apple Research Center catalog.
///
/// Phase 1 ships the catalog *structure* only (names, categories and aliases).
/// Written research content is added in Phase 4; nothing here is a research claim.
struct ResearchTopic: Identifiable, Hashable, Sendable {
    /// Stable slug, for example `coretrust`.
    let id: String
    let name: String
    let category: ResearchCategory
    let aliases: [String]

    init(_ name: String, id: String? = nil, category: ResearchCategory, aliases: [String] = []) {
        self.name = name
        self.id = id ?? ResearchCatalog.slug(for: name)
        self.category = category
        self.aliases = aliases
    }
}

enum ResearchCatalog {
    static let topics: [ResearchTopic] = [
        // Operating systems
        ResearchTopic("iOS", category: .operatingSystems),
        ResearchTopic("iPadOS", category: .operatingSystems),
        ResearchTopic("macOS", category: .operatingSystems),
        ResearchTopic("watchOS", category: .operatingSystems),
        ResearchTopic("tvOS", category: .operatingSystems),
        ResearchTopic("visionOS", category: .operatingSystems),

        // System architecture
        ResearchTopic("XNU", category: .systemArchitecture, aliases: ["X is Not Unix"]),
        ResearchTopic("Mach", category: .systemArchitecture),
        ResearchTopic("BSD", category: .systemArchitecture),
        ResearchTopic("IOKit", category: .systemArchitecture, aliases: ["I/O Kit"]),
        ResearchTopic("launchd", category: .systemArchitecture),
        ResearchTopic("SpringBoard", category: .systemArchitecture),
        ResearchTopic("dyld", category: .systemArchitecture, aliases: ["dynamic linker"]),
        ResearchTopic("libSystem", category: .systemArchitecture),

        // Security technologies
        ResearchTopic("Secure Enclave", category: .securityTechnologies),
        ResearchTopic("SEP", category: .securityTechnologies, aliases: ["Secure Enclave Processor"]),
        ResearchTopic("SPTM", category: .securityTechnologies, aliases: ["Secure Page Table Monitor"]),
        ResearchTopic("PPL", category: .securityTechnologies, aliases: ["Page Protection Layer"]),
        ResearchTopic("PAC", category: .securityTechnologies, aliases: ["Pointer Authentication"]),
        ResearchTopic("AMFI", category: .securityTechnologies, aliases: ["AppleMobileFileIntegrity"]),
        ResearchTopic("CoreTrust", category: .securityTechnologies),
        ResearchTopic("Code Signing", category: .securityTechnologies),
        ResearchTopic("Sandbox", category: .securityTechnologies),
        ResearchTopic("TCC", category: .securityTechnologies, aliases: ["Transparency, Consent, and Control"]),
        ResearchTopic("Data Protection", category: .securityTechnologies),
        ResearchTopic("Boot Chain", category: .securityTechnologies),

        // Application and browser security
        ResearchTopic("WebKit", category: .applicationSecurity),
        ResearchTopic("JavaScriptCore", category: .applicationSecurity),
        ResearchTopic("App Sandbox", category: .applicationSecurity),
        ResearchTopic("Entitlements", category: .applicationSecurity),
        ResearchTopic("Launch Services", category: .applicationSecurity),

        // Processor architecture
        ResearchTopic("arm64", category: .processorArchitecture, aliases: ["AArch64"]),
        ResearchTopic("arm64e", category: .processorArchitecture)
    ]

    static func topic(withID id: String) -> ResearchTopic? {
        topics.first { $0.id == id }
    }

    static func topics(in category: ResearchCategory) -> [ResearchTopic] {
        topics.filter { $0.category == category }
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
            let keys = ([topic.name] + topic.aliases).map(normalize)
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
