import Foundation

/// What a repository's file names say about how it is built and what it is
/// made of.
///
/// This is an inspection of *names only*. It never runs a build, reads
/// manifests or resolves dependencies, so a finding says "this file is
/// present", not "this builds". Pure and synchronous, so it is testable
/// without a network.
struct RepositoryAnalysis: Equatable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case buildSystem
        case dependencies
        case continuousIntegration
        case packaging

        var title: String {
            switch self {
            case .buildSystem: "Build Systems"
            case .dependencies: "Dependency Managers"
            case .continuousIntegration: "Continuous Integration"
            case .packaging: "Packaging"
            }
        }
    }

    struct Finding: Equatable, Hashable, Identifiable, Sendable {
        let title: String
        let category: Category
        /// Up to three paths that led to the finding.
        let evidence: [String]
        var id: String { "\(category.rawValue):\(title)" }
    }

    struct LanguageShare: Equatable, Hashable, Identifiable, Sendable {
        let name: String
        let fileCount: Int
        var id: String { name }
    }

    let findings: [Finding]
    /// Source languages by number of files with a matching extension. Not by lines of code.
    let languages: [LanguageShare]
    let fileCount: Int
    let directoryCount: Int
    /// True when the tree GitHub returned was cut short.
    let isIncomplete: Bool

    static func analyze(_ tree: GitHubTree) -> RepositoryAnalysis {
        let files = tree.entries.filter { $0.kind == .file }
        let directoryCount = tree.entries.filter { $0.kind == .directory }.count

        var evidence: [String: [String]] = [:]
        for file in files {
            for title in matchingRules(for: file.path) {
                evidence[title, default: []].append(file.path)
            }
        }

        let findings = rules.compactMap { rule -> Finding? in
            guard let paths = evidence[rule.title], !paths.isEmpty else { return nil }
            return Finding(title: rule.title, category: rule.category, evidence: Array(paths.sorted().prefix(3)))
        }

        return RepositoryAnalysis(
            findings: findings,
            languages: languageShares(for: files),
            fileCount: files.count,
            directoryCount: directoryCount,
            isIncomplete: tree.isTruncated
        )
    }

    func findings(in category: Category) -> [Finding] {
        findings.filter { $0.category == category }
    }

    // MARK: Rules

    private struct Rule {
        let title: String
        let category: Category
        let matches: @Sendable (_ path: String, _ name: String) -> Bool
    }

    private static let rules: [Rule] = [
        Rule(title: "Swift Package Manager", category: .buildSystem) { _, name in name == "Package.swift" },
        Rule(title: "Xcode project", category: .buildSystem) { path, _ in path.hasSuffix(".xcodeproj/project.pbxproj") },
        Rule(title: "Xcode workspace", category: .buildSystem) { path, _ in path.hasSuffix(".xcworkspace/contents.xcworkspacedata") },
        Rule(title: "XcodeGen or similar (project.yml)", category: .buildSystem) { _, name in name == "project.yml" },
        Rule(title: "CMake", category: .buildSystem) { _, name in name == "CMakeLists.txt" },
        Rule(title: "Make", category: .buildSystem) { _, name in name == "Makefile" || name == "GNUmakefile" },
        Rule(title: "Bazel", category: .buildSystem) { _, name in
            name == "BUILD" || name == "BUILD.bazel" || name == "WORKSPACE" || name == "MODULE.bazel"
        },
        Rule(title: "Meson", category: .buildSystem) { _, name in name == "meson.build" },
        Rule(title: "Autotools", category: .buildSystem) { _, name in name == "configure.ac" || name == "configure.in" },
        Rule(title: "Cargo (Rust)", category: .buildSystem) { _, name in name == "Cargo.toml" },
        Rule(title: "Go modules", category: .buildSystem) { _, name in name == "go.mod" },
        Rule(title: "Gradle", category: .buildSystem) { _, name in name == "build.gradle" || name == "build.gradle.kts" },
        Rule(title: "Maven", category: .buildSystem) { _, name in name == "pom.xml" },

        Rule(title: "CocoaPods", category: .dependencies) { _, name in name == "Podfile" || name.hasSuffix(".podspec") },
        Rule(title: "Carthage", category: .dependencies) { _, name in name == "Cartfile" },
        Rule(title: "npm", category: .dependencies) { _, name in name == "package.json" },
        Rule(title: "Python packaging", category: .dependencies) { _, name in
            name == "pyproject.toml" || name == "setup.py" || name == "requirements.txt"
        },
        Rule(title: "Bundler (Ruby)", category: .dependencies) { _, name in name == "Gemfile" },

        Rule(title: "GitHub Actions", category: .continuousIntegration) { path, _ in
            path.hasPrefix(".github/workflows/") && (path.hasSuffix(".yml") || path.hasSuffix(".yaml"))
        },
        Rule(title: "GitLab CI", category: .continuousIntegration) { _, name in name == ".gitlab-ci.yml" },
        Rule(title: "fastlane", category: .continuousIntegration) { _, name in name == "Fastfile" },

        Rule(title: "Docker", category: .packaging) { _, name in name == "Dockerfile" || name == "docker-compose.yml" },
        Rule(title: "App entitlements", category: .packaging) { _, name in name.hasSuffix(".entitlements") },
        Rule(title: "Info.plist", category: .packaging) { _, name in name == "Info.plist" }
    ]

    private static func matchingRules(for path: String) -> [String] {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return rules.filter { $0.matches(path, name) }.map(\.title)
    }

    // MARK: Languages

    private static let languageByExtension: [String: String] = [
        "swift": "Swift",
        "m": "Objective-C", "mm": "Objective-C++",
        "c": "C",
        "cc": "C++", "cpp": "C++", "cxx": "C++", "hpp": "C++",
        "s": "Assembly", "asm": "Assembly",
        "rs": "Rust",
        "go": "Go",
        "py": "Python",
        "js": "JavaScript", "mjs": "JavaScript",
        "ts": "TypeScript",
        "java": "Java",
        "kt": "Kotlin",
        "rb": "Ruby",
        "sh": "Shell",
        "php": "PHP",
        "cs": "C#"
    ]

    private static func languageShares(for files: [GitHubTreeEntry]) -> [LanguageShare] {
        var counts: [String: Int] = [:]
        for file in files {
            guard let dot = file.name.lastIndex(of: "."), dot != file.name.startIndex else { continue }
            let ext = String(file.name[file.name.index(after: dot)...]).lowercased()
            if let language = languageByExtension[ext] {
                counts[language, default: 0] += 1
            }
        }
        return counts
            .map { LanguageShare(name: $0.key, fileCount: $0.value) }
            .sorted { lhs, rhs in
                lhs.fileCount != rhs.fileCount ? lhs.fileCount > rhs.fileCount : lhs.name < rhs.name
            }
            .prefix(5)
            .map { $0 }
    }
}
