import Observation
import SwiftUI
import WebKit

/// Whether Duova is signed in to an app, as its card shows it.
enum AppSignInStatus: Equatable {
    case unknown
    case checking
    case signedIn
    /// No working session and nothing Duova can sign in with.
    case notSignedIn
    /// The app wants a second step (code or approval) from the person.
    case mfaNeeded
    case failed(String)
    case unavailable(String)
    case offline

    /// Five words max.
    var title: String {
        switch self {
        case .unknown: ""
        case .checking: String(localized: "Checking sign-in…")
        case .signedIn: String(localized: "Signed in")
        case .notSignedIn: String(localized: "Not signed in")
        case .mfaNeeded: String(localized: "MFA needed. Finish sign-in.")
        case .failed(let reason), .unavailable(let reason): reason
        case .offline: String(localized: "Couldn't reach app.")
        }
    }

    var symbol: String {
        switch self {
        case .unknown, .checking: "ellipsis"
        case .signedIn: "checkmark.circle.fill"
        case .notSignedIn: "person.crop.circle.badge.questionmark"
        case .mfaNeeded: "lock.shield.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .unavailable: "nosign"
        case .offline: "wifi.slash"
        }
    }
}

/// Checks, for every app in the catalog, whether Duova is signed in, and signs
/// in with the saved login when it isn't.
///
/// - A cached session (double-encrypted cookies) is tried first by loading a
///   signed-in page.
/// - Otherwise Duova fills in the saved email/username + password, up to
///   **three tries** in all, kept across launches. Only Duova tries; later
///   tries ask Apple's on-device model where the fields are, in case the page
///   changed. After the third, it stops ("We couldn't sign in.") until the
///   person signs in themselves or changes the saved login, so a wrong
///   password can't lock the account.
/// - A second step (code, approval) stops there: the card says "MFA needed"
///   and the sign-in sheet lets the person finish.
@MainActor
@Observable
final class AppSignInCenter {
    static let maxAttempts = 3

    private(set) var statuses: [ServiceID: AppSignInStatus] = [:]
    private var accountID: UUID?
    private var recipes = AppLoginRecipe.bundled
    @ObservationIgnored private var dataStores: [ServiceID: WKWebsiteDataStore] = [:]
    /// Pages left mid-sign-in (waiting for a code), handed to the sign-in sheet.
    @ObservationIgnored private var paused: [ServiceID: WebLoginRunner] = [:]
    @ObservationIgnored private var interactive: [ServiceID: WebLoginRunner] = [:]
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var checking: Set<ServiceID> = []
    /// The hidden page of an automatic attempt in progress.
    @ObservationIgnored private var running: [ServiceID: WebLoginRunner] = [:]
    /// Apps whose automatic attempt was stopped because the person signs in themselves.
    @ObservationIgnored private var interrupted: Set<ServiceID> = []

    func status(for id: ServiceID) -> AppSignInStatus { statuses[id] ?? .unknown }

    func recipe(for id: ServiceID) -> AppLoginRecipe? { recipes[id.rawValue] }

    // MARK: Lifecycle

    /// Once this device has the account's keys, checks only the apps with a
    /// saved login or session (`priority`, such as favorites, first), one at a
    /// time. Every other app is checked when its card is opened, so starting
    /// Duova never reaches out to apps the person hasn't set up.
    func start(accountID: UUID?, priority: [ServiceID] = []) {
        stop()
        self.accountID = accountID
        guard let accountID else { return }
        runTask = Task { [weak self] in
            let recipes = await AppLoginRecipe.load(client: DuovaBackend.client)
            guard let self, !Task.isCancelled, self.accountID == accountID else { return }
            self.recipes = recipes
            // Let the app finish appearing first.
            try? await Task.sleep(for: .seconds(2))
            let saved = await self.appsWithSavedSignIn()
            let ordered = priority.filter(saved.contains)
                + ServiceCatalog.all.map(\.id).filter { saved.contains($0) && !priority.contains($0) }
            for id in ordered {
                guard !Task.isCancelled, self.accountID == accountID else { return }
                await self.check(id)
            }
        }
    }

    /// Apps with something to check: a saved login or session on this device,
    /// or a saved login in the cloud (one request for all of them).
    private func appsWithSavedSignIn() async -> Set<ServiceID> {
        guard let store = loginStore else { return [] }
        let cloud = await store.cloudReferences() ?? []
        return Set(ServiceCatalog.all.map(\.id).filter { id in
            let slug = id.rawValue
            return store.login(for: slug) != nil || store.sessionCache(for: slug) != nil
                || cloud.contains(store.reference(slug))
        })
    }

    /// Checks an app the first time its card is opened.
    func checkIfNeeded(_ id: ServiceID) async {
        guard status(for: id) == .unknown, !checking.contains(id) else { return }
        await check(id)
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        accountID = nil
        statuses = [:]
        for runner in paused.values { runner.detach() }
        for runner in interactive.values { runner.detach() }
        for runner in running.values { runner.cancel() }
        paused = [:]
        interactive = [:]
        running = [:]
        interrupted = []
        checking = []
        dataStores = [:]
    }

    /// The saved login was saved, changed or deleted: the tries start over.
    func loginChanged(_ id: ServiceID) {
        guard let store = loginStore else { return }
        resetTries(store.reference(id.rawValue))
        Task { await check(id) }
    }

    /// Clears the app's session, and keeps the app signed out: Duova won't
    /// sign it back in with the saved login until the person signs in
    /// themselves or saves the login again. The saved login itself stays
    /// (delete it from Saved Login to forget it).
    func signOut(of id: ServiceID) async {
        guard let store = loginStore else { return }
        UserDefaults.standard.set(true, forKey: key("signed-out", store.reference(id.rawValue)))
        if checking.contains(id) {
            interrupted.insert(id)
            running.removeValue(forKey: id)?.cancel()
        }
        store.clearSessionCache(for: id.rawValue)
        if let dataStore = dataStores[id] {
            await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        paused[id]?.detach()
        paused[id] = nil
        statuses[id] = .notSignedIn
    }

    // MARK: Checking

    private var loginStore: AppLoginStore? {
        accountID.flatMap { try? AppLoginStore(accountID: $0) }
    }

    /// Each app keeps its cookies apart from every other app's, in memory.
    private func dataStore(for id: ServiceID) -> WKWebsiteDataStore {
        if let existing = dataStores[id] { return existing }
        let fresh = WKWebsiteDataStore.nonPersistent()
        dataStores[id] = fresh
        return fresh
    }

    func check(_ id: ServiceID) async {
        guard !checking.contains(id), let store = loginStore else { return }
        let slug = id.rawValue
        guard let recipe = recipes[slug] else {
            statuses[id] = .unavailable(String(localized: "Sign-in not supported yet."))
            return
        }
        if recipe.support == .unavailable {
            statuses[id] = .unavailable(recipe.note ?? String(localized: "Sign-in not supported yet."))
            return
        }
        guard interactive[id] == nil else { return }
        checking.insert(id)
        interrupted.remove(id)
        defer {
            checking.remove(id)
            running[id] = nil
        }
        statuses[id] = .checking
        paused[id]?.detach()
        paused[id] = nil

        if store.login(for: slug) == nil, store.sessionCache(for: slug) == nil {
            _ = await store.restoreFromCloud(for: slug)
        }

        let dataStore = dataStore(for: id)
        let hadSession = await restoreCookies(from: store, slug: slug, recipe: recipe, into: dataStore)
        guard !interrupted.contains(id) else { return }
        let login = store.login(for: slug)
        let canFill = recipe.support == .automatic && login.map {
            $0.method.usesPassword && !$0.identifier.isEmpty && !$0.password.isEmpty
        } == true
        guard hadSession || canFill else {
            statuses[id] = .notSignedIn
            return
        }
        if !hadSession, UserDefaults.standard.bool(forKey: key("signed-out", store.reference(slug))) {
            statuses[id] = .notSignedIn
            return
        }
        let runner = WebLoginRunner(recipe: recipe, appName: ServiceCatalog.service(id).name, dataStore: dataStore)
        runner.attachHidden()
        running[id] = runner
        var keepRunner = false
        defer { if !keepRunner { runner.detach() } }

        if hadSession {
            let outcome = await runner.probe()
            guard !interrupted.contains(id) else { return }
            switch outcome {
            case .signedIn:
                resetTries(store.reference(slug))
                await saveCookies(from: runner, to: store, slug: slug)
                statuses[id] = .signedIn
                return
            case .unreachable:
                statuses[id] = .offline
                return
            case .mfa:
                keepRunner = true
                paused[id] = runner
                statuses[id] = .mfaNeeded
                return
            default:
                break // The session expired; try the saved login.
            }
        }

        guard canFill, let login else {
            statuses[id] = .notSignedIn
            return
        }
        let ref = store.reference(slug)
        let usedSoFar = used(ref)
        guard usedSoFar < Self.maxAttempts else {
            statuses[id] = .failed(hold(ref) ?? Self.couldNotSignIn)
            return
        }

        for attempt in (usedSoFar + 1)...Self.maxAttempts {
            guard !Task.isCancelled else { return }
            setUsed(attempt, ref)
            let outcome = await runner.signIn(identifier: login.identifier, password: login.password, useModel: attempt > 1)
            guard !interrupted.contains(id) else {
                // Stopped for the person to sign in themselves: not a real try.
                setUsed(attempt - 1, ref)
                return
            }
            switch outcome {
            case .signedIn:
                resetTries(ref)
                await saveCookies(from: runner, to: store, slug: slug)
                statuses[id] = .signedIn
                return
            case .mfa:
                keepRunner = true
                paused[id] = runner
                statuses[id] = .mfaNeeded
                return
            case .captcha:
                setUsed(Self.maxAttempts, ref)
                stop(id, ref: ref, reason: String(localized: "Blocked by a captcha."))
                return
            case .unsafePage:
                setUsed(Self.maxAttempts, ref)
                stop(id, ref: ref, reason: String(localized: "Login page looked unsafe."))
                return
            case .unreachable:
                // Not a real try: the page never loaded.
                setUsed(attempt - 1, ref)
                statuses[id] = .offline
                return
            case .fieldsNotFound, .rejected, .signedOut:
                if attempt == Self.maxAttempts {
                    stop(id, ref: ref, reason: Self.couldNotSignIn)
                    return
                }
            }
        }
    }

    private static var couldNotSignIn: String { String(localized: "We couldn't sign in.") }

    private func stop(_ id: ServiceID, ref: String, reason: String) {
        setHold(ref, reason: reason)
        statuses[id] = .failed(reason)
    }

    private func restoreCookies(
        from store: AppLoginStore, slug: String, recipe: AppLoginRecipe, into dataStore: WKWebsiteDataStore
    ) async -> Bool {
        guard let data = store.sessionCache(for: slug),
              let cookies = try? JSONDecoder().decode([StoredCookie].self, from: data)
        else { return false }
        let live = cookies.filter { !$0.isExpired && recipe.ownsCookie(domain: $0.domain) }
        for stored in live {
            if let cookie = stored.cookie { await dataStore.httpCookieStore.setCookie(cookie) }
        }
        return live.contains { recipe.sessionCookies.contains($0.name) }
    }

    private func saveCookies(from runner: WebLoginRunner, to store: AppLoginStore, slug: String) async {
        let cookies = await runner.cookies().map(StoredCookie.init)
        guard !cookies.isEmpty, let data = try? JSONEncoder().encode(cookies) else { return }
        try? store.saveSessionCache(data, for: slug)
    }

    // MARK: Signing in by hand

    /// The page for the sign-in sheet: the one paused at a code step, or a
    /// fresh login page. Stops any automatic attempt still running.
    func beginInteractive(_ id: ServiceID) -> WebLoginRunner? {
        if let runner = interactive[id] { return runner }
        guard let recipe = recipes[id.rawValue], recipe.support != .unavailable else { return nil }
        if checking.contains(id) {
            interrupted.insert(id)
            running.removeValue(forKey: id)?.cancel()
            statuses[id] = .notSignedIn
        }
        let runner: WebLoginRunner
        if let waiting = paused.removeValue(forKey: id) {
            waiting.detach()
            runner = waiting
        } else {
            runner = WebLoginRunner(recipe: recipe, appName: ServiceCatalog.service(id).name, dataStore: dataStore(for: id))
            runner.webView.load(URLRequest(url: recipe.loginURL))
        }
        interactive[id] = runner
        return runner
    }

    /// Whether the person has finished signing in; keeps the session if so.
    func completeInteractive(_ id: ServiceID) async -> Bool {
        guard let runner = interactive[id], let store = loginStore else { return false }
        guard await runner.hasSession() else { return false }
        let page = await runner.analyze()
        guard (page?.password ?? -1) < 0, page?.otp != true else { return false }
        await saveCookies(from: runner, to: store, slug: id.rawValue)
        resetTries(store.reference(id.rawValue))
        statuses[id] = .signedIn
        return true
    }

    func endInteractive(_ id: ServiceID) {
        interactive.removeValue(forKey: id)?.detach()
        if statuses[id] == .mfaNeeded, paused[id] == nil {
            statuses[id] = .notSignedIn
        }
    }

    // MARK: Tries

    /// Tries used and the last failure, keyed by the app's opaque reference, not its name.
    private func key(_ kind: String, _ ref: String) -> String {
        "duova.app-signin.\(kind).\(accountID?.uuidString.lowercased() ?? "none").\(ref)"
    }

    private func used(_ ref: String) -> Int { UserDefaults.standard.integer(forKey: key("used", ref)) }

    private func setUsed(_ count: Int, _ ref: String) {
        UserDefaults.standard.set(count, forKey: key("used", ref))
    }

    /// Also called whenever the person signs in or changes the saved login,
    /// which ends a sign-out too.
    private func resetTries(_ ref: String) {
        UserDefaults.standard.removeObject(forKey: key("used", ref))
        UserDefaults.standard.removeObject(forKey: key("hold", ref))
        UserDefaults.standard.removeObject(forKey: key("signed-out", ref))
    }

    private func hold(_ ref: String) -> String? { UserDefaults.standard.string(forKey: key("hold", ref)) }
    private func setHold(_ ref: String, reason: String) { UserDefaults.standard.set(reason, forKey: key("hold", ref)) }
}
