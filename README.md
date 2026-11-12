# Pwned

A native SwiftUI iOS app for security research on Apple platforms. It collects
public vulnerability data, picks out what concerns Apple software, and lets you
keep research notes that are linked to the CVEs, technologies, products and
repositories they mention.

Version and build come from `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)
and are shown in the Info tab.

## What the app has

**Three tabs.**

- **Discover** is Apple-focused. It lists vulnerabilities that Pwned has classified as
  Apple-related. Records where the evidence is weak go to a separate *Candidates* list
  instead of being counted as Apple. Broad NVD ingestion is kept separate from what
  Discover shows.
- **Saved** holds your notes, bookmarked vulnerabilities, bookmarked repositories and
  recently viewed items.
- **Info** shows the app name, version and build, Settings, and credits.

**Real data only.** Nothing is shown unless it came from a data source or you wrote it.
There is built-in *sample* data for development. It is not part of the normal app, it
is labelled as sample wherever it appears, and *Clear cache* never brings it back.
It is reachable only from a quiet entry in the Info tab.

**Apple naming.** One formatter (`Core/AppleNaming.swift`) turns raw names into
"iOS", "iPadOS", "macOS", "watchOS", "tvOS", "visionOS" and so on for display. The
raw data is never rewritten. Names that only look Apple (Cisco's "IOS") are left alone.

**Apple relevance.** `AppleClassifier` combines several signals into one of
`confirmed`, `likely`, `uncertain` or `notApple`:

| Level | Evidence |
| --- | --- |
| confirmed | A vulnerable CPE for an Apple product, or Apple as the reporting CNA |
| likely | A vendor-reported Apple product, an `support.apple.com` security release reference, a CISA KEV entry for an Apple product, or a description saying it was fixed in an Apple OS release |
| uncertain | Weak evidence only, such as an Apple component named in the description |

**Linked research notes.** Writing a CVE ID or `owner/name` repository in a note links
it automatically. Technologies and products (for example *Secure Enclave*, *TCC*,
*WebKit*) are suggested and you confirm them. You can also link and unlink by hand
(a note can link to another note). Each CVE, topic, repository and note page shows
its backlinks. Search covers note text and links. References live in a SwiftData
`NoteReference` model; resolution against current data happens at read time, so it
works offline and never creates duplicates. Unlinking an automatic link keeps it
dismissed until the text mention goes away.

## Phase status

| Phase | Scope | Status |
| --- | --- | --- |
| 1 | App foundation | Done |
| 2 | Vulnerability intelligence (NVD, cache, filtering, detail pages) | Done |
| 3 | GitHub repository explorer | **Partial.** Repository URL or `owner/name` input, API metadata, README, file tree, text file viewer, build and dependency detection from **file names only**. Not done: commits, releases, issues, code search, dependency graph. |
| 4 | Apple Research Center | **Partial.** A catalog of technologies and products with related-topic links, linked vulnerabilities and repositories, backlinks and search. Not done: written research content for the topics. The pages say so. |
| 5 | Laboratory | **Partial.** Hashing (text and files), number-base and text converters, JSON and property-list viewer. Not done: Mach-O headers, ARM64 and Mach-O references, crash, IPS and panic log viewers, file metadata. These are listed in the app as *Planned*. |
| 6 | Notebook | **Overlaps with linked notes.** Notes, backlinks and cross-references now exist. Folders, tags, export and templates do not. |

## Tests

`Tests/` is an XCTest unit-test target (`PwnedTests`). Swift Testing is not used because
it needs a macro plugin, and this project has no macro-plugin dependencies.
The `Test Pwned` workflow runs it in the iOS Simulator and is separate from `Build Pwned`.

Covered: Apple naming, the classifier and term matcher, note linking and reference
storage (in-memory SwiftData), NVD request and response mapping (with a recording
transport, no network), filtering and search, the cache and store, the GitHub client and
analysis, and the Laboratory converters, hashes and formatters.

Not covered: SwiftUI views, and anything that needs the live NVD or GitHub services.

## Data sources

- **NVD CVE API 2.0** for vulnerabilities. Apple-targeted requests use the Apple CNA
  source identifier and Apple CPE matching, in 30-day publication windows. If NVD
  rejects a request, that source is skipped and a notice is shown instead of failing the
  whole refresh.
- **GitHub REST API**, anonymous (60 requests per hour). Nothing from a repository is
  stored on the device other than your own bookmark and notes.

The vulnerability cache is a JSON file in Application Support. Your notes, links and
bookmarks live in a separate SwiftData store, so clearing the cache never touches them.

## Building

The Xcode project is generated and not committed.

```sh
brew install xcodegen
xcodegen generate
open Pwned.xcodeproj
```

CI (`.github/workflows`) uses a macOS 26 runner with Xcode 26.4.1 and produces an
unsigned IPA (`build.yml`) and runs the tests (`tests.yml`). Bundle identifier is
`by.thekammy.pwned`, Swift 6, iOS 26.3.

The app icon is a temporary placeholder in `Resources/Assets.xcassets`.
