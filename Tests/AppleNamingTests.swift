import XCTest
@testable import Pwned

final class AppleNamingTests: XCTestCase {
    func testOperatingSystemsUseAppleSpelling() {
        XCTAssertEqual(AppleNaming.displayName("iphone os"), "iOS")
        XCTAssertEqual(AppleNaming.displayName("iphone_os"), "iOS")
        XCTAssertEqual(AppleNaming.displayName("ipados"), "iPadOS")
        XCTAssertEqual(AppleNaming.displayName("macos"), "macOS")
        XCTAssertEqual(AppleNaming.displayName("mac os x"), "Mac OS X")
        XCTAssertEqual(AppleNaming.displayName("watchos"), "watchOS")
        XCTAssertEqual(AppleNaming.displayName("tvos"), "tvOS")
        XCTAssertEqual(AppleNaming.displayName("visionos"), "visionOS")
    }

    func testTechnologiesAndHardwareUseAppleSpelling() {
        XCTAssertEqual(AppleNaming.displayName("webkit"), "WebKit")
        XCTAssertEqual(AppleNaming.displayName("javascriptcore"), "JavaScriptCore")
        XCTAssertEqual(AppleNaming.displayName("iphone"), "iPhone")
        XCTAssertEqual(AppleNaming.displayName("ipad"), "iPad")
        XCTAssertEqual(AppleNaming.displayName("apple silicon"), "Apple Silicon")
        XCTAssertEqual(AppleNaming.displayName("bootrom"), "BootROM")
        XCTAssertEqual(AppleNaming.displayName("secure boot"), "Secure Boot")
        XCTAssertEqual(AppleNaming.displayName("xnu"), "XNU")
    }

    func testSpacingAndCaseDoNotMatter() {
        XCTAssertEqual(AppleNaming.canonicalName(for: "  WEBKIT "), "WebKit")
        XCTAssertEqual(AppleNaming.canonicalName(for: "Boot-ROM"), "BootROM")
        XCTAssertTrue(AppleNaming.isKnownName("i p h o n e"))
        XCTAssertNil(AppleNaming.canonicalName(for: "airflow"))
    }

    func testAppleProductsDropTheVendor() {
        XCTAssertEqual(AppleNaming.productName(vendor: "apple", product: "iphone_os"), "iOS")
        XCTAssertEqual(AppleNaming.productName(vendor: "apple", product: "mac_os_x"), "Mac OS X")
        XCTAssertEqual(AppleNaming.productName(vendor: "apple", product: "safari"), "Safari")
    }

    func testThirdPartyProductsAreTitleCased() {
        XCTAssertEqual(AppleNaming.productName(vendor: "apache", product: "airflow"), "Apache Airflow")
        XCTAssertEqual(AppleNaming.productName(vendor: "neo4j", product: "neo4j"), "Neo4j")
        XCTAssertEqual(AppleNaming.productName(vendor: "php", product: "php"), "PHP")
        XCTAssertEqual(AppleNaming.productName(vendor: "microsoft", product: "windows_11"), "Microsoft Windows 11")
    }

    /// Cisco's operating system is called IOS. It must never be shown as Apple's iOS.
    func testAnotherVendorsIOSIsNotRenamed() {
        XCTAssertEqual(AppleNaming.productName(vendor: "cisco", product: "ios"), "Cisco IOS")
        XCTAssertEqual(AppleNaming.productName(vendor: "apple", product: "ios"), "iOS")
    }

    func testVendorDetection() {
        XCTAssertTrue(AppleNaming.isApple("apple"))
        XCTAssertTrue(AppleNaming.isApple("Apple Inc."))
        XCTAssertFalse(AppleNaming.isApple("applesauce"))
        XCTAssertFalse(AppleNaming.isApple("cisco"))
    }

    func testVersionTextOnlyCapitalizesClauses() {
        XCTAssertEqual(
            AppleNaming.versionText("before 26.7.2; from 27.0 before 27.2"),
            "Before 26.7.2; From 27.0 before 27.2"
        )
        XCTAssertEqual(AppleNaming.versionText(""), "")
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(AppleNaming.displayName("  "), "")
    }
}
