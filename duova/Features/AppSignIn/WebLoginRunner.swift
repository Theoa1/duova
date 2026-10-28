import UIKit
import WebKit

/// Drives one app's login page in a web view: checks whether a session still
/// works, and fills in a saved login when it doesn't.
///
/// - Credentials are only typed into `https` pages on the recipe's own sites,
///   and are passed to the page as script arguments (never pasted into code).
/// - Duova's scripts run in their own JavaScript world, so the site's scripts
///   can't see or tamper with them.
/// - The web view's data store is in memory only; cookies are kept between
///   launches solely as a double-encrypted session cache (`AppLoginStore`).
@MainActor
final class WebLoginRunner: NSObject, WKNavigationDelegate {
    enum Outcome: Equatable {
        case signedIn
        case signedOut
        /// The site asked for a second step (a code, an approval).
        case mfa
        /// The site said no, with its message when it showed one.
        case rejected(String?)
        case fieldsNotFound
        case captcha
        case unreachable
        /// The login form wasn't on one of the app's own sites.
        case unsafePage
    }

    struct Analysis: Decodable {
        var url: String
        var identifier: Int
        var password: Int
        var submit: Int
        var next: Int
        var otp: Bool
        var captcha: Bool
        var error: String?
        var fields: [PageField]
    }

    let recipe: AppLoginRecipe
    let appName: String
    let webView: WKWebView
    private var loadFailed = false
    private var isCancelled = false

    init(recipe: AppLoginRecipe, appName: String, dataStore: WKWebsiteDataStore) {
        self.recipe = recipe
        self.appName = appName
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
    }

    // MARK: Hosting

    /// Pages only run normally inside a window, so the hidden web view sits
    /// in the window but off screen, invisible and untouchable.
    func attachHidden() {
        guard webView.superview == nil, let window = Self.keyWindow else { return }
        webView.frame = CGRect(x: -10_000, y: 0, width: 390, height: 844)
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        window.insertSubview(webView, at: 0)
    }

    func detach() {
        webView.removeFromSuperview()
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        webView.accessibilityElementsHidden = false
    }

    /// Stops an attempt in progress: nothing more is loaded, filled or pressed.
    func cancel() {
        isCancelled = true
        loadFailed = true
        webView.stopLoading()
        detach()
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    // MARK: Session

    func cookies() async -> [HTTPCookie] {
        await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            .filter { recipe.ownsCookie(domain: $0.domain) }
    }

    func hasSession() async -> Bool {
        let names = Set(recipe.sessionCookies)
        guard !names.isEmpty else { return false }
        return await cookies().contains { cookie in
            names.contains(cookie.name) && !cookie.value.isEmpty && (cookie.expiresDate.map { $0 > .now } ?? true)
        }
    }

    /// Loads a signed-in page and reports whether the session still works.
    func probe() async -> Outcome {
        guard await load(recipe.checkURL) else { return .unreachable }
        let page = await analyze()
        if page?.otp == true { return .mfa }
        if let page, page.password >= 0 || Self.looksLikeLogin(page.url) { return .signedOut }
        return await hasSession() ? .signedIn : .signedOut
    }

    // MARK: Sign in

    /// One sign-in attempt. The second attempt asks the on-device model first.
    func signIn(identifier: String, password: String, useModel: Bool) async -> Outcome {
        guard await load(recipe.loginURL) else { return .unreachable }
        guard var page = await analyze(waitForFields: true) else { return .fieldsNotFound }
        if page.otp { return .mfa }
        if page.password < 0, page.identifier < 0, await hasSession() { return .signedIn }
        if page.captcha { return .captcha }
        guard recipe.allowsCredentials(on: webView.url) else { return .unsafePage }

        var target = (identifier: page.identifier, password: page.password, submit: page.submit)
        if useModel || (target.identifier < 0 && target.password < 0) || target.submit < 0,
           let choice = await LoginFieldFinder.choose(from: page.fields, appName: appName) {
            if useModel || target.identifier < 0, choice.identifier >= 0 { target.identifier = choice.identifier }
            if useModel || target.password < 0, choice.password >= 0 { target.password = choice.password }
            if useModel || target.submit < 0, choice.submit >= 0 { target.submit = choice.submit }
        }
        guard target.identifier >= 0 || target.password >= 0 else { return .fieldsNotFound }

        if target.password < 0 {
            // Email first, then the password on the next screen.
            await fill(identifierAt: target.identifier, identifier, passwordAt: -1, "")
            await press(page.next >= 0 ? page.next : target.submit, fallbackField: target.identifier)
            var found = false
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let next = await analyze() else { continue }
                page = next
                if page.otp { return .mfa }
                if page.captcha { return .captcha }
                if page.password >= 0 { found = true; break }
                if let error = page.error { return .rejected(error) }
            }
            guard found else { return .fieldsNotFound }
            guard recipe.allowsCredentials(on: webView.url) else { return .unsafePage }
            target = (-1, page.password, page.submit)
        }

        await fill(identifierAt: target.identifier, identifier, passwordAt: target.password, password)
        await press(target.submit, fallbackField: target.password)
        return await result()
    }

    /// Watches the page after submitting.
    private func result() async -> Outcome {
        var last: Analysis?
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(600))
            if loadFailed { return .unreachable }
            guard let page = await analyze() else { continue }
            last = page
            if page.otp { return .mfa }
            if page.captcha { return .captcha }
            if page.password < 0, await hasSession() { return .signedIn }
            if page.password >= 0, let error = page.error { return .rejected(error) }
        }
        if await hasSession(), last?.password ?? -1 < 0 { return .signedIn }
        return .rejected(last?.error)
    }

    private static func looksLikeLogin(_ url: String) -> Bool {
        let lower = url.lowercased()
        return ["/login", "/signin", "/sign-in", "/accounts/login"].contains { lower.contains($0) }
    }

    // MARK: Page loading

    private func load(_ url: URL) async -> Bool {
        guard !isCancelled else { return false }
        loadFailed = false
        webView.load(URLRequest(url: url, timeoutInterval: 20))
        return await settle(timeout: 20)
    }

    /// Waits for the page to finish loading, plus a moment for scripts to draw it.
    private func settle(timeout: Double) async -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        try? await Task.sleep(for: .milliseconds(400))
        while Date.now < deadline {
            if loadFailed { return false }
            if !webView.isLoading {
                try? await Task.sleep(for: .milliseconds(1200))
                if !webView.isLoading { return !loadFailed }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return !loadFailed
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { loadFailed = true }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // Stay on the web: no jumps into other apps or custom schemes.
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        decisionHandler(["https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
    }

    // MARK: Scripts

    private func run(_ script: String, _ arguments: [String: Any] = [:]) async -> Any? {
        guard !isCancelled else { return nil }
        return try? await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .defaultClient)
    }

    /// Finds the login fields: the recipe's selectors first, then common
    /// patterns. Repeats for a few seconds while the page draws, if asked.
    func analyze(waitForFields: Bool = false) async -> Analysis? {
        let selectors: [String: Any] = [
            "identifier": recipe.identifierSelector ?? "", "password": recipe.passwordSelector ?? "",
            "submit": recipe.submitSelector ?? "", "next": recipe.nextSelector ?? "",
            "mfa": recipe.mfaSelector ?? "", "error": recipe.errorSelector ?? "", "mfaHints": recipe.mfaURLHints,
        ]
        var result: Analysis?
        for _ in 0..<(waitForFields ? 12 : 1) {
            if let json = await run(Self.analyzeScript, ["sel": selectors]) as? String,
               let page = try? JSONDecoder().decode(Analysis.self, from: Data(json.utf8)) {
                result = page
                if page.identifier >= 0 || page.password >= 0 || page.otp || page.captcha { return page }
            }
            if waitForFields { try? await Task.sleep(for: .milliseconds(500)) }
        }
        return result
    }

    private func fill(identifierAt identifierIndex: Int, _ identifier: String, passwordAt passwordIndex: Int, _ password: String) async {
        _ = await run(Self.fillScript, [
            "identifierIndex": identifierIndex, "identifierValue": identifier,
            "passwordIndex": passwordIndex, "passwordValue": password,
        ])
    }

    private func press(_ index: Int, fallbackField: Int) async {
        _ = await run(Self.pressScript, ["index": index, "fieldIndex": fallbackField])
    }

    private static let analyzeScript = #"""
        const visible = (el) => {
          if (!el || !el.isConnected) return false;
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          return r.width > 1 && r.height > 1 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0.05;
        };
        const pick = (selector) => {
          if (!selector) return null;
          try { return [...document.querySelectorAll(selector)].find(visible) || null; } catch (e) { return null; }
        };
        const all = [...document.querySelectorAll('input:not([type=hidden]), button, [role="button"]')].filter(visible).slice(0, 80);
        window.__duovaFields = all;
        // Button captions only; never what's typed in a field.
        const caption = (el) => (el.tagName === 'INPUT' ? (['submit', 'button'].includes(el.type) ? el.value : '') : el.innerText) || '';
        const text = (el) => (caption(el) + ' ' + (el.getAttribute('aria-label') || '')).replace(/\s+/g, ' ').trim();
        const meta = (el) => [el.name, el.id, el.placeholder, el.getAttribute('aria-label'), el.autocomplete].join(' ');
        const isInput = (el) => el.tagName === 'INPUT';
        const textLike = (el) => isInput(el) && ['', 'text', 'email', 'tel'].includes((el.type || '').toLowerCase());
        const isPassword = (el) => !!el && isInput(el) && el.type === 'password';
        const chosenPassword = pick(sel.password);
        const chosenIdentifier = pick(sel.identifier);
        const password = (isPassword(chosenPassword) ? chosenPassword : null) || all.find(isPassword);
        let identifier = (textLike(chosenIdentifier) ? chosenIdentifier : null)
          || all.find((el) => textLike(el) && /username|email|tel/.test(el.autocomplete || ''))
          || all.find((el) => isInput(el) && el.type === 'email')
          || all.find((el) => textLike(el) && /user|email|e-mail|login|phone|account|identifier/i.test(meta(el)));
        if (!identifier && password) {
          const before = all.filter((el) => textLike(el) && (el.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING));
          identifier = before[before.length - 1] || null;
        }
        const anchor = password || identifier;
        const scope = anchor && anchor.form ? [...anchor.form.querySelectorAll('button, input[type=submit], [role="button"]')].filter(visible) : [];
        const words = /^(log ?in|sign ?in|continue|next|submit)$/i;
        const submit = pick(sel.submit) || scope.find((el) => el.type === 'submit') || scope.find((el) => words.test(text(el)))
          || all.find((el) => el.type === 'submit' || words.test(text(el)));
        const next = pick(sel.next);
        const otpField = pick(sel.mfa) || all.find((el) => isInput(el) && el.type !== 'password'
          && (el.autocomplete === 'one-time-code' || /otp|one.?time|verification|security.?code|2fa|two.?factor|passcode/i.test(meta(el))));
        const otp = !password && (!!otpField || (sel.mfaHints || []).some((hint) => hint && location.href.includes(hint)));
        const captcha = !!document.querySelector('iframe[src*="captcha" i], iframe[src*="arkoselabs" i], iframe[title*="challenge" i], [id*="captcha" i]');
        const errorNode = pick(sel.error);
        const errorText = errorNode ? errorNode.innerText.replace(/\s+/g, ' ').trim().slice(0, 160) : '';
        const index = (el) => (el ? all.indexOf(el) : -1);
        return JSON.stringify({
          url: location.href,
          identifier: index(identifier), password: index(password), submit: index(submit), next: index(next),
          otp, captcha, error: errorText || null,
          fields: all.map((el, i) => ({
            index: i, tag: el.tagName.toLowerCase(), type: (el.type || '').toLowerCase(), name: el.name || '',
            id: el.id || '', placeholder: el.placeholder || '', autocomplete: el.autocomplete || '', label: text(el).slice(0, 60),
          })),
        });
        """#

    private static let fillScript = #"""
        const fields = window.__duovaFields || [];
        const setValue = (el, value) => {
          el.focus();
          Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value);
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        };
        // A password only ever goes into a password field, an identifier only into a text field.
        const typeOf = (el) => (el && el.tagName === 'INPUT' ? (el.type || '').toLowerCase() : null);
        const identifierField = fields[identifierIndex];
        const passwordField = fields[passwordIndex];
        let filled = 0;
        if (identifierIndex >= 0 && ['', 'text', 'email', 'tel'].includes(typeOf(identifierField))) { setValue(identifierField, identifierValue); filled++; }
        if (passwordIndex >= 0 && typeOf(passwordField) === 'password') { setValue(passwordField, passwordValue); filled++; }
        return filled;
        """#

    private static let pressScript = #"""
        const fields = window.__duovaFields || [];
        const button = fields[index];
        if (button) { button.click(); return true; }
        const field = fields[fieldIndex];
        if (field && field.form) {
          if (field.form.requestSubmit) { field.form.requestSubmit(); } else { field.form.submit(); }
          return true;
        }
        return false;
        """#
}
