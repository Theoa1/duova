import Foundation
import Observation

/// App-wide, locally persisted state: which launch variant to show and the
/// signed-in account's favorite services.
///
/// Favorites belong to an account and are stored encrypted (`SecureStore`), so a
/// second account on the same device never sees them. Launch history is not
/// account data and stays in plain defaults.
///
/// Everything here is local, so startup never waits on the network and the
/// native shell works offline (blueprint §2, §18).
@Observable
final class AppSession {
    let launchVariant: LaunchVariant
    /// Favorite service IDs in the order they were added.
    private(set) var favorites: [ServiceID] = []

    @ObservationIgnored private let store: SecureStore
    @ObservationIgnored private let history: LaunchHistory
    @ObservationIgnored private var accountID: UUID?

    init(accountID: UUID? = nil, store: SecureStore = .shared,
         defaults: UserDefaults = .standard, now: Date = .now) {
        self.store = store
        history = LaunchHistory(defaults: defaults)
        launchVariant = history.resolveVariant(now: now)
        history.recordLaunch(now: now)
        activate(accountID: accountID)
    }

    /// Loads the favorites for `accountID` (or clears them when signed out).
    func activate(accountID: UUID?) {
        self.accountID = accountID
        guard let accountID else {
            favorites = []
            return
        }
        let stored = store.load([String].self, name: Self.favoritesName(accountID)) ?? []
        favorites = stored.compactMap(ServiceID.init(rawValue:))
    }

    func isFavorite(_ id: ServiceID) -> Bool {
        favorites.contains(id)
    }

    func toggleFavorite(_ id: ServiceID) {
        if let index = favorites.firstIndex(of: id) {
            favorites.remove(at: index)
        } else {
            favorites.append(id)
        }
        guard let accountID else { return }
        try? store.save(favorites.map(\.rawValue), name: Self.favoritesName(accountID))
    }

    /// Call whenever the scene stops being active so the next launch can choose
    /// the resume variant.
    func recordInactive(now: Date = .now) {
        history.recordInactive(now: now)
    }

    private static func favoritesName(_ id: UUID) -> String { "favorites-\(id.uuidString)" }
}
