import XCTest
import UIKit
@testable import Pwned

final class AppIconTests: XCTestCase {
    private var appBundle: Bundle {
        Bundle(identifier: "by.thekammy.pwned") ?? .main
    }

    func testTheDefaultIconUsesNoAlternateName() {
        XCTAssertNil(AppIconChoice.slate.alternateName)
        XCTAssertEqual(AppIconChoice(alternateName: nil), .slate)
    }

    func testAlternateNamesRoundTrip() {
        for choice in AppIconChoice.allCases {
            XCTAssertEqual(AppIconChoice(alternateName: choice.alternateName), choice)
        }
        XCTAssertEqual(AppIconChoice(alternateName: "SomethingElse"), .slate)
    }

    func testEveryIconHasItsOwnNamesAndTitle() {
        let all = AppIconChoice.allCases
        XCTAssertEqual(Set(all.map(\.logoName)).count, all.count)
        XCTAssertEqual(Set(all.map(\.title)).count, all.count)
        XCTAssertEqual(Set(all.compactMap(\.alternateName)).count, all.count - 1)
    }

    func testInAppLogosAreInTheAssetCatalog() {
        for choice in AppIconChoice.allCases {
            let image = UIImage(named: choice.logoName, in: appBundle, compatibleWith: nil)
            XCTAssertNotNil(image, "\(choice.logoName) is missing from Assets.xcassets")
        }
    }

    /// The built Info.plist is what iOS reads, so this checks the project.yml
    /// icon settings reached the app, not just the asset catalog.
    func testBuiltAppDeclaresThePrimaryAndAlternateIcons() throws {
        let icons = try XCTUnwrap(appBundle.infoDictionary?["CFBundleIcons"] as? [String: Any], "The app declares no icons")
        XCTAssertNotNil(icons["CFBundlePrimaryIcon"], "No primary icon")

        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any], "No alternate icons declared")
        let declared = Set(alternates.keys)
        let expected = Set(AppIconChoice.allCases.compactMap(\.alternateName))
        XCTAssertEqual(declared, expected)
    }

    func testBuiltAppHasALaunchScreenSoItFillsTheScreen() {
        // A missing UILaunchScreen entry makes iOS letterbox the app in a 2:3 window.
        XCTAssertNotNil(appBundle.infoDictionary?["UILaunchScreen"], "The app has no launch screen, so it would not fill the screen")
    }

    func testTheLogoIsSquareAndLargeEnoughForTheInfoPage() throws {
        let image = try XCTUnwrap(UIImage(named: AppIconChoice.slate.logoName, in: appBundle, compatibleWith: nil))
        XCTAssertEqual(image.size.width, image.size.height)
        XCTAssertGreaterThanOrEqual(image.size.width * image.scale, 240, "Sharp at 80 pt on a 3x screen")
    }
}

final class InfoContentTests: XCTestCase {
    func testTheProjectLinksPointAtTheRepository() {
        XCTAssertEqual(AppInfo.repository.fullName, "KammyUnix/pwned")
        XCTAssertEqual(AppInfo.repositoryURL.absoluteString, "https://github.com/KammyUnix/pwned")
        XCTAssertEqual(AppInfo.issuesURL.absoluteString, "https://github.com/KammyUnix/pwned/issues")
        XCTAssertEqual(AppInfo.releasesURL.absoluteString, "https://github.com/KammyUnix/pwned/releases")
        XCTAssertEqual(AppInfo.developerURL.absoluteString, "https://github.com/KammyUnix")
    }

    func testTheNVDNoticeIsInTheLegalPageWordForWord() {
        XCTAssertEqual(InfoDocument.nvdNotice, "This product uses the NVD API but is not endorsed or certified by the NVD.")
        XCTAssertTrue(InfoDocument.legal.paragraphs.contains { $0.body == InfoDocument.nvdNotice })
    }

    func testDocumentsHaveUniqueHeadingsAndText() {
        for document in [InfoDocument.license, .privacy, .legal] {
            let headings = document.paragraphs.map(\.heading)
            XCTAssertEqual(headings.count, Set(headings).count, "\(document.title) repeats a heading")
            for paragraph in document.paragraphs {
                XCTAssertFalse(paragraph.body.isEmpty, "\(document.title): \(paragraph.heading) is empty")
            }
        }
    }

    func testThePrivacyNoteNamesTheServicesTheAppContacts() {
        let text = InfoDocument.privacy.paragraphs.map(\.body).joined(separator: " ")
        XCTAssertTrue(text.contains("services.nvd.nist.gov"))
        XCTAssertTrue(text.contains("api.github.com"))
    }

    func testThereIsNoSpecialThanksOrAcknowledgements() {
        let everything = [InfoDocument.license, .privacy, .legal]
            .flatMap(\.paragraphs)
            .map { $0.heading + " " + $0.body }
            .joined(separator: " ")
            .lowercased()
        XCTAssertFalse(everything.contains("special thanks"))
        XCTAssertFalse(everything.contains("acknowledg"))
        XCTAssertFalse(AppInfo.summary.lowercased().contains("thanks"))
    }

    func testReleaseNotesRenderAsTextOrNotAtAll() {
        XCTAssertNil(InfoView.notesText(""))
        XCTAssertNil(InfoView.notesText("  \n "))
        let rendered = InfoView.notesText("Faster **refresh**")
        XCTAssertEqual(rendered.map { String($0.characters) }, "Faster refresh")
    }
}
