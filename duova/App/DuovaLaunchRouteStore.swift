import Foundation
import Observation

/// Where the app is: the Duova library (before any service was launched) or a
/// launched service, which takes over the whole app.
enum DuovaRoute: Equatable {
    case initialLibrary
    case immersive(ServiceID)
}

/// The one durable fact behind the route: which service the signed-in account
/// launched on this device, if any.
///
/// Launching a service is a commitment. It's written (encrypted, per account)
/// *before* the service appears, so a crash a moment later still reopens the
/// service rather than the library. Nothing in the running app clears it:
/// there is no route from a launched service back to the library in this
/// phase. Only deleting the account, or a developer reset in a Debug build,
/// removes it.
@Observable
final class DuovaLaunchRouteStore {
    private struct Commitment: Codable {
        var schemaVersion = 1
        var serviceSlug: String
        var committedAt: Date
    }

    /// The committed service for the active account, or nil before any launch.
    private(set) var committedService: ServiceID?

    @ObservationIgnored private let store: SecureStore
    @ObservationIgnored private var accountID: UUID?

    init(accountID: UUID? = nil, store: SecureStore = .shared) {
        self.store = store
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-immersive"), let accountID {
            store.remove(name: Self.name(accountID))
        }
        #endif
        activate(accountID: accountID)
    }

    /// Loads the commitment for `accountID`; nil (signed out) means no route.
    func activate(accountID: UUID?) {
        self.accountID = accountID
        guard let accountID,
              let saved = store.load(Commitment.self, name: Self.name(accountID)),
              let service = ServiceID(rawValue: saved.serviceSlug),
              SocialAdapterRegistry.adapter(for: service) != nil
        else {
            committedService = nil
            return
        }
        committedService = service
    }

    func route(for accountID: UUID?) -> DuovaRoute {
        guard accountID != nil, accountID == self.accountID, let committedService else { return .initialLibrary }
        return .immersive(committedService)
    }

    /// Commits to `service`. Returns false (and routes nowhere) if the
    /// commitment couldn't be written, so the library never hands over to a
    /// service that wouldn't come back after a relaunch.
    @discardableResult
    func commit(_ service: ServiceID) -> Bool {
        guard let accountID, SocialAdapterRegistry.adapter(for: service) != nil else { return false }
        do {
            try store.save(Commitment(serviceSlug: service.rawValue, committedAt: .now), name: Self.name(accountID))
        } catch {
            return false
        }
        committedService = service
        return true
    }

    #if DEBUG
    /// Test builds only: forgets the launch so the library shows again. There
    /// is deliberately no production path to this.
    func resetForTesting() {
        guard let accountID else { return }
        store.remove(name: Self.name(accountID))
        committedService = nil
    }
    #endif

    private static func name(_ id: UUID) -> String { "launch-route-\(id.uuidString)" }
}
