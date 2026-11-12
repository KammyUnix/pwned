import XCTest
@testable import Pwned

final class RepositoryAnalysisTests: XCTestCase {
    private func tree(_ paths: [String], truncated: Bool = false) -> GitHubTree {
        let entries = paths.map { path -> GitHubTreeEntry in
            // A trailing slash marks a directory in these fixtures.
            if path.hasSuffix("/") {
                return GitHubTreeEntry(path: String(path.dropLast()), kind: .directory, size: nil)
            }
            return GitHubTreeEntry(path: path, kind: .file, size: 10)
        }
        return GitHubTree(entries: entries, isTruncated: truncated)
    }

    func testFindsBuildSystemsDependencyManagersAndCI() {
        let analysis = RepositoryAnalysis.analyze(tree([
            "Package.swift", "Sources/", "Sources/App/main.swift", "Sources/App/util.swift", "Tests/AppTests.swift",
            ".github/workflows/ci.yml", "Dockerfile", "Pwned.xcodeproj/project.pbxproj", "Podfile", "docs/readme.md"
        ]))

        let titles = Set(analysis.findings.map(\.title))
        XCTAssertTrue(titles.isSuperset(of: ["Swift Package Manager", "Xcode project", "CocoaPods", "GitHub Actions", "Docker"]))
        XCTAssertFalse(titles.contains("Cargo (Rust)"))
        XCTAssertEqual(analysis.findings(in: .continuousIntegration).map(\.title), ["GitHub Actions"])
        XCTAssertEqual(analysis.findings(in: .continuousIntegration).first?.evidence, [".github/workflows/ci.yml"])
    }

    func testCountsFilesFoldersAndLanguages() {
        let analysis = RepositoryAnalysis.analyze(tree(["Sources/", "Sources/a.swift", "Sources/b.swift", "c.m", "d.py", "README.md"]))
        XCTAssertEqual(analysis.fileCount, 5)
        XCTAssertEqual(analysis.directoryCount, 1)
        XCTAssertEqual(analysis.languages.first, RepositoryAnalysis.LanguageShare(name: "Swift", fileCount: 2))
        XCTAssertEqual(Set(analysis.languages.map(\.name)), ["Swift", "Objective-C", "Python"])
    }

    func testEvidenceIsLimitedToThreePaths() {
        let analysis = RepositoryAnalysis.analyze(tree((1...6).map { "module\($0)/Makefile" }))
        XCTAssertEqual(analysis.findings.first { $0.title == "Make" }?.evidence.count, 3)
    }

    func testAnIncompleteTreeIsFlagged() {
        XCTAssertTrue(RepositoryAnalysis.analyze(tree(["a.c"], truncated: true)).isIncomplete)
        XCTAssertFalse(RepositoryAnalysis.analyze(tree(["a.c"])).isIncomplete)
    }

    func testSubmodulesAndFoldersAreNotCountedAsFiles() {
        let entries = [
            GitHubTreeEntry(path: "vendor/lib", kind: .submodule, size: nil),
            GitHubTreeEntry(path: "src", kind: .directory, size: nil),
            GitHubTreeEntry(path: "src/main.rs", kind: .file, size: 1)
        ]
        let analysis = RepositoryAnalysis.analyze(GitHubTree(entries: entries, isTruncated: false))
        XCTAssertEqual(analysis.fileCount, 1)
    }
}

final class GitHubTreeTests: XCTestCase {
    func testChildrenListFoldersFirstThenFilesByName() {
        let tree = GitHubTree(entries: [
            GitHubTreeEntry(path: "z.md", kind: .file, size: 1),
            GitHubTreeEntry(path: "dir", kind: .directory, size: nil),
            GitHubTreeEntry(path: "a.txt", kind: .file, size: 1),
            GitHubTreeEntry(path: "dir/b.txt", kind: .file, size: 1),
            GitHubTreeEntry(path: "dir/sub", kind: .directory, size: nil)
        ], isTruncated: false)

        XCTAssertEqual(tree.children(of: "").map(\.name), ["dir", "a.txt", "z.md"])
        XCTAssertEqual(tree.children(of: "dir").map(\.name), ["sub", "b.txt"])
        XCTAssertTrue(tree.children(of: "missing").isEmpty)
    }

    func testEntryNamesAndParents() {
        let entry = GitHubTreeEntry(path: "Sources/App/main.swift", kind: .file, size: 1)
        XCTAssertEqual(entry.name, "main.swift")
        XCTAssertEqual(entry.parentPath, "Sources/App")
        XCTAssertEqual(GitHubTreeEntry(path: "README.md", kind: .file, size: 1).parentPath, "")
    }
}

/// The client is tested against canned responses. The response shapes match what
/// the live API returned when they were checked; the values are invented.
final class GitHubClientTests: XCTestCase {
    private let reference = GitHubRepositoryReference(owner: "apple", name: "swift-nio")

    private func client(_ transport: RecordingTransport) -> GitHubClient {
        GitHubClient(transport: transport)
    }

    func testReadsRepositoryMetadata() async throws {
        let body = """
        {"full_name":"apple/swift-nio","description":"Event-driven network application framework",
         "html_url":"https://github.com/apple/swift-nio","homepage":"","language":"Swift",
         "stargazers_count":8000,"forks_count":650,"open_issues_count":120,"default_branch":"main",
         "license":{"spdx_id":"Apache-2.0","name":"Apache License 2.0"},"topics":["swift","networking"],
         "archived":false,"fork":false,"size":1234,
         "created_at":"2018-02-14T05:11:00Z","pushed_at":"2026-11-01T12:00:00Z"}
        """
        let transport = RecordingTransport(body: body)
        let details = try await client(transport).repository(reference)

        XCTAssertEqual(details.fullName, "apple/swift-nio")
        XCTAssertEqual(details.stars, 8000)
        XCTAssertEqual(details.forks, 650)
        XCTAssertEqual(details.openIssues, 120)
        XCTAssertEqual(details.defaultBranch, "main")
        XCTAssertEqual(details.license, "Apache-2.0")
        XCTAssertEqual(details.topics, ["swift", "networking"])
        XCTAssertNil(details.homepage, "An empty homepage is no homepage")
        XCTAssertEqual(details.pushedAt, NVDDate.parse("2026-11-01T12:00:00"))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/apple/swift-nio")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Requests are anonymous")
    }

    func testAnUnassertedLicenseFallsBackToItsName() async throws {
        let body = #"{"full_name":"a/b","license":{"spdx_id":"NOASSERTION","name":"Other"}}"#
        let details = try await client(RecordingTransport(body: body)).repository(reference)
        XCTAssertEqual(details.license, "Other")
        XCTAssertEqual(details.stars, 0)
        XCTAssertEqual(details.defaultBranch, "HEAD")
    }

    func testReadsTheREADMEAsRawText() async throws {
        let transport = RecordingTransport(body: "# Title\nBody")
        let text = try await client(transport).readme(reference)
        XCTAssertEqual(text, "# Title\nBody")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Accept"), "application/vnd.github.raw+json")
        XCTAssertEqual(transport.requests.first?.url?.path, "/repos/apple/swift-nio/readme")
    }

    func testARepositoryWithoutAREADMEReturnsNil() async throws {
        let text = try await client(RecordingTransport(status: 404)).readme(reference)
        XCTAssertNil(text)
    }

    func testReadsTheFileTreeAndSkipsUnknownEntryTypes() async throws {
        let body = """
        {"sha":"abc","tree":[
          {"path":"README.md","type":"blob","size":10},
          {"path":"Sources","type":"tree"},
          {"path":"vendor/lib","type":"commit"},
          {"path":"odd","type":"weird"}],"truncated":true}
        """
        let transport = RecordingTransport(body: body)
        let tree = try await client(transport).tree(reference)

        XCTAssertEqual(tree.entries.map(\.path), ["README.md", "Sources", "vendor/lib"])
        XCTAssertEqual(tree.entries.map(\.kind), [.file, .directory, .submodule])
        XCTAssertEqual(tree.entries.first?.size, 10)
        XCTAssertTrue(tree.isTruncated)

        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.path, "/repos/apple/swift-nio/git/trees/HEAD")
        XCTAssertEqual(url.query, "recursive=1")
    }

    func testReadsAFileAsText() async throws {
        let transport = RecordingTransport(body: "let x = 1\n")
        let file = try await client(transport).file(reference, path: "Sources/My File.swift", size: 10)
        XCTAssertEqual(file.text, "let x = 1\n")
        XCTAssertEqual(file.byteCount, 10)
        XCTAssertEqual(transport.requests.first?.url?.absoluteString,
                       "https://api.github.com/repos/apple/swift-nio/contents/Sources/My%20File.swift")
    }

    func testBinaryFilesYieldNoText() async throws {
        let transport = RecordingTransport { _ in HTTPResult(data: Data([0x89, 0x50, 0x00, 0x47]), statusCode: 200, retryAfter: nil) }
        let file = try await client(transport).file(reference, path: "logo.png", size: 4)
        XCTAssertNil(file.text)
        XCTAssertEqual(file.byteCount, 4)
    }

    func testOversizedFilesAreRefusedWithoutDownloading() async {
        let transport = RecordingTransport(body: "x")
        do {
            _ = try await client(transport).file(reference, path: "big.bin", size: GitHubClient.maxFileBytes + 1)
            XCTFail("Expected tooLarge")
        } catch {
            XCTAssertEqual(error as? GitHubError, .tooLarge(byteCount: GitHubClient.maxFileBytes + 1))
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLongTextIsCutOnACharacterBoundary() async throws {
        let text = String(repeating: "é", count: GitHubClient.maxDisplayBytes) // two bytes each
        let transport = RecordingTransport { _ in HTTPResult(data: Data(text.utf8), statusCode: 200, retryAfter: nil) }
        let file = try await client(transport).file(reference, path: "long.txt", size: nil)
        let shown = try XCTUnwrap(file.text)
        XCTAssertLessThanOrEqual(shown.utf8.count, GitHubClient.maxDisplayBytes)
        XCTAssertTrue(shown.allSatisfy { $0 == "é" })
    }

    // MARK: Failures

    func testMapsHTTPStatusesToErrors() async {
        let cases: [(Int, GitHubError)] = [
            (404, .notFound),
            (409, .emptyRepository),
            (403, .rateLimited(retryAfter: nil)),
            (429, .rateLimited(retryAfter: nil)),
            (502, .server(status: 502)),
            (418, .rejected(status: 418))
        ]
        for (status, expected) in cases {
            do {
                _ = try await client(RecordingTransport(status: status)).repository(reference)
                XCTFail("Expected an error for HTTP \(status)")
            } catch {
                XCTAssertEqual(error as? GitHubError, expected, "HTTP \(status)")
            }
        }
    }

    func testAMalformedBodyIsAnInvalidResponse() async {
        do {
            _ = try await client(RecordingTransport(body: "not json")).repository(reference)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .invalidResponse)
        }
    }

    func testOfflineIsReportedAsOffline() async {
        let transport = RecordingTransport { _ in throw NetworkError.offline }
        do {
            _ = try await client(transport).tree(reference)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .offline)
        }
    }

    func testErrorMessagesAreSpecificAndRetryabilityIsCorrect() {
        XCTAssertTrue(GitHubError.rateLimited(retryAfter: 30).errorDescription?.contains("30") == true)
        XCTAssertTrue(GitHubError.rateLimited(retryAfter: nil).errorDescription?.contains("60 per hour") == true)
        XCTAssertTrue(GitHubError.offline.isRetryable)
        XCTAssertFalse(GitHubError.notFound.isRetryable)
        XCTAssertFalse(GitHubError.emptyRepository.isRetryable)
        XCTAssertFalse(GitHubError.tooLarge(byteCount: 1).isRetryable)
    }
}
