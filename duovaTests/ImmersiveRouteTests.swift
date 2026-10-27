import Foundation
import Testing
@testable import duova

/// The route invariant: once a service is launched for an account, the app
/// routes to it, and keeps routing to it on a fresh start.
@MainActor
struct ImmersiveRouteTests {
    private func makeStore() -> SecureStore {
        let dir = URL.temporaryDirectory.appending(path: "duova-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return SecureStore(directory: dir, keyService: "com.duova.tests.\(UUID().uuidString)")
    }

    @Test func noLaunchMeansLibrary() {
        let account = UUID()
        let route = DuovaLaunchRouteStore(accountID: account, store: makeStore())
        #expect(route.committedService == nil)
        #expect(route.route(for: account) == .initialLibrary)
    }

    @Test func signedOutIsAlwaysLibrary() {
        let route = DuovaLaunchRouteStore(accountID: nil, store: makeStore())
        #expect(route.route(for: nil) == .initialLibrary)
        #expect(route.commit(.instagram) == false)
    }

    @Test func commitRoutesToServiceAndSurvivesRelaunch() {
        let store = makeStore()
        let account = UUID()
        let first = DuovaLaunchRouteStore(accountID: account, store: store)
        #expect(first.commit(.instagram))
        #expect(first.route(for: account) == .immersive(.instagram))

        // A new instance, as after a force quit, reads the same commitment.
        let second = DuovaLaunchRouteStore(accountID: account, store: store)
        #expect(second.route(for: account) == .immersive(.instagram))
    }

    @Test func commitmentIsScopedToTheAccount() {
        let store = makeStore()
        let a = UUID(), b = UUID()
        let route = DuovaLaunchRouteStore(accountID: a, store: store)
        #expect(route.commit(.instagram))
        route.activate(accountID: b)
        #expect(route.route(for: b) == .initialLibrary)
        route.activate(accountID: a)
        #expect(route.route(for: a) == .immersive(.instagram))
        // Asking about another account than the active one never leaks the route.
        #expect(route.route(for: b) == .initialLibrary)
    }

    @Test func servicesWithoutAnAdapterCannotBeCommitted() {
        let account = UUID()
        let route = DuovaLaunchRouteStore(accountID: account, store: makeStore())
        let unsupported = ServiceID.allCases.first { SocialAdapterRegistry.adapter(for: $0) == nil }
        if let unsupported {
            #expect(route.commit(unsupported) == false)
            #expect(route.route(for: account) == .initialLibrary)
        }
    }

    @Test func debugResetIsTheOnlyWayBack() {
        let account = UUID()
        let route = DuovaLaunchRouteStore(accountID: account, store: makeStore())
        #expect(route.commit(.instagram))
        route.resetForTesting()
        #expect(route.route(for: account) == .initialLibrary)
    }
}
