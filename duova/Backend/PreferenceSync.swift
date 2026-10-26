import Foundation
import Supabase

/// Keeps the signed-in account's preferences in step with their encrypted copy
/// in the cloud.
///
/// - After sign-in, the cloud copy wins if there is one; otherwise this device's
///   choices are uploaded.
/// - After that, every change is uploaded shortly after it's made, on top of
///   the revision this device last read. If another device saved in between,
///   nothing is overwritten: both devices' changes are merged setting by
///   setting (each device's own changes win for what it changed) and saved again.
/// - If the cloud copy was sealed on another device (whose keys this device
///   doesn't have), nothing is uploaded, so neither device overwrites the other.
/// - Offline, nothing is uploaded until the next successful sync.
@MainActor
final class PreferenceSync {
    private var accountID: UUID?
    private var ready = false
    /// What this device and the cloud last agreed on: the base for merging.
    private var lastSynced: PreferenceSnapshot?
    /// The cloud revision `lastSynced` came from.
    private var revision: Int64 = 0
    private var apply: ((PreferenceSnapshot) -> Void)?
    private var pushTask: Task<Void, Never>?

    private static let maxConflictRetries = 3

    /// Pulls the account's preferences after sign-in and applies them.
    func start(accountID: UUID?, current: PreferenceSnapshot, apply: @escaping (PreferenceSnapshot) -> Void) async {
        pushTask?.cancel()
        self.accountID = accountID
        self.apply = apply
        ready = false
        lastSynced = nil
        revision = 0
        guard let accountID, let client = DuovaBackend.client, client.auth.currentUser?.id == accountID,
              let store = try? PreferenceCloudStore(client: client, userID: accountID)
        else { return }

        switch try? await store.pull() {
        case .snapshot(let remote, let remoteRevision):
            guard self.accountID == accountID else { return }
            lastSynced = remote
            revision = remoteRevision
            if remote != current { apply(remote) }
            ready = true
        case .empty(let remoteRevision):
            guard self.accountID == accountID else { return }
            revision = remoteRevision
            lastSynced = nil
            ready = true
            await save(current, store: store, accountID: accountID)
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
            await self.save(snapshot, store: store, accountID: accountID)
        }
    }

    /// Saves on top of the last revision; on a conflict, merges with what the
    /// other device saved and tries again.
    private func save(_ snapshot: PreferenceSnapshot, store: PreferenceCloudStore, accountID: UUID) async {
        var local = snapshot
        for _ in 0...Self.maxConflictRetries {
            guard !Task.isCancelled, self.accountID == accountID else { return }
            let saved: Int64?
            do {
                saved = try await store.push(local, expectedRevision: revision)
            } catch {
                return // Offline or refused: retried with the next change or sign-in.
            }
            guard self.accountID == accountID else { return }
            if let saved {
                revision = saved
                lastSynced = local
                return
            }

            // Another device saved first.
            let remote: PreferenceSnapshot
            switch try? await store.pull() {
            case .snapshot(let snapshot, let remoteRevision):
                remote = snapshot
                revision = remoteRevision
            case .empty(let remoteRevision):
                revision = remoteRevision
                continue
            case .sealedElsewhere:
                ready = false
                return
            case nil:
                return
            }
            guard self.accountID == accountID else { return }
            let merged = PreferenceSnapshot.merge(base: lastSynced ?? remote, local: local, remote: remote)
            lastSynced = remote
            if merged == remote {
                if merged != local { apply?(merged) }
                return
            }
            if merged != local {
                // Applying it here reports a change, which saves the merge.
                apply?(merged)
                return
            }
            local = merged
        }
    }

    func stop() {
        pushTask?.cancel()
        accountID = nil
        apply = nil
        ready = false
        lastSynced = nil
        revision = 0
    }
}
