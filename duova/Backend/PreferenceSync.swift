import Foundation
import Supabase

/// Keeps the signed-in account's preferences in step with their encrypted copy
/// in the cloud.
///
/// - After sign-in, the cloud copy wins if there is one; otherwise this device's
///   choices are uploaded.
/// - After that, every change is uploaded shortly after it's made.
/// - If the cloud copy was sealed on another device (whose keys this device
///   doesn't have), nothing is uploaded, so neither device overwrites the other.
/// - Offline, nothing is uploaded until the next successful sync.
@MainActor
final class PreferenceSync {
    private var accountID: UUID?
    private var ready = false
    private var lastSynced: PreferenceSnapshot?
    private var pushTask: Task<Void, Never>?

    /// Pulls the account's preferences after sign-in and applies them.
    func start(accountID: UUID?, current: PreferenceSnapshot, apply: (PreferenceSnapshot) -> Void) async {
        pushTask?.cancel()
        self.accountID = accountID
        ready = false
        lastSynced = nil
        guard let accountID, let client = DuovaBackend.client, client.auth.currentUser?.id == accountID,
              let store = try? PreferenceCloudStore(client: client, userID: accountID)
        else { return }

        switch try? await store.pull() {
        case .snapshot(let remote):
            guard self.accountID == accountID else { return }
            lastSynced = remote
            if remote != current { apply(remote) }
            ready = true
        case .empty:
            guard self.accountID == accountID else { return }
            if (try? await store.push(current)) != nil {
                lastSynced = current
                ready = true
            }
        case .sealedElsewhere, nil:
            break
        }
    }

    /// Call on every preference change; uploads after a short pause.
    func changed(_ snapshot: PreferenceSnapshot) {
        guard ready, snapshot != lastSynced, let accountID, let client = DuovaBackend.client else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, self.accountID == accountID,
                  let store = try? PreferenceCloudStore(client: client, userID: accountID)
            else { return }
            if (try? await store.push(snapshot)) != nil { self.lastSynced = snapshot }
        }
    }

    func stop() {
        pushTask?.cancel()
        accountID = nil
        ready = false
        lastSynced = nil
    }
}
