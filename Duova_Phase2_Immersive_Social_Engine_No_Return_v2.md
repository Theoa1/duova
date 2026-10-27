# DUOVA — PHASE 2: IMMERSIVE SOCIAL EXPERIENCE ENGINE
## Instagram-first universal social adapter — Revised locked specification, v2.0
**Date:** 26 October 2026  
**Implementation baseline:** `Theoa1/duova`, `top-navigation` branch, commit reviewed in the previous phase.  
**Visual reference:** User-provided Stitch HTML prototype, adapted as architectural inspiration, **not** as a page to display inside Duova and **not** as a license to recolor Instagram.  
**Scope:** Native SwiftUI/UIKit host, real third-party website within WebKit, desktop-first presentation, seven Duo layout modes, persistent state and warm loading.

---

# 0. OVERRIDING PRODUCT DECISION — NO RETURN, NO DUOVA UI

This section takes priority over every earlier Duova Phase 2 document and prototype, including every reference to a floating switcher, a persistent Duova edge handle, a close button, a back-to-library gesture, or an in-service app rail.

**For this phase, once Instagram (or another supported service) is launched, it is the complete visible Duova application experience. There is NO in-app route back to the Duova library or shell.** The existing Duova library, search and profile navigation appear only **before a service has been launched** (or in intentional developer-only/test reset flows). The app never inserts Duova UI over a launched service.

Mandatory decisions:

- **No close X**, no close-by-tapping-outside, no native back-to-Duova navigation, no library button, no swipe-to-library gesture, no navigation drawer, no persistent address bar.
- **No edge switcher, no Liquid Glass grip, no floating Duova app menu, no quick-note shortcut, no pane-controls overlay** during a launched service. The idea is postponed, not partly visible, hidden offscreen with a hit area, or available through a secret gesture.
- No Duova header, footer, badges, logo, watermark, debugging labels, pane title bars, fake status strips or decorative chassis within the service's screen.
- The service gets the **entire app-controlled display**; its own genuine navigation remains present when the real website displays it.
- iOS system Home gesture, App Switcher, notifications and OS-controlled indicators remain available. Duova cannot and must not disable the operating system's exit paths. “No way back” means **no path to the Duova library within the app**, not trapping someone in a device application.
- When Duova goes to background, is terminated by the OS, or is reopened, **restore the launched service directly**. Do not show the Duova library as a transition, fallback or splash destination.
- If an account needs reauthentication or App Lock requires unlocking, display only the required secure authentication/unlock presentation, then resume the active service. Do not navigate to the app library.
- If the website is unavailable, show a minimal service-specific retry/reconnect state *inside* the immersive host. Do not silently return to the Duova shell. A missing network, blocked website, empty history or failed restoration is never a reason to show the library.
- Do not add an in-service settings menu for the moment. Configuration can be seeded from existing saved Duova settings or developer tools prior to launch.
- Service switching and returning to the Duova library are **explicitly out of scope** during Phase 2, despite references in Stitch. A separate future product decision may authorize them.

**Core state invariant:** Once `launchService(instagram)` commits, the production route is `immersive(instagram)` (possibly with a transient security challenge). No normal UI action transitions to `library`.

---

# 1. MISSION AND EXPERIENCE CONTRACT

Duova is not redesigning Instagram, duplicating its application, or manufacturing its content. Duova hosts the real Instagram web experience in its own fullscreen, service-specific browsing context, requests the desktop website first and optimizes available space for folding-device layouts. It should feel like a dedicated app through minimized reloading, state retention, touch responsiveness, properly sized content, native system integration and carefully scoped multi-pane browsing.

Success is defined by five user experiences: (1) launch Instagram once and see only Instagram; (2) reopen Duova and resume Instagram without passing through the launcher; (3) open real comments alongside the existing feed where supported without resetting that feed; (4) fold, unfold or rotate without starting over; and (5) have Instagram's genuine colors, styles, content, actions, accounts, ads and accessibility semantics respected.

## 1.1 First-launch and relaunch journeys

**Before first service launch:** Duova's existing sign-in, App Lock, app library, search, account screens and app detail cards remain as currently implemented. The user selects Instagram and commits to launch.

**After service launch:** the Duova application is an uninterrupted Instagram surface. There are no Duova exit, switcher or utility controls. Instagram's own web controls still work. When resumed later, the user goes directly to Instagram.

**After an OS-level close/force quit or system eviction:** Duova reconstructs the Instagram host and tries to restore the last browser route, feed anchor, contextual pane, split ratio and website session. It must accurately distinguish best-effort content restoration from guaranteed pixel-perfect DOM preservation.

**After logout or expired Duova credentials:** required account sign-in may be shown because security cannot be bypassed. Once authenticated, reopen Instagram directly; never detour via the Duova library. The Instagram site may separately ask the user to authenticate.

**If the user wants to abandon Instagram in this phase:** no in-app control exists. The user may leave the application at the OS level; this does not clear the selected service. Only a developer test reset or future approved exit mechanism may reset immersive selection. Do not invent hidden user exit gestures.

---

# 2. IMMUTABLE DESIGN AND BEHAVIOR RULES

1. **Fullscreen means no host chrome.** Native host fills the active usable display under iOS rules. Attempt status-bar hiding for the immersive controller when appropriate; accept that Apple controls system indicator visibility and gestures.
2. **Desktop-first web request.** Use WebKit desktop-preferred content mode for Instagram's actual site. If a specific route fails or misbehaves, allow a versioned, recorded compatibility fallback; do not break login to enforce desktop mode.
3. **Instagram's identity is sovereign.** Retain original fonts, brand colors, components, account names, imagery, action layouts, disclosures and site mode. Never impose Duova's blue/purple design on Instagram.
4. **The Stitch file is not an Instagram replacement.** It is a structural reference (feed + context, split ratio, posture behavior). Strip its mocked content, pretend device shell, headers, status/benchmark counters, edge rail and Duova UI from production service rendering.
5. **Keep live views alive.** No new `WKWebView` allocation on an ordinary posture change or companion-tab selection. Avoid navigation or DOM replacement when native re-layout is sufficient.
6. **Separate persistent service context.** Keep a stable website data store per Duova user and service; primary and companion panes for the *same* service may share authentication. Do not accidentally share it with another Duova account or service.
7. **No proprietary site-data synchronization.** Instagram cookies, passwords and access tokens must not be copied into Supabase or analytics. Prefer manually signing into the real website using a per-account persistent WebKit store. The existing hidden auto-login engine must not be reused as the visible host.
8. **No fake functionality.** Companion comments and DMs must come from legitimate website routes or interactions, not a copied HTML representation or fabricated API payloads. Unsupported companion actions fall back to Instagram's own single-surface behavior.
9. **Never preload destructive actions.** Do not silently click Like, Follow, Send, Publish, Delete, Mark read, purchase or permission prompts. Infinite feeds and every website page cannot be fully loaded.
10. **No secret service switcher.** All switcher/edge handle/quick notes and back-to-library functions are disabled in both visible UI and gesture/navigation routers during this phase.
11. **State is first class.** Persist the minimum safe representation of the active service, panes, routes, anchor, scroll, playback *when available*, and layout. Save before backgrounding and periodically after significant navigation, with debouncing.
12. **Secure restoration.** Authentication always gates user-specific restored state; never restore user A's cookies, routes or local snapshots when user B is signed in. Data must be account scoped, encrypted where sensitive, and scrubbed on authorized deletion.
13. **Graceful failure.** On process crash/offline, keep the immersive route and show an unbranded recovery overlay with Retry; do not expose Duova's shell.
14. **Controlled CSS and JS.** Versioned and reversible rules scoped by verified host, route, posture and tested selectors. Never broadly hide or rewrite entire pages.
15. **Verify device capabilities.** Seven postures are **design states**. Use real geometry and documented APIs, not fictional hinge sensors or fictional hardware behavior.

---

# 3. FULLSCREEN SURFACE ARCHITECTURE

The production view tree should act like this:

```
RootView
  ├─ Authentication / local unlock (only when strictly required)
  ├─ DuovaInitialLibrary (only BEFORE any service launch)
  └─ ImmersiveServiceHost(service = instagram)
       ├─ PrimaryInstagramWebView
       ├─ OptionalCompanionInstagramWebView
       ├─ Invisible native posture/layout coordinator
       └─ Conditional unbranded failure/retry layer

Not present in ImmersiveServiceHost:
  MainShell navigation, library, Duova profile/search,
  Liquid Glass edge grip, floating switcher, app rail,
  quick note button, close X, home button, back-to-library,
  pane badge/header/footer, invented status strip.
```

The immersive host must not be embedded inside `MainShell` or under a stack that exposes the shell's back action. Use a root-level mutually exclusive route or a dedicated fullscreen root presentation with the parent never visible. Handle `WKNavigationDelegate`, popups, site history and context routing within the service. The iOS browser Back action, where applicable, navigates **within Instagram's real web history only**, never to Duova's initial library. There is no system-level requirement or permission to block the user's iOS Home gesture.

The app needs a **launch commitment** state: when Instagram launch succeeds or is explicitly initiated, persist its selection atomically before routing into the host, so an immediate crash/restart cannot expose the library. A service launch still loads while the immersive host is on screen; show a neutral skeleton/loading presentation only if the website hasn't painted yet. Do not show a persistent Duova splash once the service is selected.

## 3.1 Suggested state model (design code)

```swift
import Foundation

enum DuovaRoute: Codable, Equatable {
    case initialLibrary
    case immersive(service: String)
}

struct ImmersiveRestoreState: Codable {
    var schemaVersion = 1
    var duovaAccountID: UUID
    var serviceSlug: String
    var lastPrimaryRoute: String  // verified/sanitized, not a token-bearing URL
    var lastContextRoute: String?
    var companionKind: String?
    var splitRatio: Double
    var primaryScrollY: Double?
    var primaryContentAnchor: String?
    var companionScrollY: Double?
    var lastPosture: String
    var capturedAt: Date
}
```

**Important:** These types illustrate intent. Do not store authentication tokens or arbitrary raw URLs in them. The view model must ensure it never routes from immersive to initialLibrary in production. Safe reset functionality can live only in explicit testing builds, separately from ordinary application navigation.

## 3.2 System UI and safe area

Request maximum supported immersion without hiding Instagram itself behind camera cutouts, the keyboard or gesture areas. Use iOS's fullscreen `UIViewController` preferences and SwiftUI safe-area decisions after testing. Apple's `prefersHomeIndicatorAutoHidden` can request hidden appearance but cannot guarantee it. Do not simulate a black fake status bar, a Dynamic Island or iPhone chassis in the service UI. The site should fill and harmonize with actual safe areas.

---

# 4. WEBSITE BROWSING CONTEXT, SESSION ISOLATION, AND MULTI-PANE SUPPORT

### 4.1 Store strategy

Create a persistent WebKit website-data store with a **stable identifier** derived through an account-scoped store registry for `(Duova account ID, service slug)`. Do not create a fresh random store ID on every launch. Both Instagram panes in the same account should use the *same* store to share legitimate website sign-in; different services and Duova accounts must not share store identifiers.

Prefer WebKit-managed cookie/localStorage/IndexedDB persistence, rather than serializing all cookies. An independent website account remains separate from the Duova account. On account changes, dispose of old website views and restore only the new account's store. Erasing an account's site data requires an explicit verified deletion operation.

**Do not treat an isolated website data store as a separate operating-system sandbox.** It is a managed browsing isolation boundary inside the Duova app; WebKit still follows system processes and policies.

### 4.2 Desktop-first semantics

Start with `WKWebpagePreferences.ContentMode.desktop`. Test actual site output and viewport breakpoints; some services deliberately restrict embeds, window behavior or third-party login, so add route-specific fallback instead of spoofing unsupported capabilities. The desktop layout is the **source**, not a mandate to force a tiny desktop page onto a cover display.

### 4.3 Two panes

- `Primary`: long-lived feed/video browser with its own `WKBackForwardList` and scroll anchoring.
- `Companion`: independent context browser for current comments, selected profile, Explore, DMs when available.
- Both share only the per-account/per-service website data store, not a DOM or arbitrary script state.
- Never move live DOM elements between windows. A post's comments in a second pane may need opening its *real post URL*, with limited ability to deep-focus comments depending on site support.
- If Instagram doesn't allow a context route to work simultaneously, leave a single website surface as a valid fallback; do not display fake comments or break user interactions.
- Where the site owns back/forward/browser behaviors, preserve them. No native edge-back gesture can dump the user into the Duova library.

### 4.4 WebKit factory concept

```swift
import WebKit

@MainActor
enum SocialWebViewFactory {
    static func make(using dataStore: WKWebsiteDataStore) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }
}
```

These are factory basics only. Production requires approved navigation, media and popup policies, site permission handling, file uploads, downloads, process recovery, content rule coordination, link safety and per-store lifecycle management. Store registry creation, restoration and SwiftUI/UIKit hosting are separate components.

---

# 5. INSTAGRAM SURFACES AND SOCIAL ADAPTER BASELINE

**Baseline model:** `PrimarySurface` is the main content anchor; `ContextSurface` is an optionally visible companion. The initial open/landscape configuration is Feed | Comments, only when real website routing supports it. Other contexts include Instagram's genuine DMs, selected profile, Explore and Reels. The adapter must not replace Instagram's navigation colors/icons/labels.

### 5.1 Context rules

- **Feed:** original content, Stories, scroll position, media status and navigation in primary.
- **Comments:** opening a post's native comment action can route its verified post permalink to companion while preserving the primary feed. Only add a context-pane view if real comments are available; avoid fake comment widgets.
- **Messages:** show real site DMs in companion where supported; protect message privacy and do not copy message bodies into Duova storage.
- **Profile:** selected account's actual profile URL in companion when possible.
- **Explore/Search:** real search and discovery paths; never manufacture search results.
- **Reels/Stories:** preserve aspect ratio and playback state where the browser permits it; media may still pause because of site autoplay or OS audio rules.
- **Create, settings, account security and login:** retain Instagram-owned flows, dialogs, MFA/CAPTCHA, upload controls, confirmation steps and warnings.

### 5.2 Switching contexts without Duova controls

The user does **not** see a custom Duova “Comments / DMs / Profile” native menu yet. Use Instagram's existing visible actions as context cues: tapping native comments, messages or a profile can open the relevant real route in the companion when verified. If a particular action cannot be redirected safely, let Instagram handle it normally in its own webview. We may add a visible context selector in a *future explicitly approved phase*, not in this build.

No pane header, footer, or split-ratio buttons. The engine computes ratios automatically using stored prelaunch preferences and available space. Developer/test tools can simulate ratios without appearing in production UI.

### 5.3 Interaction examples

1. User scrolls 27 posts, selects a post and opens comments: companion shows real comments; primary scroll and media remain anchored.
2. User navigates to another profile: verified actual route can reuse companion; primary isn't recreated.
3. User rotates or unfolds: webviews remain in memory, their native frames resize, no reload.
4. User backgrounds Duova mid-feed and returns: in-memory view instantly resumes if retained.
5. OS kills the web process: host stays immersive, reconstructs session and makes best-effort restoration from saved checkpoint.
6. User force-quits then reopens Duova: app returns **directly to Instagram**, never to Duova's library.
7. User performs a real site back gesture: navigate only within Instagram's page history.

---

# 6. SEVEN DUO FORMATS — FULL DESIGN CONTRACT

Seven postures are target layout states, not claims of publicly available Apple fold-sensor APIs. Determine effective layout from usable geometry, orientation, safe areas and official hardware posture signals when available. Developer tooling may force a posture in preview/test builds only.

| No. | Layout state | Primary surface | Companion policy | Fullscreen rule |
| --- | --- | --- | --- | --- |
| 1 | **Closed portrait** | Single Instagram feed fits the cover screen, with natural controls, no sideways scrolling | Native website comments/detail overlays only on demand; avoid cramped split | Entire display is Instagram; no Duova overlays |
| 2 | **Closed landscape** | Wide centered feed/Reels; sensible media aspect ratio and readable max width | Temporary context only if sufficient geometry; otherwise one website surface | No Duova chrome or exit |
| 3 | **Open portrait** | Feed uses largest comfortable region with clear reading width | Side-by-side if usable width allows; otherwise context on-demand inside website | No artificial device frame |
| 4 | **Open landscape** | Feed stable, typically ~60% of width | Real comments/profile/messages in ~40%; 50/50 or 70/30 when saved settings allow | No header or separate switcher |
| 5 | **Book / partly open** | Feed aligned to reading pane and hinge exclusion | Genuine context on opposite pane, preserving independent navigation | Content cannot sit under a physical hinge |
| 6 | **Tabletop / half-open** | Video or selected feed in upper segment | Comments/controls below where it is physically comfortable; keyboard-aware | No native toolbars |
| 7 | **Tent / standby** | One outward-facing service-focused layout, reduces visual clutter | Suspend companion until meaningful available area | Only active display shows service |

### 6.1 Layout constraints

- Layout engine uses **usable width in points**, not device marketing diagonal size.
- Starting feasibility heuristic: two panes only when usable width is roughly 760 pt or more, leaving primary at least ~390 pt and companion at least ~320 pt, after margins/gutter; tune from real test fixtures.
- Default open-landscape ratio is 60:40. Support saved 50:50 and 70:30 only where min widths hold; clamp ratios rather than forcing clipped content.
- Use a simple service-consistent separator only if needed; do not render a fake black hinge unless physical occlusion requires a safe gap.
- Account for keyboard, Dynamic Type, VoiceOver, screen zoom, orientation, split windows and system UI.
- Switching from two panes to one must **suspend/retain companion state**, not discard its URL or scroll. Returning to two panes should reconstruct the previously selected context.
- Do not resize type so much that controls become difficult to tap; keep web semantics and original appearance.
- Avoid claiming true book/tabletop/tent detection if the hardware does not publish those signals. Provide geometry-driven fallbacks.

---

# 7. ABSOLUTE STATE-REMEMBERING REQUIREMENT

**A launched service is durable application state, not a temporary screen.** State remembering is mandatory across ordinary transitions and best-effort across OS termination or website process death. There are two distinct layers:

### 7.1 Live-in-memory preservation (high fidelity)

When the app stays resident: retain the `WKWebView` instances, history, website JS process (while alive), scroll position, site SPA state and available media continuity. Reposition or resize the *same instances*. Never recreate a webview simply because the user rotates, folds, changes companion or background/foreground transitions.

### 7.2 Durable checkpoint restoration (best effort)

Save after launch and meaningful navigation, debounced while scrolling, before backgrounding and whenever the scene transitions away. Save minimally, securely and account-scoped:

| State | Storage / restoration method | Reliability |
| --- | --- | --- |
| Last active service | Encrypted local launch commitment, owner ID | Must restore routing immediately |
| Primary URL/route | Host allowlisted and sanitized local checkpoint | Best effort; website may redirect |
| Companion view and selected post reference | Approved route or opaque safe content reference | Best effort |
| Primary and companion scroll | Offset and, where permitted, stable semantic anchor/permalink | Best effort; feed ordering may change |
| Split ratio and selected layout | Local app preference with account scope | Durable |
| Fold/posture interpretation | Recompute from *current* geometry, not stale device sensor | Deterministic layout |
| Website login/session | Persistent per-account/per-service WKWebsiteDataStore | As long as website and session allow |
| Selected Story/Reel/video and playback time | Safe client-only snapshot when accessible/allowed | Best effort; OS/site can reset media |
| Unsaved comment/DM drafts | Never collect or cloud-sync by default; leave to site/browser session | Not guaranteed after process death |
| Passwords, OTPs, private messages, whole DOM | **Never** place in checkpoint/log/telemetry | Forbidden |

Store the checkpoint in existing account-scoped encrypted local storage (`SecureStore` or equivalent). Do not upload website-specific URLs, comments or session secrets to Supabase; if a future sync requirement is approved, introduce a separate privacy review and encryption policy.

### 7.3 Restore algorithm (strict order)

1. Boot app and load secure Duova session metadata, including whether a service launch was committed.
2. If no service launch was ever committed, show existing Duova library. Otherwise resolve immersive route **before creating library UI**.
3. If local lock or server-auth validation is required, gate the immersive content behind authentication; do not show library while waiting.
4. Restore the website-data store identified for the signed-in account and Instagram.
5. Create primary/companion WebViews once, request the last safe route (or official Instagram home if route is invalid); reuse running views when scene resumes.
6. Wait for actual page readiness; attempt bounded scroll/anchor restoration only on matching host and expected route. Never inject credentials or click site actions while restoring.
7. Restore companion route and selected post if supported; otherwise leave site in a usable primary view while retaining preferred companion state.
8. Apply current posture geometry and saved split ratio, avoiding new loads solely due to resizing.
9. Record `restored`, `partial`, `site_requires_login`, `offline`, or `unavailable` locally for diagnostics, without collecting private content.
10. On failure, continue displaying service-level retry UI. **Never route to Duova library** as a recovery mechanism.

### 7.4 Restoration rules for special cases

- **In-memory layout change:** zero new WebViews, zero primary page loads.
- **Background then foreground:** existing view first; only restore checkpoint if WebContent process was evicted.
- **Cold app launch:** direct-to-Instagram before network fetch; restoration then runs behind immersive loading view.
- **WebContent process terminated:** retain committed immersive route; create new page instance and restore safe checkpoint.
- **Network offline:** show offline state inside the immersive host, preserve stored checkpoint, retry when connected; never clear launch selection.
- **Instagram session expired:** use Instagram's own login path in the immersive host; preserve stored layout and safe route for post-login retry.
- **Different Duova user logs in:** never reuse previous user's website store/checkpoint; route to only that user's committed service or prelaunch library, subject to secure auth.
- **App update / adapter version changed:** migrate checkpoint fields; incompatible site routes fall back to official home within Instagram, not Duova's library.
- **Web page DOM reordered:** do not blindly scroll to stale pixel offset if doing so selects wrong content; prefer matching verified anchors and bounded fallback.
- **Crash during checkpoint:** journal/atomic-write checkpoint and retain last-known-good version.

### 7.5 Never promise impossible restoration

Websites can dynamically reorder infinite feeds; browser session data may expire, video playback can be restricted, and iOS may kill web processes. State remembering therefore has a **hard guarantee for Duova-owned route and layout metadata** and a **best-effort guarantee for remote Instagram page internals**. Communicate and test this honestly. “Same exact live pixels after force-quit” is not guaranteed for arbitrary third-party websites.

---

# 8. FAST LOADING WITHOUT ABUSE OR FAKE CONTENT

The aim is instant-feeling use, not crawling or making state-changing requests to the entire website. Preload **permitted, bounded and likely-needed** resources only.

| Band | Priority | Strategy |
| --- | --- | --- |
| P0 | Essential | Active Instagram route, authenticated WebKit store, minimum render-critical CSS, native host |
| P1 | Current context | Real selected post/comments route already needed by user; keep companion warm |
| P2 | Predictive | One likely *read-only* context, with permission and host checks; skip on constrained network |
| P3 | Lifecycle | Preserve current primary and companion WebViews while resident; intelligently suspend if pressure |
| P4 | Cold restore | Local encrypted checkpoint + standard website cache; fetch remote site only as needed |

**Forbidden:** clicking every button; crawling all posts, all pages or a person's DMs; simulating user interactions; auto-sending events; preloading unlimited videos; bypassing authentication/rate limits; persisting session cookies to Duova's cloud; querying undocumented Instagram private APIs.

Use WebKit resource caching where permitted, conditional on network/Low Data Mode/battery, and measure network requests, memory, time to first usable content, restore delay and unintended page reloads. Use a predictable limit for warm webviews and resource budgets; dynamic iOS jetsam behavior overrides our preferences. Keep first party business logic on the website.

---

# 9. STYLING, APPEARANCE AND INTERACTION DETAILS

## 9.1 What Duova may adapt

- whitespace and maximum readable column width;
- responsive grids and safe-area padding;
- non-disruptive spacing between feed and contextual pane;
- clipping/overflow improvements for the desktop page in smaller windows;
- site-consistent video sizing and aspect ratios;
- site-consistent scroll behavior and keyboard alignment;
- support for website-provided light/dark preferences, without color replacement.

## 9.2 What Duova must not change

- Instagram logo, social icons, colors, photo/video rendering, fonts or brand identity;
- user-generated content, account names, comments, follower counts, metrics and messaging;
- sponsored disclosures, security warnings, terms prompts, ads and safety/report mechanisms;
- MFA, CAPTCHA, password and account recovery steps;
- native website controls replaced with fake app-native equivalents;
- unrelated third-party websites outside reviewed hosts.

## 9.3 No host UI, even transient UI

Do not display Duova's Liquid Glass, app menu, switcher, search, profile, quick note, app list, custom pane-selector bar, ratio widget, diagnostic label or close X on the launched service. Native presentation is allowed for **OS-required permissions, keyboard, media picker, accessibility and critical retry/error states**, not for Duova navigation. No hidden swipe region or invisible hit target for the deferred menu.

## 9.4 Theme

Prefer site-native dark/light mode. If the site does not expose a stable theme control or ignores system theme, do not brute-force black/white inversion; document as a compatibility limitation rather than degrading original brand colors. Service overlays are website-owned. Native recovery/permission views adapt to system color scheme and use understated neutrals only.

---

# 10. RELIABILITY, SECURITY AND PLATFORM RULES

- Use exact official hosts / reviewed subdomains for website-specific CSS and JS; verify redirects and external authentication pages individually. Never use substring host matching.
- Route every `target="_blank"`, external scheme, file picker, camera, microphone, download, popup and associated login flow through explicit, safe WebKit delegates.
- Don't permit one account's cookies/checkpoints to be applied to another account's session.
- Do not log sensitive URLs containing tokens, code parameters, query strings, messages or account-specific records.
- Don't use screenshotting or DOM scraping to duplicate a user's private website content in Duova's servers.
- Scope `WKUserScript` injection to reviewed hosts/routes, version by adapter release; audit CSS/JS compatibility and provide kill switches.
- Keep VoiceOver reading order coherent in each posture, including hinge exclusion, keyboard focus and dynamic text; no inaccessible invisible shell gestures.
- Do not interfere with actual system Home gesture, OS app switcher or emergency/privacy controls. UIKit may request home-indicator auto-hide but cannot enforce it.
- Keep local lock/authentication functioning even if full-screen service mode is active; a mandatory security lock can temporarily supersede the website.
- Review Instagram platform policies and the Apple App Review Guidelines for third-party site use, branding and meaningful independent functionality before public release. Source feasibility does not guarantee permission to distribute.
- Keep previously identified auth deletion, keyring reset and cross-device preference conflict issues on the stabilization gate before inviting real users.

---

# 11. INTEGRATION PLAN FOR CURRENT GITHUB BRANCH

Current relevant files from the `top-navigation` review: `RootView.swift`, `MainShell.swift`, `LibraryView.swift`, `ServiceDetailView.swift`, `AppSession.swift`, `AppSignInCenter.swift`, `WebLoginRunner.swift`, `AppLoginStore.swift`, `PrivateDataCrypto.swift`, `DeviceKeyring.swift`, and backend preference/services files.

Proposed implementation ownership:

```
App/RootView.swift                      choose initialLibrary vs immersive, auth gates
App/DuovaLaunchRouteStore.swift          durable per-account immersive commitment
Immersive/ImmersiveServiceHost.swift     edge-to-edge shell; NO close or menu
Immersive/ImmersiveCoordinator.swift     identity, lifecycle, restoration, routing
Immersive/ServiceSessionRegistry.swift  stable per-account/service data-store IDs
Immersive/SocialWebViewFactory.swift     official WKWebView config
Immersive/SocialPaneCompositor.swift     same WebViews, new geometry/posture
Immersive/SocialPostureResolver.swift    seven tested layouts + geometry fallback
Immersive/ImmersiveCheckpointStore.swift encrypted local state, atomic writes
Immersive/ImmersiveRestoreEngine.swift   controlled navigation + anchor restore
Immersive/SocialNavigationPolicy.swift   safe hosts/links/popups/privacy
Immersive/SocialAdapter.swift            common site-neutral protocol
Immersive/InstagramAdapter.swift         real Instagram routes/selectors/CSS
Immersive/InstagramStyles.css            minimal, versioned, original colors
Immersive/ServiceFallbackView.swift      neutral retry, NEVER library
Tests/ImmersiveRouteTests.swift          no-back transition invariant
Tests/ImmersiveStateTests.swift          persist/reopen/crash/account isolation
Tests/SocialPostureTests.swift           all 7 modes + arbitrary widths
Tests/InstagramFixtures/                controlled local HTML fixtures
```

Integration rules:

1. Keep `MainShell` **unchanged before first service launch**; never place its navigation in the immersive view hierarchy.
2. Add a committed active-service route in `RootView`, with account-scoped encrypted persistence.
3. Launch from the existing Instagram card (or equivalent explicit action). Save commitment **before** presenting the webview.
4. Do not add a close callback or sheet-dismiss action from immersive to library. If using a modal representation, disable gesture dismissal and remove any hidden back route; a root swap is preferable.
5. Do not reuse hidden `WebLoginRunner` as the fullscreen website browser. Build a visible persistent WebKit host; disable or bypass auto-login automation for the pilot.
6. Do not add the future edge menu component, even if it already exists in a prototype. No runtime view or gesture for it in this phase.
7. Tie checkpoint ownership to current Duova account and stable service data-store ID.
8. Keep device security/authentication separate from website identity; secure unlock may occur but restore Instagram immediately after it.
9. Use fixtures before Instagram-specific live tests, and don't claim real website capabilities until verified.

---

# 12. DEVELOPMENT CHUNKS AND RELEASE GATES

| Chunk | Engineering objective | Acceptance gate |
| --- | --- | --- |
| **P2-00** | Stabilization, legal review, baseline verification | No unresolved account deletion/keyring reset data loss; adapter distribution path reviewed |
| **P2-01** | **No-return immersive root host** | After launch, no close/menu/edge/route to library; full app display; OS Home remains |
| **P2-02** | Account-scoped persistent WebKit service context | Website session persists across app relaunch where site permits; no cross-account cookie leakage |
| **P2-03** | **Durable launch and state checkpoint engine** | Force-quit/relaunch returns directly to Instagram; orientation and pane state restored best-effort |
| **P2-04** | Seven-format posture compositor | Same live primary `WKWebView` across all geometry changes; no reload due to native layout alone |
| **P2-05** | Instagram adapter | Original website identity intact, verified real routes and comments; no mock content in production |
| **P2-06** | Safe warming and performance | Only permitted read-only warm work; bounded resource budget; measured restoration delays |
| **P2-07** | Privacy, accessibility, failure recovery | Errors, offline, auth and web process crash all remain inside immersive route |
| **P2-08** | General social baseline | Reuse same engine for next eligible social service without Instagram hardcoding |

Do not skip P2-01/P2-03: fullscreen no-return behavior and remembering launched state are mandatory platform requirements, not polish items.

---

# 13. ACCEPTANCE MATRIX / DEFINITION OF DONE

For **each seven posture states**, test all of the following:

- Launch service from library; no Duova header, footer, logo, close, edge handle, app switcher or quick note appears.
- Tap screen corners, drag edges, swipe from inside the app, tap outside native website dialogs: no route opens Duova's library.
- OS Home gesture/App Switcher still work as iOS intends.
- Background then foreground: primary WebView remains live where retained; no unnecessary load.
- Kill and relaunch app: restore directly to immersive Instagram, not Duova library or app picker.
- Scroll feed deeply, open real post comments, change context if available, fold/unfold; preserve best-effort scroll/content anchor and context.
- Reorient while media plays; never recreate the primary WebView solely to change native layout.
- Simulate WebContent process termination, no internet, site login expiry, unsupported popups and route mismatch; error/retry never dumps user into library.
- Verify all layouts with long comments, landscape media, the software keyboard, accessibility features and system navigation.
- Verify session data store for account A is not visible to account B. Test removal of user data and secure lock.
- No leaked credentials, private URLs, OTP, drafts, messages or entire DOM saved to Duova backend/logs.
- No autoplay promises beyond website/OS policies and no synthetic user activity from preload engine.
- Kill-switch CSS after deliberate DOM change: original website must still work.

Additional explicit pass/fail gates:

| Requirement | Pass |
| --- | --- |
| Return to Duova library after service launch via app UI | **Impossible in production during this phase** |
| Duova floating edge menu in service | **Absent** |
| Persistence of selected service across relaunch | **Required** |
| Site session store stable and account scoped | **Required** |
| Restore of exact SPA scroll and video time after an OS kill | **Best effort and explicitly measured** |
| Instagram source branding and content fidelity | **Required** |
| Seven posture simulations and responsive fallback | **Required** |
| Safe device OS exit and accessibility | **Required** |

---

# 14. FUTURE FEATURES — EXPRESSLY NOT IN THIS PHASE

Do not add any of the following until the product owner explicitly changes this specification:

- Liquid Glass edge grip, switcher, recent-app rail or app-menu overlay in immersive service;
- swipe to return to Duova's app library;
- an X/Close/Exit Service control, navigation bar or host breadcrumb;
- global Duova quick note/ratio/view selector controls inside the active social site;
- switching from Instagram to another Duova service without leaving immersive mode;
- arbitrary whole-site prefetching or clicking every control;
- universal third-party auto-login or password autofill across uncontrolled hosts;
- copying Instagram user content into a fake Duova-designed interface;
- claims of guaranteed pixel-perfect restoration of server-controlled websites.

---

# 15. AUTHORITATIVE PRODUCT SUMMARY

**Before launch:** Duova's current library and account experience are visible.  
**At launch:** Instagram takes over the entire app-controlled display, with desktop-first WebKit and site-native styling.  
**During use:** Instagram stays immersive; adaptive one/two-pane layouts respond to all seven formats; NO Duova component or app switcher appears.  
**On close/background/restart:** Duova remembers that Instagram was launched and resumes Instagram directly, restoring safe browser state as precisely as the site and OS allow.  
**Returning to Duova:** NO in-app route exists in Phase 2. A separate future approval is required. The iOS Home gesture remains under OS control.

## Technical references
- Apple `WKWebsiteDataStore`: https://developer.apple.com/documentation/webkit/wkwebsitedatastore
- Apple `WKWebpagePreferences.ContentMode`: https://developer.apple.com/documentation/webkit/wkwebpagepreferences/contentmode
- Apple `WKNavigationDelegate`: https://developer.apple.com/documentation/webkit/wknavigationdelegate
- Apple `WKContentWorld`: https://developer.apple.com/documentation/webkit/wkcontentworld
- Apple `prefersHomeIndicatorAutoHidden`: https://developer.apple.com/documentation/uikit/uiviewcontroller/prefershomeindicatorautohidden
- Apple `prefersStatusBarHidden`: https://developer.apple.com/documentation/uikit/uiviewcontroller/prefersstatusbarhidden
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
