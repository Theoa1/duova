import Foundation

/// Which launch presentation to show. Selected from local history only, so
/// choosing one never waits on a network or a third-party service.
enum LaunchVariant: String, Equatable {
    /// First install: full brand moment (1.2–1.8 s).
    case full
    /// Ordinary launch: fewer icons, faster convergence (0.5–0.9 s).
    case quick
    /// Returning moments after leaving: a minimal logo pulse, almost instant.
    case resume
}

/// Persisted launch history used to choose a `LaunchVariant`.
struct LaunchHistory {
    private enum Key {
        static let hasLaunchedBefore = "duova.launch.hasLaunchedBefore"
        static let lastActiveAt = "duova.launch.lastActiveAt"
    }

    /// If Duova was active this recently, the next launch uses the resume variant.
    static let resumeWindow: TimeInterval = 90

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func resolveVariant(now: Date = .now) -> LaunchVariant {
        guard defaults.bool(forKey: Key.hasLaunchedBefore) else { return .full }
        if let lastActive = defaults.object(forKey: Key.lastActiveAt) as? Date {
            let elapsed = now.timeIntervalSince(lastActive)
            if elapsed >= 0 && elapsed <= Self.resumeWindow { return .resume }
        }
        return .quick
    }

    func recordLaunch(now: Date = .now) {
        defaults.set(true, forKey: Key.hasLaunchedBefore)
        defaults.set(now, forKey: Key.lastActiveAt)
    }

    /// Call whenever the scene stops being active.
    func recordInactive(now: Date = .now) {
        defaults.set(now, forKey: Key.lastActiveAt)
    }
}
