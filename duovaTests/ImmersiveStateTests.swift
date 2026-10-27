import Foundation
import Testing
@testable import duova

/// Checkpoints remember only sanitized routes, and adapters only accept the
/// exact hosts they were written for.
@MainActor
struct ImmersiveStateTests {
    private let instagram = InstagramAdapter()

    private func makeStore() -> SecureStore {
        let dir = URL.temporaryDirectory.appending(path: "duova-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return SecureStore(directory: dir, keyService: "com.duova.tests.\(UUID().uuidString)")
    }

    // MARK: Routes

    @Test func checkpointRouteDropsQueryAndFragment() {
        let url = URL(string: "https://www.instagram.com/explore/?utm_source=x&igsh=TOKEN#frag")!
        #expect(instagram.checkpointRoute(for: url) == "/explore/")
    }

    @Test func signInAndRecoveryRoutesAreNeverRemembered() {
        for path in ["/accounts/login/", "/accounts/password/reset/", "/challenge/abc/", "/accounts/onetap/"] {
            let url = URL(string: "https://www.instagram.com\(path)")!
            #expect(instagram.checkpointRoute(for: url) == nil, "\(path) should not be checkpointed")
        }
    }

    @Test func messageThreadsCollapseToTheInbox() {
        let thread = URL(string: "https://www.instagram.com/direct/t/1234567890/")!
        #expect(instagram.checkpointRoute(for: thread) == "/direct/inbox/")
    }

    @Test func otherHostsAreNotRemembered() {
        #expect(instagram.checkpointRoute(for: URL(string: "https://www.facebook.com/login/")!) == nil)
        #expect(instagram.checkpointRoute(for: URL(string: "https://evil.example/p/abc/")!) == nil)
    }

    @Test func restoredRoutesAreReValidated() {
        #expect(instagram.url(forCheckpointRoute: "/explore/") == URL(string: "https://www.instagram.com/explore/"))
        #expect(instagram.url(forCheckpointRoute: "/accounts/login/") == nil)
        #expect(instagram.url(forCheckpointRoute: "../../etc") == nil)
        #expect(instagram.url(forCheckpointRoute: "explore") == nil)
    }

    // MARK: Hosts

    @Test func mainFrameHostsMatchExactly() {
        #expect(instagram.allowsMainFrame(URL(string: "https://www.instagram.com/")!))
        #expect(instagram.allowsMainFrame(URL(string: "https://instagram.com/p/x/")!))
        #expect(instagram.allowsMainFrame(URL(string: "https://www.facebook.com/login.php")!))
        #expect(!instagram.allowsMainFrame(URL(string: "http://www.instagram.com/")!))
        #expect(!instagram.allowsMainFrame(URL(string: "https://www.instagram.com.evil.example/")!))
        #expect(!instagram.allowsMainFrame(URL(string: "https://evil-instagram.com/")!))
        #expect(!instagram.allowsMainFrame(URL(string: "https://notinstagram.com/")!))
    }

    // MARK: Companion classification

    @Test func companionKindsFollowRealRoutes() {
        func kind(_ path: String) -> CompanionKind? {
            instagram.companionKind(for: URL(string: "https://www.instagram.com\(path)")!, from: nil)
        }
        #expect(kind("/p/Cabc123/") == .post)
        #expect(kind("/reel/Cxyz/") == .post)
        #expect(kind("/explore/") == .explore)
        #expect(kind("/direct/inbox/") == .messages)
        #expect(kind("/some.user_name/") == .profile)
        #expect(kind("/some.user_name/reels/") == .profile)
        #expect(kind("/accounts/edit/") == nil)
        #expect(kind("/reels/") == nil)
        #expect(kind("/") == nil)
        #expect(kind("/p/") == nil)
        #expect(kind("/user/p/abc/") == nil)
    }

    // MARK: Checkpoint storage

    @Test func checkpointRoundTripsAndIsScoped() {
        let store = ImmersiveCheckpointStore(store: makeStore())
        let account = UUID()
        let checkpoint = ImmersiveCheckpoint(
            adapterVersion: 1, accountID: account, service: .instagram, primaryRoute: "/explore/",
            companionRoute: "/p/abc/", companionKind: .post, splitRatio: .fiftyFifty, primaryScrollY: 1234,
            companionScrollY: 0, anchor: "/p/def/", posture: .openLandscape, capturedAt: .now)
        store.save(checkpoint)

        let loaded = store.load(accountID: account, service: .instagram)
        #expect(loaded?.primaryRoute == "/explore/")
        #expect(loaded?.companionKind == .post)
        #expect(loaded?.splitRatio == .fiftyFifty)
        #expect(loaded?.primaryScrollY == 1234)
        #expect(loaded?.posture == .openLandscape)

        // Another account or service sees nothing.
        #expect(store.load(accountID: UUID(), service: .instagram) == nil)
        store.remove(accountID: account, service: .instagram)
        #expect(store.load(accountID: account, service: .instagram) == nil)
    }

    @Test func checkpointHoldsNoSecrets() throws {
        // Everything in a checkpoint is a path, number, enum or date; there is
        // no field a token, query string or message body could travel in.
        let checkpoint = ImmersiveCheckpoint(
            adapterVersion: 1, accountID: UUID(), service: .instagram, primaryRoute: "/", companionRoute: nil,
            companionKind: nil, splitRatio: nil, primaryScrollY: 0, companionScrollY: 0, anchor: nil,
            posture: .closedPortrait, capturedAt: .now)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any]
        let keys = Set(json?.keys.map { $0 } ?? [])
        #expect(keys == [
            "schemaVersion", "adapterVersion", "accountID", "service", "primaryRoute", "primaryScrollY",
            "companionScrollY", "posture", "capturedAt",
        ])
    }

    // MARK: Website data stores

    @Test func websiteStoreIdentifiersAreStablePerAccountAndService() {
        let store = makeStore()
        let a = UUID(), b = UUID()
        let first = ServiceSessionRegistry.identifier(accountID: a, service: .instagram, store: store)
        let again = ServiceSessionRegistry.identifier(accountID: a, service: .instagram, store: store)
        let other = ServiceSessionRegistry.identifier(accountID: b, service: .instagram, store: store)
        #expect(first == again)
        #expect(first != other)
        #expect(ServiceSessionRegistry.identifiers(for: a, store: store) == [first])
    }
}
