import SwiftUI
import Observation

/// The app icons Pwned ships. The first is the default icon; the others are
/// alternate icons declared in `project.yml` and the asset catalog.
enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case slate
    case graphite
    case silver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slate: "Slate"
        case .graphite: "Graphite"
        case .silver: "Silver"
        }
    }

    /// The name passed to `setAlternateIconName`. Nil is the default icon.
    var alternateName: String? {
        switch self {
        case .slate: nil
        case .graphite: "AppIconGraphite"
        case .silver: "AppIconSilver"
        }
    }

    /// The in-app image of this icon.
    var logoName: String {
        switch self {
        case .slate: "AppLogo"
        case .graphite: "AppLogoGraphite"
        case .silver: "AppLogoSilver"
        }
    }

    init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName } ?? .slate
    }
}

/// Tracks which icon is installed and changes it.
@MainActor
@Observable
final class AppIconModel {
    private(set) var current: AppIconChoice
    private(set) var errorMessage: String?

    init() {
        current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName)
    }

    var isSupported: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    func select(_ choice: AppIconChoice) async {
        guard choice != current else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.alternateName)
            current = choice
            errorMessage = nil
            Haptics.play(.tap)
        } catch {
            errorMessage = "The icon couldn't be changed: \(error.localizedDescription)"
        }
    }
}

/// The app icon drawn at any size, with the rounded-square shape iOS gives icons.
struct AppIconView: View {
    let choice: AppIconChoice
    var size: CGFloat = 88

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Image(choice.logoName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.04)
            .accessibilityLabel("Pwned app icon, \(choice.title)")
    }
}
