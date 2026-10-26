import Foundation
import Observation

/// App-wide, locally persisted state: which launch variant to show, whether
/// the welcome step is done, and the user's favorite services.
///
/// Everything here is local, so startup never waits on the network and the
/// native shell works offline (blueprint §2, §18).
@Observable
final class AppSession {
    private enum Key {
        static let welcomeCompleted = "duova.session.welcomeCompleted"
        static let favorites = "duova.session.favorites"
    }

    let launchVariant: LaunchVariant
    private(set) var hasCompletedWelcome: Bool
    /// Favorite service IDs in the order they were added.
    private(set) var favorites: [ServiceID]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let history: LaunchHistory

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        history = LaunchHistory(defaults: defaults)
        launchVariant = history.resolveVariant(now: now)
        history.recordLaunch(now: now)

        hasCompletedWelcome = defaults.bool(forKey: Key.welcomeCompleted)
        let stored = defaults.stringArray(forKey: Key.favorites) ?? []
        favorites = stored.compactMap(ServiceID.init(rawValue:))
    }

    func completeWelcome() {
        hasCompletedWelcome = true
        defaults.set(true, forKey: Key.welcomeCompleted)
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
        defaults.set(favorites.map(\.rawValue), forKey: Key.favorites)
    }

    /// Call when the scene is no longer active so the next launch can choose
    /// the resume variant.
    func recordInactive(now: Date = .now) {
        history.recordInactive(now: now)
    }
}
