import Foundation
import Observation

/// Anything that can be chosen from a fixed list of named options in a menu.
protocol MenuOption: CaseIterable, Identifiable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
}

/// A persisted setting with a fixed set of named choices.
protocol PreferenceOption: MenuOption, Codable, RawRepresentable where RawValue == String {}

extension PreferenceOption {
    var id: String { rawValue }
}

extension AppearanceMode: PreferenceOption {}
extension MotionLevel: PreferenceOption {}

enum ExpandedLayout: String, PreferenceOption {
    case adaptive, single, split

    var title: String {
        switch self {
        case .adaptive: String(localized: "Adaptive")
        case .single: String(localized: "Single pane")
        case .split: String(localized: "Two panes")
        }
    }
}

enum PanelRatio: String, PreferenceOption {
    case fiftyFifty, sixtyForty, seventyThirty

    var title: String {
        switch self {
        case .fiftyFifty: "50 : 50"
        case .sixtyForty: "60 : 40"
        case .seventyThirty: "70 : 30"
        }
    }
}

enum OpeningBehavior: String, PreferenceOption {
    case resumeLast, serviceHome

    var title: String {
        switch self {
        case .resumeLast: String(localized: "Resume last position")
        case .serviceHome: String(localized: "Start at home")
        }
    }
}

enum SwitcherSide: String, PreferenceOption {
    case right, left

    var title: String {
        switch self {
        case .right: String(localized: "Right edge")
        case .left: String(localized: "Left edge")
        }
    }
}

enum GestureStyle: String, PreferenceOption {
    case standard, handleOnly

    var title: String {
        switch self {
        case .standard: String(localized: "Swipe and handle")
        case .handleOnly: String(localized: "Handle only")
        }
    }
}

/// Duova's defaults for how services open and lay out. Individual services
/// inherit these until the user overrides a field for that service.
struct ServiceDefaults: Codable, Equatable {
    var expandedLayout: ExpandedLayout = .adaptive
    var panelRatio: PanelRatio = .sixtyForty
    var opening: OpeningBehavior = .resumeLast
    var switcherSide: SwitcherSide = .right
    var gesture: GestureStyle = .standard
}

/// A service's explicit choices. A `nil` field inherits the Duova default, so
/// changing a default later still reaches every service that hasn't opted out,
/// and resetting restores inheritance rather than a stale copy.
struct ServiceOverrides: Codable, Equatable {
    var appearance: AppearanceMode?
    var motion: MotionLevel?
    var expandedLayout: ExpandedLayout?
    var panelRatio: PanelRatio?
    var opening: OpeningBehavior?
    var switcherSide: SwitcherSide?
    var gesture: GestureStyle?

    var count: Int {
        [appearance != nil, motion != nil, expandedLayout != nil, panelRatio != nil,
         opening != nil, switcherSide != nil, gesture != nil].filter { $0 }.count
    }

    var isEmpty: Bool { count == 0 }
}

private struct StoredServicePreferences: Codable {
    var defaults: ServiceDefaults
    var overrides: [String: ServiceOverrides]
}

/// Global defaults plus per-service overrides for the signed-in account,
/// encrypted at rest. These record the user's choices; each takes effect when
/// the corresponding service workspace exists.
@Observable
final class ServicePreferences {
    var defaults = ServiceDefaults() {
        didSet { save() }
    }

    private(set) var overrides: [ServiceID: ServiceOverrides] = [:]

    @ObservationIgnored private let store: SecureStore
    @ObservationIgnored private var accountID: UUID?
    @ObservationIgnored private var isLoading = false

    init(accountID: UUID? = nil, store: SecureStore = .shared) {
        self.store = store
        activate(accountID: accountID)
    }

    func activate(accountID: UUID?) {
        self.accountID = accountID
        isLoading = true
        defer { isLoading = false }
        guard let accountID,
              let stored = store.load(StoredServicePreferences.self, name: Self.name(accountID))
        else {
            defaults = ServiceDefaults()
            overrides = [:]
            return
        }
        defaults = stored.defaults
        overrides = Dictionary(uniqueKeysWithValues: stored.overrides.compactMap { key, value in
            ServiceID(rawValue: key).map { ($0, value) }
        })
    }

    /// Replaces everything at once (used when the account's synced copy arrives).
    func replaceAll(defaults newDefaults: ServiceDefaults, overrides newOverrides: [ServiceID: ServiceOverrides]) {
        isLoading = true
        defaults = newDefaults
        overrides = newOverrides.filter { !$0.value.isEmpty }
        isLoading = false
        save()
    }

    func overrides(for id: ServiceID) -> ServiceOverrides {
        overrides[id] ?? ServiceOverrides()
    }

    func update(_ id: ServiceID, _ change: (inout ServiceOverrides) -> Void) {
        var value = overrides(for: id)
        change(&value)
        overrides[id] = value.isEmpty ? nil : value
        save()
    }

    func reset(_ id: ServiceID) {
        overrides[id] = nil
        save()
    }

    func overrideCount(for id: ServiceID) -> Int {
        overrides(for: id).count
    }

    private func save() {
        guard !isLoading, let accountID else { return }
        let stored = StoredServicePreferences(
            defaults: defaults,
            overrides: Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) }))
        try? store.save(stored, name: Self.name(accountID))
    }

    private static func name(_ id: UUID) -> String { "preferences-\(id.uuidString)" }
}
