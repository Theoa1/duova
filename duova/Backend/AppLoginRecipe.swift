import Foundation
import Supabase

/// How Duova signs in to one app's website: where the login page is, the CSS
/// selectors for its fields, and how to tell that it worked.
///
/// The bundled recipes below are the fallback; published rows in
/// `duova_app_login_recipes` (schema v4) replace them, so a site that changes
/// its login page can be fixed without an app update. When no selector
/// matches, Duova looks for the fields itself (see `LoginFieldFinder`).
nonisolated struct AppLoginRecipe: Codable, Equatable, Sendable {
    enum Support: String, Codable, Sendable {
        /// Duova fills in the saved login and checks the result.
        case automatic
        /// The person signs in themselves in the sign-in sheet (for example a QR code).
        case manual
        /// The site doesn't allow signing in here.
        case unavailable

        fileprivate var rank: Int {
            switch self {
            case .automatic: 0
            case .manual: 1
            case .unavailable: 2
            }
        }
    }

    var slug: String
    var loginURL: URL
    /// A signed-in page; loading it shows whether the session still works.
    var checkURL: URL
    /// Credentials are only ever typed into pages on these sites (or their subdomains).
    var hosts: [String]
    /// Cookies the site sets once someone is signed in.
    var sessionCookies: [String]
    var identifierSelector: String? = nil
    var passwordSelector: String? = nil
    var submitSelector: String? = nil
    /// The "Next" button of a login that asks for the email first, then the password.
    var nextSelector: String? = nil
    /// A field for a second-step code.
    var mfaSelector: String? = nil
    /// URL fragments that mean the site is asking for a second step.
    var mfaURLHints: [String] = []
    var errorSelector: String? = nil
    var support: Support = .automatic
    /// Shown on the card when the app can't sign in automatically (five words max).
    var note: String? = nil

    enum CodingKeys: String, CodingKey {
        case slug = "app_slug", loginURL = "login_url", checkURL = "check_url", hosts
        case sessionCookies = "session_cookies", identifierSelector = "identifier_selector"
        case passwordSelector = "password_selector", submitSelector = "submit_selector"
        case nextSelector = "next_selector", mfaSelector = "mfa_selector", mfaURLHints = "mfa_url_hints"
        case errorSelector = "error_selector", support, note
    }

    /// Whether credentials may be typed into a page at this address.
    func allowsCredentials(on url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func ownsCookie(domain: String) -> Bool {
        let domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return hosts.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }
}

extension AppLoginRecipe {
    private static func google(_ slug: String) -> AppLoginRecipe {
        AppLoginRecipe(
            slug: slug, loginURL: URL(string: "https://accounts.google.com/")!,
            checkURL: URL(string: "https://myaccount.google.com/")!, hosts: ["google.com", "youtube.com"],
            sessionCookies: ["SID", "__Secure-3PSID"], mfaURLHints: ["/challenge/"],
            support: .unavailable, note: String(localized: "Google blocks in-app sign-in."))
    }

    /// Starting points, checked by hand. Sites change; the database copy wins.
    static let bundled: [String: AppLoginRecipe] = {
        let recipes = [
            AppLoginRecipe(
                slug: ServiceID.instagram.rawValue,
                loginURL: URL(string: "https://www.instagram.com/accounts/login/")!,
                checkURL: URL(string: "https://www.instagram.com/")!, hosts: ["instagram.com"],
                sessionCookies: ["sessionid"],
                identifierSelector: "input[name=\"username\"]", passwordSelector: "input[name=\"password\"]",
                submitSelector: "button[type=\"submit\"]",
                mfaSelector: "input[name=\"verificationCode\"], input[name=\"security_code\"]",
                mfaURLHints: ["two_factor", "/challenge/"], errorSelector: "#slfErrorAlert, [role=\"alert\"]"),
            AppLoginRecipe(
                slug: ServiceID.spotify.rawValue,
                loginURL: URL(string: "https://accounts.spotify.com/en/login")!,
                checkURL: URL(string: "https://accounts.spotify.com/en/status")!, hosts: ["spotify.com"],
                sessionCookies: ["sp_dc"],
                identifierSelector: "#login-username", passwordSelector: "#login-password",
                submitSelector: "#login-button", mfaSelector: "input[autocomplete=\"one-time-code\"]",
                mfaURLHints: ["/challenge"], errorSelector: "[data-encore-id=\"banner\"], [role=\"alert\"]"),
            AppLoginRecipe(
                slug: ServiceID.twitch.rawValue,
                loginURL: URL(string: "https://www.twitch.tv/login")!,
                checkURL: URL(string: "https://www.twitch.tv/settings/profile")!, hosts: ["twitch.tv"],
                sessionCookies: ["auth-token"],
                identifierSelector: "#login-username", passwordSelector: "#password-input",
                submitSelector: "[data-a-target=\"passport-login-button\"]",
                mfaSelector: "input[autocomplete=\"one-time-code\"], [data-a-target=\"tw-input\"][inputmode=\"numeric\"]",
                errorSelector: "[data-a-target=\"passport-error-message\"], [role=\"alert\"]"),
            AppLoginRecipe(
                slug: ServiceID.tiktok.rawValue,
                loginURL: URL(string: "https://www.tiktok.com/login/phone-or-email/email")!,
                checkURL: URL(string: "https://www.tiktok.com/setting")!, hosts: ["tiktok.com"],
                sessionCookies: ["sessionid"],
                identifierSelector: "input[name=\"username\"]", passwordSelector: "input[type=\"password\"]",
                submitSelector: "button[type=\"submit\"]", mfaSelector: "input[autocomplete=\"one-time-code\"]",
                mfaURLHints: ["verify"], errorSelector: "[class*=\"ErrorText\"], [role=\"alert\"]"),
            AppLoginRecipe(
                slug: ServiceID.excel.rawValue,
                loginURL: URL(string: "https://login.microsoftonline.com/")!,
                checkURL: URL(string: "https://www.office.com/")!,
                hosts: ["microsoftonline.com", "live.com", "microsoft.com", "office.com"],
                sessionCookies: ["ESTSAUTH", "ESTSAUTHPERSISTENT", "__Host-MSAAUTH"],
                identifierSelector: "input[name=\"loginfmt\"]", passwordSelector: "input[name=\"passwd\"]",
                submitSelector: "#idSIButton9", nextSelector: "#idSIButton9",
                mfaSelector: "input[name=\"otc\"], #idTxtBx_SAOTCC_OTC, #idRichContext_DisplaySign",
                mfaURLHints: ["/proofs/", "SAOTC"],
                errorSelector: "#usernameError, #passwordError, [role=\"alert\"]"),
            google(ServiceID.gmail.rawValue),
            google(ServiceID.googleDocs.rawValue),
            google(ServiceID.googleMaps.rawValue),
            google(ServiceID.youtube.rawValue),
            google(ServiceID.googleSlides.rawValue),
        ]
        return Dictionary(uniqueKeysWithValues: recipes.map { ($0.slug, $0) })
    }()

    /// Published recipes from the database, falling back to the bundled ones.
    ///
    /// A database recipe can update selectors, the check page and the note, but
    /// never where a password may go or which cookies are kept: the sites,
    /// login page and session cookies always come from the app. It can also
    /// only make support stricter. The page script itself refuses to put a
    /// password anywhere but a password field.
    static func load(client: SupabaseClient?) async -> [String: AppLoginRecipe] {
        var recipes = bundled
        guard let client else { return recipes }
        let remote: [AppLoginRecipe]? = try? await client.from("duova_app_login_recipes")
            .select("app_slug,login_url,check_url,hosts,session_cookies,identifier_selector,password_selector,submit_selector,next_selector,mfa_selector,mfa_url_hints,error_selector,support,note")
            .execute().value
        for recipe in remote ?? [] {
            guard let shipped = bundled[recipe.slug], shipped.allowsCredentials(on: recipe.checkURL) else { continue }
            var merged = recipe
            merged.loginURL = shipped.loginURL
            merged.hosts = shipped.hosts
            merged.sessionCookies = shipped.sessionCookies
            merged.support = recipe.support.rank >= shipped.support.rank ? recipe.support : shipped.support
            recipes[recipe.slug] = merged
        }
        return recipes
    }
}

/// A cookie in a form that can be sealed into an app's session cache.
nonisolated struct StoredCookie: Codable, Equatable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String?

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate
        secure = cookie.isSecure
        httpOnly = cookie.isHTTPOnly
        sameSite = cookie.sameSitePolicy?.rawValue
    }

    var isExpired: Bool { expires.map { $0 < .now } ?? false }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
        ]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSite { properties[.sameSitePolicy] = sameSite }
        return HTTPCookie(properties: properties)
    }
}
