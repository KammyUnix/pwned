import XCTest
@testable import Pwned

final class NumberConverterTests: XCTestCase {
    func testParsesEachBase() {
        XCTAssertEqual(NumberConverter.parse("0xFF", base: .hexadecimal), 255)
        XCTAssertEqual(NumberConverter.parse("ff", base: .hexadecimal), 255)
        XCTAssertEqual(NumberConverter.parse("0b101", base: .binary), 5)
        XCTAssertEqual(NumberConverter.parse("1010_1010", base: .binary), 170)
        XCTAssertEqual(NumberConverter.parse("0o17", base: .octal), 15)
        XCTAssertEqual(NumberConverter.parse("  42  ", base: .decimal), 42)
    }

    func testRejectsWhatIsNotAnUnsigned64BitNumber() {
        XCTAssertNil(NumberConverter.parse("", base: .decimal))
        XCTAssertNil(NumberConverter.parse("0x", base: .hexadecimal))
        XCTAssertNil(NumberConverter.parse("-1", base: .decimal))
        XCTAssertNil(NumberConverter.parse("+5", base: .decimal))
        XCTAssertNil(NumberConverter.parse("12g", base: .decimal))
        XCTAssertNil(NumberConverter.parse("102", base: .binary))
        XCTAssertNil(NumberConverter.parse("18446744073709551616", base: .decimal), "One above UInt64.max must not wrap")
        XCTAssertEqual(NumberConverter.parse("18446744073709551615", base: .decimal), UInt64.max)
    }

    func testFormatsWithPrefixesAndUpperCaseHex() {
        XCTAssertEqual(NumberConverter.format(255, base: .hexadecimal), "0xFF")
        XCTAssertEqual(NumberConverter.format(5, base: .binary), "0b101")
        XCTAssertEqual(NumberConverter.format(8, base: .octal), "0o10")
        XCTAssertEqual(NumberConverter.format(42, base: .decimal), "42")
    }

    func testRoundTripsThroughEveryBase() {
        for base in NumberBase.allCases {
            let text = NumberConverter.format(0xDEAD_BEEF, base: base)
            XCTAssertEqual(NumberConverter.parse(text, base: base), 0xDEAD_BEEF, "\(base.title)")
        }
    }

    func testASCIIAndBitWidth() {
        XCTAssertEqual(NumberConverter.printableASCII(65), "A")
        XCTAssertNil(NumberConverter.printableASCII(10))
        XCTAssertNil(NumberConverter.printableASCII(0x7F))
        XCTAssertNil(NumberConverter.printableASCII(300))
        XCTAssertEqual(NumberConverter.bitWidth(of: 0), 1)
        XCTAssertEqual(NumberConverter.bitWidth(of: 255), 8)
        XCTAssertEqual(NumberConverter.bitWidth(of: 256), 9)
        XCTAssertEqual(NumberConverter.bitWidth(of: .max), 64)
    }
}

final class TextConverterTests: XCTestCase {
    func testHex() {
        XCTAssertEqual(TextConverter.hex(from: "Hi"), "48 69")
        XCTAssertEqual(TextConverter.text(fromHex: "48 69"), "Hi")
        XCTAssertEqual(TextConverter.text(fromHex: "0x48,0x69"), "Hi")
        XCTAssertEqual(TextConverter.text(fromHex: "48:69"), "Hi")
        XCTAssertEqual(TextConverter.data(fromHex: "DEADBEEF"), Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testHexRejectsBadInput() {
        XCTAssertNil(TextConverter.text(fromHex: "4"))
        XCTAssertNil(TextConverter.text(fromHex: "zz"))
        XCTAssertNil(TextConverter.text(fromHex: ""))
        XCTAssertNil(TextConverter.text(fromHex: "FF"), "0xFF alone is not valid UTF-8 text")
    }

    func testBase64() {
        XCTAssertEqual(TextConverter.base64(from: "Hi"), "SGk=")
        XCTAssertEqual(TextConverter.text(fromBase64: "SGk="), "Hi")
        XCTAssertEqual(TextConverter.text(fromBase64: "SGk"), "Hi", "Missing padding is tolerated")
        XCTAssertEqual(TextConverter.text(fromBase64: "SG\nk="), "Hi", "Whitespace is ignored")
        XCTAssertNil(TextConverter.text(fromBase64: "S"))
        XCTAssertNil(TextConverter.text(fromBase64: "!!!!"))
    }

    func testBinary() {
        XCTAssertEqual(TextConverter.binary(from: "Hi"), "01001000 01101001")
        XCTAssertEqual(TextConverter.text(fromBinary: "01001000 01101001"), "Hi")
        XCTAssertEqual(TextConverter.text(fromBinary: "0100100001101001"), "Hi")
        XCTAssertNil(TextConverter.text(fromBinary: "0100100"))
        XCTAssertNil(TextConverter.text(fromBinary: "0100100a"))
    }

    func testNonASCIIUsesUTF8Bytes() {
        XCTAssertEqual(TextConverter.hex(from: "é"), "C3 A9")
        XCTAssertEqual(TextConverter.text(fromHex: "C3 A9"), "é")
    }

    func testEveryConversionRoundTrips() {
        let pairs: [(TextConversion, TextConversion)] = [
            (.textToHex, .hexToText), (.textToBase64, .base64ToText), (.textToBinary, .binaryToText)
        ]
        for (forward, back) in pairs {
            let encoded = TextConverter.convert("Pwned ✓", forward)
            XCTAssertEqual(encoded.flatMap { TextConverter.convert($0, back) }, "Pwned ✓", forward.title)
        }
    }
}

final class HashEngineTests: XCTestCase {
    // Published test vectors for the message "abc".
    private let vectors: [(HashAlgorithm, String)] = [
        (.md5, "900150983cd24fb0d6963f7d28e17f72"),
        (.sha1, "a9993e364706816aba3e25717850c26c9cd0d89d"),
        (.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (.sha384, "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"),
        (.sha512, "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    ]

    func testKnownVectors() {
        for (algorithm, expected) in vectors {
            XCTAssertEqual(HashEngine.hexDigest(of: "abc", algorithm: algorithm), expected, algorithm.rawValue)
        }
    }

    func testTheEmptyInput() {
        XCTAssertEqual(HashEngine.hexDigest(of: "", algorithm: .sha256),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testStreamingInPiecesEqualsHashingAtOnce() {
        let data = Data((0..<10_000).map { UInt8($0 % 251) })
        for algorithm in HashAlgorithm.allCases {
            var streaming = StreamingDigest(algorithm)
            for start in stride(from: 0, to: data.count, by: 777) {
                streaming.update(data[start..<min(start + 777, data.count)])
            }
            XCTAssertEqual(streaming.finalize(), HashEngine.hexDigest(of: data, algorithm: algorithm), algorithm.rawValue)
        }
    }

    func testHashingAFileReadsItInChunks() throws {
        let directory = Fixtures.temporaryDirectory(for: "hash")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("blob.bin")
        // Three and a bit chunks, so more than one read is needed.
        let data = Data((0..<(HashEngine.chunkSize * 3 + 123)).map { UInt8($0 % 253) })
        try data.write(to: url)

        let result = try HashEngine.hexDigest(ofFileAt: url, algorithm: .sha256)
        XCTAssertEqual(result.digest, HashEngine.hexDigest(of: data, algorithm: .sha256))
        XCTAssertEqual(result.byteCount, Int64(data.count))
    }

    func testAMissingFileThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertThrowsError(try HashEngine.hexDigest(ofFileAt: url, algorithm: .md5))
    }

    func testChecksumComparisonIgnoresCaseAndWhitespaceAndClaimsNothingWhenEmpty() {
        XCTAssertEqual(HashEngine.matches("abc123", " ABC123\n"), true)
        XCTAssertEqual(HashEngine.matches("abc123", "abc124"), false)
        XCTAssertNil(HashEngine.matches("abc123", "  "))
    }

    func testOnlyMD5AndSHA1AreFlaggedInsecure() {
        XCTAssertEqual(HashAlgorithm.allCases.filter(\.isInsecure), [.md5, .sha1])
    }
}

final class StructuredDataFormatterTests: XCTestCase {
    private func output(_ result: Result<StructuredDataFormatter.Output, StructuredDataFormatter.Failure>) throws -> StructuredDataFormatter.Output {
        try result.get()
    }

    func testPrettyPrintsJSONWithSortedKeys() throws {
        let result = try output(StructuredDataFormatter.format(#"{"b":1,"a":[1,2],"url":"https://x.example/a"}"#))
        XCTAssertEqual(result.format, .json)
        let a = try XCTUnwrap(result.text.range(of: "\"a\""))
        let b = try XCTUnwrap(result.text.range(of: "\"b\""))
        XCTAssertLessThan(a.lowerBound, b.lowerBound)
        XCTAssertTrue(result.text.contains("\n"))
        XCTAssertTrue(result.text.contains("https://x.example/a"), "Slashes are not escaped")
    }

    func testShowsAnXMLPropertyList() throws {
        let plist = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>k</key><string>v</string></dict></plist>"#
        let result = try output(StructuredDataFormatter.format(plist))
        XCTAssertEqual(result.format, .xmlPlist)
        XCTAssertTrue(result.text.contains("<key>k</key>"))
    }

    func testShowsABinaryPropertyListAsXML() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["k": "v"], format: .binary, options: 0)
        let result = try output(StructuredDataFormatter.format(data))
        XCTAssertEqual(result.format, .binaryPlist)
        XCTAssertTrue(result.text.contains("<key>k</key>"))
        XCTAssertTrue(result.text.contains("<string>v</string>"))
    }

    func testReportsWhatItCannotRead() {
        XCTAssertEqual(StructuredDataFormatter.format(Data()), .failure(.empty))
        XCTAssertEqual(StructuredDataFormatter.format("hello"), .failure(.unrecognized))
        XCTAssertEqual(StructuredDataFormatter.format("[1,2"), .failure(.unrecognized))
        XCTAssertEqual(StructuredDataFormatter.format("<not-a-plist/>"), .failure(.unrecognized))
    }

    func testAScalarJSONValueIsShownAsItIs() throws {
        let result = try output(StructuredDataFormatter.format("42"))
        XCTAssertEqual(result.format, .json)
        XCTAssertEqual(result.text, "42")
    }
}
