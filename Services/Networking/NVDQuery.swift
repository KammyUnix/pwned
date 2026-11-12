import Foundation

/// A request to the NVD CVE API 2.0 (`/rest/json/cves/2.0`).
///
/// Only parameters documented for that endpoint are used: `cveId`,
/// `keywordSearch`, `sourceIdentifier`, `virtualMatchString`, `pubStartDate`,
/// `pubEndDate`, `resultsPerPage` and `startIndex`. NVD requires `pubStartDate`
/// and `pubEndDate` together and limits the range to 120 days; callers here
/// use windows of 30 days or less.
///
/// `sourceIdentifier` and `virtualMatchString` combined with a publication
/// window follow NVD's documentation, but this client has not been exercised
/// against live responses for those combinations. A rejected combination
/// surfaces as `NetworkError.rejected` and is reported, never ignored.
struct NVDQuery: Equatable, Sendable {
    static let endpoint = URL(string: "https://services.nvd.nist.gov/rest/json/cves/2.0")!

    var cveID: String?
    var keyword: String?
    /// Only CVEs published by this CNA or source, for example `product-security@apple.com`.
    var sourceIdentifier: String?
    /// Only CVEs whose configurations match this (possibly partial) CPE string.
    var virtualMatchString: String?
    var publishedFrom: Date?
    var publishedTo: Date?
    var resultsPerPage: Int = 500
    var startIndex: Int = 0

    static func cve(_ id: String) -> NVDQuery {
        NVDQuery(cveID: id.uppercased(), resultsPerPage: 1)
    }

    static func search(keyword text: String, startIndex: Int = 0, resultsPerPage: Int) -> NVDQuery {
        NVDQuery(keyword: text, resultsPerPage: resultsPerPage, startIndex: startIndex)
    }

    static func published(from: Date, to: Date, startIndex: Int = 0, resultsPerPage: Int) -> NVDQuery {
        NVDQuery(publishedFrom: from, publishedTo: to, resultsPerPage: resultsPerPage, startIndex: startIndex)
    }

    /// CVEs published by Apple's own CNA in a window.
    static func appleCNA(from: Date, to: Date, startIndex: Int = 0, resultsPerPage: Int) -> NVDQuery {
        NVDQuery(
            sourceIdentifier: AppleClassifier.appleCNAIdentifier,
            publishedFrom: from, publishedTo: to,
            resultsPerPage: resultsPerPage, startIndex: startIndex
        )
    }

    /// CVEs whose configurations match a CPE string, published in a window.
    static func cpeMatch(_ matchString: String, from: Date, to: Date, startIndex: Int = 0, resultsPerPage: Int) -> NVDQuery {
        NVDQuery(
            virtualMatchString: matchString,
            publishedFrom: from, publishedTo: to,
            resultsPerPage: resultsPerPage, startIndex: startIndex
        )
    }

    /// Builds the request URL with strictly percent-encoded values, so characters
    /// such as `+`, `&` or `:` in a keyword or date can never change its meaning.
    func url() throws -> URL {
        var items: [(String, String)] = []
        if let cveID { items.append(("cveId", cveID)) }
        if let keyword { items.append(("keywordSearch", keyword)) }
        if let sourceIdentifier { items.append(("sourceIdentifier", sourceIdentifier)) }
        if let virtualMatchString { items.append(("virtualMatchString", virtualMatchString)) }
        if let publishedFrom, let publishedTo {
            items.append(("pubStartDate", NVDDate.requestString(publishedFrom)))
            items.append(("pubEndDate", NVDDate.requestString(publishedTo)))
        }
        items.append(("resultsPerPage", String(resultsPerPage)))
        items.append(("startIndex", String(startIndex)))

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.percentEncodedQueryItems = items.map { name, value in
            URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        guard let url = components?.url else { throw NetworkError.invalidResponse }
        return url
    }
}
