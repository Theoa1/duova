import Foundation
import Observation
import SwiftUI

/// Light / dark choice for the Duova interface.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// `nil` follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

enum MotionLevel: String, Codable, CaseIterable, Identifiable {
    case standard
    case reduced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .reduced: String(localized: "Reduced")
        }
    }
}

/// Display choices that apply to the whole device, including the sign-in
/// screen (which appears before any account is known). These are not account
/// data, so they live in ordinary defaults.
@Observable
final class DisplayPreferences {
    private enum Key {
        static let appearance = "duova.display.appearance"
        static let colorStyle = "duova.display.colorStyle"
        static let motion = "duova.display.motion"
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var colorStyle: DuovaColorStyle {
        didSet { defaults.set(colorStyle.rawValue, forKey: Key.colorStyle) }
    }

    var motion: MotionLevel {
        didSet { defaults.set(motion.rawValue, forKey: Key.motion) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        colorStyle = defaults.string(forKey: Key.colorStyle).flatMap(DuovaColorStyle.init(rawValue:)) ?? .duova
        motion = defaults.string(forKey: Key.motion).flatMap(MotionLevel.init(rawValue:)) ?? .standard
    }
}
