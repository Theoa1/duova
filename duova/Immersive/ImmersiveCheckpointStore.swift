import Foundation

/// Where the person was in a service, remembered so the next launch can go
/// back there. Only routes and positions: never tokens, query strings,
/// messages, page content or anything the site stores about them.
struct ImmersiveCheckpoint: Codable, Equatable {
    static let currentSchema = 2

    var schemaVersion = ImmersiveCheckpoint.currentSchema
    var adapterVersion: Int
    var accountID: UUID
    var service: ServiceID
    /// Sanitized path on the site (adapter-approved), e.g. "/explore/".
    var primaryRoute: String
    /// Sanitized path shown in the companion, if one was open.
    var companionRoute: String?
    var companionKind: CompanionKind?
    var splitRatio: PanelRatio?
    var primaryScrollY: CGFloat
    var companionScrollY: CGFloat
    /// Permalink path of the content nearest the top of the primary surface.
    var anchor: String?
    var posture: SocialPosture
    var capturedAt: Date
    var primaryState: SocialPageState? = nil
    var companionState: SocialPageState? = nil
}

/// Encrypted, account-scoped storage for checkpoints, one per service.
struct ImmersiveCheckpointStore {
    var store: SecureStore = .shared

    func load(accountID: UUID, service: ServiceID) -> ImmersiveCheckpoint? {
        guard let checkpoint = store.load(ImmersiveCheckpoint.self, name: Self.name(accountID, service)),
              (1...ImmersiveCheckpoint.currentSchema).contains(checkpoint.schemaVersion),
              checkpoint.accountID == accountID, checkpoint.service == service
        else { return nil }
        return checkpoint
    }

    func save(_ checkpoint: ImmersiveCheckpoint) {
        try? store.save(checkpoint, name: Self.name(checkpoint.accountID, checkpoint.service))
    }

    func remove(accountID: UUID, service: ServiceID) {
        store.remove(name: Self.name(accountID, service))
    }

    private static func name(_ accountID: UUID, _ service: ServiceID) -> String {
        "immersive-\(accountID.uuidString)-\(service.rawValue)"
    }
}
