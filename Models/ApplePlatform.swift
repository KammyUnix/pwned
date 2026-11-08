import Foundation

enum ApplePlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case iOS
    case iPadOS
    case macOS
    case watchOS
    case tvOS
    case visionOS

    var id: String { rawValue }
    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .iOS: "iphone"
        case .iPadOS: "ipad"
        case .macOS: "laptopcomputer"
        case .watchOS: "applewatch"
        case .tvOS: "appletv"
        case .visionOS: "visionpro"
        }
    }

    /// Case-insensitive lookup from a user-typed token such as "ios" or "iPadOS".
    init?(searchToken: String) {
        let token = searchToken.lowercased()
        guard let match = ApplePlatform.allCases.first(where: { $0.rawValue.lowercased() == token }) else {
            return nil
        }
        self = match
    }
}
