import Foundation

/// Wire format of the NVD CVE API 2.0 response.
///
/// NVD adds fields over time (for example `affected` and `ssvcV203`), so every
/// section is decoded leniently: a malformed or unexpected section is dropped
/// instead of failing the whole page, and a malformed CVE is skipped instead of
/// discarding its neighbours. Only a CVE's `id` is required.
struct NVDResponse: Decodable, Sendable {
    let resultsPerPage: Int?
    let startIndex: Int?
    let totalResults: Int?
    let timestamp: String?
    let vulnerabilities: [Item]

    private enum CodingKeys: String, CodingKey {
        case resultsPerPage, startIndex, totalResults, timestamp, vulnerabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultsPerPage = try? container.decodeIfPresent(Int.self, forKey: .resultsPerPage)
        startIndex = try? container.decodeIfPresent(Int.self, forKey: .startIndex)
        totalResults = try? container.decodeIfPresent(Int.self, forKey: .totalResults)
        timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
        vulnerabilities = (try? container.decodeIfPresent(LossyArray<Item>.self, forKey: .vulnerabilities))?.elements ?? []
    }

    struct Item: Decodable, Sendable {
        let cve: CVE
    }

    struct CVE: Decodable, Sendable {
        let id: String
        let sourceIdentifier: String?
        let published: String?
        let lastModified: String?
        let vulnStatus: String?
        let descriptions: [LangString]
        let metrics: Metrics?
        let weaknesses: [Weakness]
        let configurations: [Configuration]
        let affected: [Affected]
        let references: [Reference]
        let cisaExploitAdd: String?
        let cisaActionDue: String?
        let cisaRequiredAction: String?
        let cisaVulnerabilityName: String?

        private enum CodingKeys: String, CodingKey {
            case id, sourceIdentifier, published, lastModified, vulnStatus, descriptions, metrics
            case weaknesses, configurations, affected, references
            case cisaExploitAdd, cisaActionDue, cisaRequiredAction, cisaVulnerabilityName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            sourceIdentifier = try? container.decodeIfPresent(String.self, forKey: .sourceIdentifier)
            published = try? container.decodeIfPresent(String.self, forKey: .published)
            lastModified = try? container.decodeIfPresent(String.self, forKey: .lastModified)
            vulnStatus = try? container.decodeIfPresent(String.self, forKey: .vulnStatus)
            descriptions = (try? container.decodeIfPresent(LossyArray<LangString>.self, forKey: .descriptions))?.elements ?? []
            metrics = try? container.decodeIfPresent(Metrics.self, forKey: .metrics)
            weaknesses = (try? container.decodeIfPresent(LossyArray<Weakness>.self, forKey: .weaknesses))?.elements ?? []
            configurations = (try? container.decodeIfPresent(LossyArray<Configuration>.self, forKey: .configurations))?.elements ?? []
            affected = (try? container.decodeIfPresent(LossyArray<Affected>.self, forKey: .affected))?.elements ?? []
            references = (try? container.decodeIfPresent(LossyArray<Reference>.self, forKey: .references))?.elements ?? []
            cisaExploitAdd = try? container.decodeIfPresent(String.self, forKey: .cisaExploitAdd)
            cisaActionDue = try? container.decodeIfPresent(String.self, forKey: .cisaActionDue)
            cisaRequiredAction = try? container.decodeIfPresent(String.self, forKey: .cisaRequiredAction)
            cisaVulnerabilityName = try? container.decodeIfPresent(String.self, forKey: .cisaVulnerabilityName)
        }
    }

    struct LangString: Decodable, Sendable {
        let lang: String?
        let value: String?
    }

    // MARK: Metrics

    struct Metrics: Decodable, Sendable {
        let cvssMetricV40: [Metric]
        let cvssMetricV31: [Metric]
        let cvssMetricV30: [Metric]
        let cvssMetricV2: [Metric]

        private enum CodingKeys: String, CodingKey {
            case cvssMetricV40, cvssMetricV31, cvssMetricV30, cvssMetricV2
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cvssMetricV40 = (try? container.decodeIfPresent(LossyArray<Metric>.self, forKey: .cvssMetricV40))?.elements ?? []
            cvssMetricV31 = (try? container.decodeIfPresent(LossyArray<Metric>.self, forKey: .cvssMetricV31))?.elements ?? []
            cvssMetricV30 = (try? container.decodeIfPresent(LossyArray<Metric>.self, forKey: .cvssMetricV30))?.elements ?? []
            cvssMetricV2 = (try? container.decodeIfPresent(LossyArray<Metric>.self, forKey: .cvssMetricV2))?.elements ?? []
        }
    }

    struct Metric: Decodable, Sendable {
        let source: String?
        let type: String?
        let cvssData: CVSSData?
        /// CVSS v2 reports its severity here rather than inside `cvssData`.
        let baseSeverity: String?
    }

    struct CVSSData: Decodable, Sendable {
        let version: String?
        let vectorString: String?
        let baseScore: Double?
        let baseSeverity: String?
    }

    // MARK: Weaknesses

    struct Weakness: Decodable, Sendable {
        let description: [LangString]?
    }

    // MARK: Configurations (analyzed CPE matches)

    struct Configuration: Decodable, Sendable {
        let nodes: [Node]?
    }

    struct Node: Decodable, Sendable {
        let cpeMatch: [CPEMatch]?
    }

    struct CPEMatch: Decodable, Sendable {
        let vulnerable: Bool?
        let criteria: String?
        let versionStartIncluding: String?
        let versionStartExcluding: String?
        let versionEndIncluding: String?
        let versionEndExcluding: String?
    }

    // MARK: Affected (CNA-reported products)

    struct Affected: Decodable, Sendable {
        let source: String?
        let affectedData: [AffectedData]?
    }

    struct AffectedData: Decodable, Sendable {
        let vendor: String?
        let product: String?
        let versions: [AffectedVersion]?
    }

    struct AffectedVersion: Decodable, Sendable {
        let version: String?
        let status: String?
        let lessThan: String?
        let lessThanOrEqual: String?
    }

    // MARK: References

    struct Reference: Decodable, Sendable {
        let url: String?
        let source: String?
        let tags: [String]?
    }
}

/// Decodes an array, silently dropping elements that fail to decode. If the
/// value is not an array at all the result is empty rather than an error.
struct LossyArray<Element: Decodable & Sendable>: Decodable, Sendable {
    let elements: [Element]

    private struct Attempt: Decodable {
        let value: Element?

        init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        if let attempts = try? [Attempt](from: decoder) {
            elements = attempts.compactMap(\.value)
        } else {
            elements = []
        }
    }
}
