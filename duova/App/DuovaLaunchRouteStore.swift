import Foundation
import Observation

/// Where the app is: the Duova library (before any service was launched) or a
/// launched service, which takes over the whole app.
enum DuovaRoute: Equatable {
    case splitter
    case initialLibrary
    case immersive(ServiceID)
}

/// Encrypted, account-scoped active or parked workspace destination.
/// Older records reopen their service; parking explicitly returns to Splitter.
@Observable
final class DuovaLaunchRouteStore {
    private struct Commitment: Codable {
        var schemaVersion = 1
        var serviceSlug: String
        var committedAt: Date
        var parked: Bool? = nil
    }

    /// The committed service for the active account, or nil before any launch.
    private(set) var committedService: ServiceID?
    private(set) var isParked = false
    private(set) var savedAt: Date?

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
            isParked = false
            savedAt = nil
            return
        }
        committedService = service
        isParked = saved.parked ?? false
        savedAt = saved.committedAt
    }

    func route(for accountID: UUID?) -> DuovaRoute {
        guard accountID != nil, accountID == self.accountID, let committedService else { return .initialLibrary }
        return isParked ? .splitter : .immersive(committedService)
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
        isParked = false
        savedAt = .now
        return true
    }

    /// Park the workspace without clearing its isolated cookies or checkpoint.
    @discardableResult
    func park() -> Bool {
        guard let accountID, let committedService else { return false }
        let date = Date.now
        do {
            try store.save(Commitment(serviceSlug: committedService.rawValue, committedAt: date, parked: true),
                           name: Self.name(accountID))
        } catch { return false }
        savedAt = date
        isParked = true
        return true
    }

    #if DEBUG
    /// Test builds only: forgets the launch so the library shows again. There
    /// is deliberately no production path to this.
    func resetForTesting() {
        guard let accountID else { return }
        store.remove(name: Self.name(accountID))
        committedService = nil
        isParked = false
        savedAt = nil
    }
    #endif

    private static func name(_ id: UUID) -> String { "launch-route-\(id.uuidString)" }
}
