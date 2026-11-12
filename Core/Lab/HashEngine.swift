import Foundation
import CryptoKit

/// A hash function the Laboratory can compute.
enum HashAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"
    case sha384 = "SHA-384"
    case sha512 = "SHA-512"

    var id: String { rawValue }

    /// MD5 and SHA-1 are broken for security purposes. They are offered because
    /// published checksums still use them, and are labelled so.
    var isInsecure: Bool {
        self == .md5 || self == .sha1
    }
}

/// An incremental hash, so a large file can be read in pieces instead of
/// being held in memory.
struct StreamingDigest {
    private enum Storage {
        case md5(Insecure.MD5)
        case sha1(Insecure.SHA1)
        case sha256(SHA256)
        case sha384(SHA384)
        case sha512(SHA512)
    }

    private var storage: Storage

    init(_ algorithm: HashAlgorithm) {
        switch algorithm {
        case .md5: storage = .md5(Insecure.MD5())
        case .sha1: storage = .sha1(Insecure.SHA1())
        case .sha256: storage = .sha256(SHA256())
        case .sha384: storage = .sha384(SHA384())
        case .sha512: storage = .sha512(SHA512())
        }
    }

    mutating func update(_ data: Data) {
        switch storage {
        case .md5(var hasher):
            hasher.update(data: data)
            storage = .md5(hasher)
        case .sha1(var hasher):
            hasher.update(data: data)
            storage = .sha1(hasher)
        case .sha256(var hasher):
            hasher.update(data: data)
            storage = .sha256(hasher)
        case .sha384(var hasher):
            hasher.update(data: data)
            storage = .sha384(hasher)
        case .sha512(var hasher):
            hasher.update(data: data)
            storage = .sha512(hasher)
        }
    }

    /// The digest as lower-case hex.
    func finalize() -> String {
        switch storage {
        case .md5(let hasher): Self.hex(hasher.finalize())
        case .sha1(let hasher): Self.hex(hasher.finalize())
        case .sha256(let hasher): Self.hex(hasher.finalize())
        case .sha384(let hasher): Self.hex(hasher.finalize())
        case .sha512(let hasher): Self.hex(hasher.finalize())
        }
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum HashEngine {
    /// Size of each read when hashing a file.
    static let chunkSize = 1 << 20

    static func hexDigest(of data: Data, algorithm: HashAlgorithm) -> String {
        var digest = StreamingDigest(algorithm)
        digest.update(data)
        return digest.finalize()
    }

    static func hexDigest(of text: String, algorithm: HashAlgorithm) -> String {
        hexDigest(of: Data(text.utf8), algorithm: algorithm)
    }

    /// Hashes a file one chunk at a time. Throws if the file can't be read.
    static func hexDigest(ofFileAt url: URL, algorithm: HashAlgorithm) throws -> (digest: String, byteCount: Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var digest = StreamingDigest(algorithm)
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            digest.update(chunk)
            total += Int64(chunk.count)
        }
        return (digest.finalize(), total)
    }

    /// Whether two hex digests are the same, ignoring case and whitespace.
    /// Returns nil when the second is empty, so nothing is claimed.
    static func matches(_ computed: String, _ expected: String) -> Bool? {
        let cleaned = expected.lowercased().filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        return computed.lowercased() == cleaned
    }
}
