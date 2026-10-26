# Duova — Conversation Record

Recorded: 2026-10-26.

## Scope and provenance

This is an organized record of the conversation supplied in the project brief, including its requirements, proposals, tradeoffs, naming changes, and technical direction. It is **not a verbatim chat export**: repetitive prose, decorative wireframes, timing labels, and unavailable citation widgets are condensed. The complete extracted specification and all 240 supplied service candidates are in **DUOVA_PROJECT_BLUEPRINT.md**.

Historical names—Duo Optimizer and Paneva—are retained here to explain the discussion. The final name is **Duova**. Earlier assistant statements are historical proposals, not independently verified facts. In particular, precise iPhone Duo specifications, OS/SDK availability, named folding APIs, provider support, US rankings, and legal conclusions require primary-source verification before implementation. The referenced screenshot was not supplied as an image in this session.

## 0. Earlier workspace request

**User:** “Enable strict concurrency checking and fix issues.”

That turn was interrupted. No completed concurrency change or successful validation is established by the visible conversation. The subsequent request prioritizes documentation and a step-by-step project setup. Concurrency checking remains an engineering setup item, not a completed feature.

## 1. Initial product brief

**User request, organized from the supplied message:**

We are building an iPhone Duo application. Create two Markdown files here: one containing the conversation, the other containing the extracted full project breakdown. Do not build the app yet; fully break it down so its UI elements can be designed.

The product is a quick iPhone Duo optimizer for the website versions of applications, where available. It should not feel like a website. Hide redundant browser-like headers and search bars, and rethink each service as though designed for Duo from the beginning. Optimize both the small phone screen and expanded layouts.

In Split View, users should be able to select secondary content such as messages or comments. The experience should be much more sophisticated than a simple website wrapper.

The first screen is login. After that, show a searchable list of services. Selecting a service makes the entire experience become that app. Returning to the library might use a three-finger pull-back or another gesture rather than a persistent back button.

The experience must be smooth and seamless. Load a service when selected, perhaps preparing the first ten at startup. Recently searched/opened apps should appear at the top in a story-like rail, with the remainder listed alongside or below.

Security comes first. Encrypt everything possible. Every service should be isolated in its own sandbox so other services cannot access it. Use the service's own authentic logo.

Use shared category styling: Social Media, Streaming, Activity, Maps/Food, Fashion, Other, and Productivity. Other should include Hinge, StreetEasy, Zillow, and similar services. Include Google Docs, Slides, Sheets, Excel, and other productivity tools. Put category filters at the top. Identify thirty popular US apps for each category. Account for services without websites.

Include a Suggest an App button collecting its name and website link.

Use caching and persistent login to make repeated sign-in unnecessary where possible. Support multiple instances with different services, such as Instagram and TikTok, but do not allow two independent Instagram instances inside Duova.

Add a small corner button for quick notes. Notes should also be available through Settings. Settings should include name, email, profile, encrypted passwords that the team cannot see, startup app selection, and other preferences.

Support Siri commands such as “Hey Siri, open Duo Instagram.”

Later, an AI engine should accept a website URL and automatically help optimize it. Ship the baseline first; AI is future scope.

### Earlier wrapper explanation included in the brief

An earlier answer described the concept as a Dashboard Web-Wrapper or Multi-Tab WebView Portal: a self-contained browser environment built with WKWebView. It proposed custom CSS to suppress redundant headers and adapt layouts, native code to respond to device configuration, and persistent cookies/tokens.

It noted that web versions may lack native features: TikTok recording, filters, and drafts; Instagram Stories and Reels upload behavior; and other native-only operations.

It also raised App Store minimum-functionality concerns for mere wrappers and suggested unique functionality such as productivity tools and notes. A statement about informal distribution referred to an unspecified Apple framework and is not an actionable distribution plan.

## 2. Assistant proposal: Complete Product Blueprint

### 2.1 Product direction

The assistant proposed a native application environment, with a launcher that disappears once the user enters a service. Six pillars:

1. One searchable, organized library.
2. Device-adaptive service experiences.
3. Configurable primary and secondary workspaces.
4. Private sessions and protected local data.
5. Session continuity and fast switching.
6. Manually engineered adapters followed later by AI assistance.

The historical response asserted a 7.6-inch inner display at 1878 × 2670 and a 5.4-inch outer display at 1398 × 2034. It claimed support for closed, open, landscape, seated, standing, hinge-responsive, and multi-scene arrangements. Those are preserved as historical claims only; the supplied citation labels contain no URLs and are not evidence.

It recommended native SwiftUI controls around supported website workflows; a separate persistent WebKit data store per service; persistent login subject to expiry; and OS scenes for multiple application windows.

It explicitly said that complete native functionality across 240 third-party services cannot be guaranteed. Some services would be optimized, some limited, and others native handoff only.

### 2.2 Application structure

Proposed permanent destinations: Apps, Workspaces, Settings.

Apps contains search, category filters, recent services, favorites, and suggestions. Workspaces contains active and saved sessions. Settings contains profile, security, passwords, notes, appearance, and preferences.

Inside a service, permanent Duova navigation disappears. Native tools remain available through a discreet control. An app adapter, private session, and native tool layer support each experience.

### 2.3 Screen inventory

The response enumerated 45 primary screens/states:

01 Splash; 02 Welcome; 03 Create account; 04 Login; 05 Recovery; 06 Security setup; 07 Onboarding; 08 Preferences; 09 Permission education; 10 Compact library; 11 Expanded library; 12 Search; 13 Category results; 14 App detail; 15 Launch transition; 16 Compact app; 17 Expanded app; 18 Dual-pane app; 19 Secondary-view picker; 20 Pane editor; 21 System Split View; 22 Book-fold mode; 23 Tabletop mode; 24 Floating switcher; 25 Workspace overview; 26 Saved workspaces; 27 Third-party sign-in; 28 Service permission request; 29 Compatibility fallback; 30 Offline/reconnect; 31 Quick note; 32 Notes library; 33 Note editor; 34 Suggest an app; 35 Submission confirmation; 36 Settings; 37 Profile; 38 Password vault; 39 Vault entry; 40 Privacy/security; 41 Per-app settings; 42 Appearance/gestures; 43 Storage/performance; 44 Siri/shortcuts; 45 Help/diagnostics.

Shared overlays cover errors, expired authentication, network loss, failed uploads, unsaved work, security notices, and compatibility changes.

### 2.4 Library

Compact order: header; native local-first search; horizontal category filters; recent rail of 8–12 services; pinned/favorite apps; virtualized list; Suggest an App.

Filters: All, Social, Streaming, Activity, Maps, Food, Fashion, Productivity, Other. Favorites is an additional virtual grouping rather than an optimization category.

Recent tiles use authentic authorized logos and an active indicator. Tap resumes; long-press exposes actions. No automatic animated previews.

Expanded proposal: category sidebar, central list/search, optional right-side app information and launch panel. Optional preview selection and direct launch were discussed; drag-to-panel was an enhancement. Extra space should show useful information rather than inflate rows.

### 2.5 Launch and exit

Launch: resolve adapter and workspace ownership; restore session and route; show native launch shell; attach retained or newly created content; apply verified adaptation; reveal usable content.

A three-finger gesture cannot be the only exit. The response proposed a small corner handle, optional long-press, optional gesture, keyboard shortcut, Siri action, and accessibility action.

Command palette: Library, Split, Switch, Quick Note, App Settings, Close. Opening it should not reload the service.

### 2.6 Device layouts

Compact: one focused view; sheets for secondary content; condensed controls.

Expanded: primary canvas and configurable companion panel.

Book: keep controls and text away from system-reported reserved regions.

Tabletop: main media/document above, contextual controls below if supported.

Narrow system scene: collapse the internal split and remember it for restoration.

Also cover standing/tent arrangements if supported, compact landscape, keyboard appearance, PiP, external/mirrored display privacy, Dynamic Type, and fold/unfold continuity.

The response named ArrangementView, UIArrangementViewController, and reserved-region APIs. Their actual availability and contracts must be verified against the installed SDK before use.

### 2.7 Split views and scenes

Secondary choices depend on the adapter:

- Social: Feed, Messages, Comments, Notifications, Profile, Saved.
- Productivity: Document, Files, Comments, Outline, Formula Help, Presenter Notes.
- Streaming: Player, Queue, Episodes, Subtitles, Chat.
- Maps/Food: Map, Results, Details, Directions, Cart, Tracking.

Suggested ratios: 60/40 default, 50/50 and 70/30 presets, adjustable divider where supported. Include swap, focus, linked selection, persisted preferences, and unavailable-state handling.

Share state within one service when possible; use another web document only when necessary.

One service owns one independent workspace per Duova account within the local app installation. Two Instagram panels in that workspace are allowed. Another scene requesting Instagram should focus or transfer the existing workspace. This does not constrain the official Instagram app outside Duova.

The earlier assertion that new scenes are available only on Duo's inner display requires verification.

### 2.8 Category design systems

Eight real optimization categories were defined:

- Social: content feed with communication/detail companion.
- Streaming: media with queue, episodes, chat, or notes.
- Activity/Fitness: metrics/workout with plan, map, or history.
- Maps/Travel: map/itinerary with results, details, booking.
- Food/Delivery: restaurant/menu with cart/order tracking.
- Fashion/Shopping: product browsing with filters, details, comparison.
- Productivity: working canvas with files, comments, tools.
- Other: real estate, dating, events, services, communities.

Favorites was described as a ninth grouping, not a ninth integration category.

Provider-specific restrictions include unavailable private messaging APIs, DRM and background playback, native health/sensor integrations, navigation safety, accurate checkout totals, and unsupported complex document editing.

### 2.9 Performance, caching, sessions

Startup should load native shell and metadata, not ten complete WebViews.

Cache layers proposed: in-memory UI state; persistent app registry; icon/image cache; per-app route/layout metadata; isolated WebKit data; a small live-view cache; encrypted user notes/vault/preferences.

Suspend nonessential rendering, avoid idle polling, respond to memory pressure and WebKit termination, preserve safe state, and never treat disposable cache as the only copy of notes.

Initial targets: cached library within one second; retained workspace switch within 250 ms; 60 fps; no third-party WebViews at library startup. A later technical response tightened the switch target to 200 ms and added local search under 100 ms. These were targets, not measured results.

Separate Duova authentication from provider authentication. Preserve provider sessions subject to expiry, account security, and supported login mechanisms. The response raised Google embedded-OAuth restrictions and the need for system authorization where supported, without assuming cookies automatically transfer.

### 2.10 Security

Per-service persistent website data stores are a storage boundary, not a new hardware sandbox. Enforce origin restrictions, navigation rules, scoped permissions, and a minimal native bridge.

Proposed protections:

- TLS/HTTPS and authenticated backend APIs.
- Authenticated encryption for sensitive app-owned records.
- Keychain and appropriate hardware-backed key protection.
- No secrets in JavaScript/local storage.
- Separate service profiles.
- Registered domains and validated redirects.
- Typed, limited bridge messages with origin validation.
- Reviewed/versioned scripts with isolated execution where suitable.
- User-driven clipboard/file/permission actions.
- Sensitive preview masking.
- Redacted logs and telemetry.
- Passkeys, app lock, device revocation.
- Audited vault and recovery design.
- Distinct cache, sign-out, and deletion controls.

The response clarified that rendered/edited content necessarily exists as plaintext in memory. “Everything encrypted” cannot mean plaintext never exists.

Notes should be encrypted locally; future end-to-end sync needs client-held keys and explicit recovery. Vault design included add/edit, generation, search, reveal/copy authentication, auto-lock, clipboard policy, duplicates, app associations, import/export, and recovery explanation. Automatic scraping of website passwords was rejected.

### 2.11 Notes, Siri, personalization, suggestions

Quick Note: small corner action, lightweight composer, autosave, title, tags, search, pinning, export, optional workspace association. Attach URLs/excerpts only through explicit user action. Notes accessible in Settings and switcher.

Siri examples: open Instagram in Duova; open TikTok; show workspaces; open notes; resume writing workspace. Actual supported phrases depend on App Intents/App Shortcuts.

Per-app preferences: default route, companion panel, ratio, resume behavior, compact navigation, theme, accessibility, media, cache, permissions, shortcut.

Suggestion form: app name, website URL, category, optional requested optimization. Validate URL; reject unsafe schemes; prevent unsafe server fetching; rate limit; acknowledge request and expose status. Submission must not execute arbitrary scripts.

### 2.12 The 240-service catalog

The response supplied 30 candidates in each of eight categories, reproduced completely in the blueprint. It described these as US-market priority candidates rather than an exact download ranking. Historical chart claims and “App Store +8” labels do not establish a current ranking or verified web compatibility.

Category prototype sets:

- Social: Instagram, TikTok, Reddit, Discord, WhatsApp.
- Streaming: YouTube, Spotify, Twitch, Netflix, Plex.
- Activity: Strava, MyFitnessPal, AllTrails, Peloton, Cronometer.
- Maps: Google Maps, Airbnb, Booking.com, Uber, FlightAware.
- Food: DoorDash, Uber Eats, Yelp, OpenTable, Starbucks.
- Shopping: Amazon, Depop, SHEIN, Zara, StockX.
- Productivity: Google Docs, Google Sheets, Gmail, Notion, Microsoft Excel.
- Other: Zillow, StreetEasy, Hinge, Tinder, Eventbrite.

Later productivity candidates: Microsoft To Do, Miro, Obsidian, Box, Adobe Acrobat, Linear.

### 2.13 Compatibility governance

Statuses: Full optimization, Enhanced web, Limited web, Native handoff, Under review, Unsupported.

Separate technical compatibility from permission/licensing status. Each catalog record needs canonical ID/name/category, aliases, authorized assets, official URLs and allowed hosts, login method, native fallback, supported/unsupported capabilities, layouts/panels, session/cache rules, permissions, OS/app minimums, adapter version, verification date, known defects, and terms/approval status.

A homepage rendering successfully is not sufficient for full optimization.

### 2.14 Ten reference service flows

1. Instagram: feed/Reels, comments/messages/profile; linked comment panel retains feed position.
2. TikTok: video/comments/profile/search/following; comments must not restart playback.
3. Google Docs: file list/editor/formatting/comments/share/save/conflicts; preserve cursor and unsaved work where provider allows.
4. Excel: workbook/worksheet/cell/formula/range/filter/save; preserve selected cell and editing context.
5. YouTube: home/player/fullscreen/Shorts/subscriptions/playlists/comments; avoid media recreation.
6. Google Maps: map/search/routes/place/saved/permissions; retain map viewport.
7. DoorDash: discovery/menu/customization/cart/address/checkout/result/tracking; preserve cart and provider payment flow.
8. Zillow: map/list/filter/detail/photo/saved/contact; linked selection without resetting search.
9. Hinge: discovery/profile/match/chat/verification/privacy; native fallback unless a permitted web workflow is established.
10. Spotify: home/search/library/player/queue/playlist/reconnect; prevent competing playback instances.

### 2.15 Settings

Profile: name, email, image, verified methods, account creation, devices, passkeys, export, sign-out, deletion.

Security Center: authentication setup, biometric lock, trusted devices, encryption configuration health, credential changes; never show raw keys.

Personalization: layouts, gestures, appearance, startup route, app defaults.

Tools/Data: notes, Siri, storage/cache, notifications.

Support: help, suggestions, about.

Separate clear temporary cache, clear website data, reset layout, remove favorite, and delete local account data. Explain whether an operation signs the user out.

### 2.16 Architecture

Native Swift application, SwiftUI plus targeted UIKit, WKWebView, adaptive layouts/scenes, persistent service profiles, versioned adapters, restricted bridge, local database, CryptoKit/Keychain, supported account authentication, App Intents, signed catalog/configuration delivery, minimal backend, privacy-filtered monitoring.

Modules: shell/scene coordinator; registry; layout; workspace; sessions; security; native tools; adapter runtime.

Do not blindly hide all website search/navigation. Replace redundant controls only when functionality remains available. Preserve consent, payments, privacy, identity, and required disclosures. Disable transformations when selectors or expected structure fail.

### 2.17 Recovery and accessibility

Specify offline launch, server failure, expired login, terminated web process, fold/unfold, duplicate scene requests, memory pressure, broken adapter, blocked client, offline editing, payment transitions, large text, and unknown permissions.

Support Dynamic Type, VoiceOver, Switch Control, keyboard navigation, Reduce Motion, adequate touch targets, contrast, focus restoration, captions, accessible exit, and left/right floating-control placement. Essential controls cannot depend on a complex gesture.

### 2.18 Future AI

Validated URL intake → permitted structure discovery → category classification → adaptation proposal → functional/accessibility/security tests → human review → signed/versioned rollout and rollback.

Components: validator, structure analyzer, component mapper, layout recommender, compatibility analyzer, accessibility analyzer, responsive/regression test runner, versioning service, review UI, compatibility scoring.

AI cannot create provider permission, bypass login restrictions, or safely grant arbitrary generated code privileged native access.

### 2.19 Distribution and permissions

The historical response cited App Store minimum functionality, third-party content/brand permissions, and terms compliance, with possible additional hosted-software requirements depending on review classification. Those are review topics, not a guarantee of acceptance or a current legal opinion.

Native workspaces, notes, and adaptation are intended product value. Use authentic authorized branding and clearly identify Duova as independent.

### 2.20 Release and design handoff

Phases: product foundation → adaptive engine → validated adapters → security/performance hardening → public baseline → future AI.

Handoff: screen map, tokens, geometry rules, library/workspace components, eight templates, ten service journeys, authentication/security UI, notes, settings, compatibility states, error states, accessibility, motion, responsive prototypes, acceptance tests.

Baseline acceptance: persistent Duova login; fast cached library; local search/filter; isolated service storage; no cross-service native-data access; distinct service scenes where supported; duplicate prevention; continuity across resizing; no unintended submissions; saved notes protected; broken-adapter fallback; encrypted notes/vault; valid Siri routing; gesture-free exit; truthful compatibility labels.

Initial six design flows: login/library/launch; Instagram communication/switch; Docs compact/expanded; Maps/detail/resume; distinct-service scenes; quick note/settings/library.

## 3. User: naming and per-app customization

**User:** “hmm I need a better one word name for this. Also these can be customizable per app. Duo Layouts. Appearance & Gestures...”

### Assistant response

Recommended Paneva, “Every app. Your way,” from pane + evolve. Alternatives: Duova (duo + nova), Morflo (morph + flow), Plyzo (fold-inspired), Veyra (minimal/premium), Flexta (flexible layouts). Names were creative suggestions, not trademark clearance.

Suggested shorter settings names: Layouts and Personalize.

Global defaults with per-app overrides:
- Layout modes: single, split, adaptive.
- Preferred primary/secondary views and ratio.
- System/light/dark appearance where supported.
- Gesture assignments and floating-control location.
- Changes in Instagram do not affect TikTok.
- Reset to global defaults.
- Persist across relaunch and resizing.
- Optional named presets: Reading, Messaging, Focused, Multitasking.

## 4. User: technology, speed, and service loading animations

**User:** “now lets talk technology what is the best option for these, what should I write the code in fully, what should I do... What frameworks or data store should I use.. I want instant loading fast things.,.. please. ... Also I want to use the apps loading animations too as well,”

### Assistant response: native technology architecture

Recommended native Swift, SwiftUI, targeted UIKit, and WebKit. The response preferred native development over React Native/Flutter/Electron for this product's platform integration; this was a product recommendation, not a claim those alternatives are incapable.

Proposed stack:
- Swift 6, SwiftUI, UIKit.
- WKWebView.
- Geometry-driven layout, with claimed Duo APIs subject to SDK verification.
- SQLite + GRDB.
- CryptoKit, Keychain, Data Protection.
- Swift async/await and actors.
- SwiftUI/Core Animation; optional licensed Rive/Lottie.
- Go HTTP API.
- PostgreSQL.
- Object storage/CDN.
- App Intents and App Shortcuts.
- Instruments and MetricKit.

Swift owns shell, account, scenes, layouts, notes, vault, Siri, caching, and native security. Reviewed CSS/JavaScript supports individual website adapters. Go handles Duova backend concerns. Do not rebuild private provider APIs or proxy all service traffic through Duova servers.

### WebView management

Central manager; views should not be created/destroyed by routine SwiftUI body recomputation.

States: Unloaded, Loading, Active, Warm, Suspended; later Restoring was added.

Starting budget: one active primary document, a second only when a verified split needs it, up to one recent warm workspace when resources permit. Budget is adaptive, shared across scenes, and measured on device.

Stable per-service profile UUIDs map to separate persistent stores. Two panels of one service may share that store. Strict Docs/Sheets isolation can require separate provider sign-ins; do not silently pool provider cookies.

### Startup and performance

Native shell → local catalog/favorites/recents → cached icons → lightweight first ten records → asynchronous catalog update → service selection → retained view or isolated new load → content ready.

Storage mappings: catalog/search/favorites/recents/preferences in SQLite; FTS5 proposed for search; encrypted notes/vault separately; cookies/cache managed by WebKit; active pages retained in live WebViews; adapters cached/versioned; animations bundled locally.

Targets: cold cached library under one second, local search under 100 ms, retained workspace switch under 200 ms, 60 fps. Measure p95 on supported hardware; provider first-render time has no universal guarantee.

Avoid ten startup WebViews, view recreation on redraw, reload on fold, cache clearing on switch, background playback for all services, large recent-preview images, UI-blocking sync, idle JavaScript polling, and full-site backend proxying.

### Original loading animations

Three distinct cases:

1. Website loader: preserve it where appropriate.
2. Native provider animation: cannot simply extract it from an installed app; use approved assets/rights.
3. Duova transition: authorized service icon plus lightweight Duova-owned motion.

Warm services should appear directly. Cold load: immediate native surface → load → readiness check → roughly 150 ms crossfade as a starting design value → failure UI if needed. No fixed branding delay.

WebKit estimated progress is not proof a JavaScript application is usable. Use bounded adapter readiness checks and timeout/fallback. Avoid multiple simultaneous loaders.

### Databases

Separate public catalog from protected user records. Proposed SQLite/GRDB for explicit queries, migrations, transactions, and FTS5. Consider whole-file encryption such as SQLCipher only after integration/key-management review; sensitive note/vault payloads still need an intentional protection design.

Suggested tables: apps, categories, app_categories, app_capabilities, app_adapters, favorites, recent_apps, workspaces, workspace_panels, app_preferences, app_session_profiles, notes, vault_entries, sync_queue, schema_migrations.

Never copy raw cookies into profile metadata. Never index encrypted notes into a plaintext search table. Search notes after authorized decryption initially.

The response preferred GRDB's explicit control to SwiftData for this architecture, while acknowledging SwiftData is suitable for simpler apps.

### Backend

One Go service using net/http or chi, managed PostgreSQL, object storage/CDN, TLS, rate limits, monitoring, and supported authentication.

Functions: accounts/devices, sessions, catalog versions, adapters, suggestions, compatibility updates, optional encrypted sync, rollout flags.

No microservices or Redis initially without measured need. Supabase/Firebase were acknowledged as alternatives; custom Go + managed PostgreSQL was preferred. Backend availability must not gate cached library access.

### Scenes and configuration

Distinguish internal split panes from system-managed windows. An owner registry resolves duplicate launches by focusing the existing service scene.

Example Instagram settings:
- Compact single; expanded split.
- Feed primary, Messages secondary, 60/40.
- System theme, motion enabled, bottom-right control.
- Resume on launch; custom switcher action.
- Warm resume enabled; WebKit-managed cache.

Security and accessibility constrain preferences. Resolve user per-app overrides, service defaults, category defaults, global defaults. The later blueprint clarifies inheritance and precedence.

### Adapters

Category template + service-specific verified adapter + user preferences → rendered workspace.

Review CSS/JS, validate bridge messages, constrain origins/capabilities, version adapters, and provide kill switch/rollback. Some services remain native/browser handoff only.

### Security details

Keychain account tokens, rotating credentials, audited vault encryption, AES-GCM note payloads, protected private storage, service profiles, HTTPS/ATS, password hashing rather than reversible backend password storage if password login is introduced, client-side sync key design, no bridge vault access, redacted logs, privacy previews, passkeys, scoped deletion.

Do not claim app-level AES-GCM covers WebKit's every cookie or cache entry. WebKit/iOS manage those protections.

### Proposed module organization

App: app entry, coordinator, scenes.
Core: auth, security, networking, database, cache, performance.
Engine: WebViews, sessions, workspaces, layouts, adapters, navigation policy, ownership.
Features: onboarding, library, search, categories, workspaces, notes, vault, settings, suggestions, Siri.
DesignSystem: components, typography, motion, themes, loaders.
Adapters: eight categories.
Resources: authorized icons, local catalog, animations.
Tests: security, isolation, performance, layouts, adapter regression.
Backend: API, auth, catalog, suggestions, compatibility, database, operations.

### Development order

Native shell → isolated two-service proof → switching/suspension/restoration → adaptive geometry/scenes/customization → account/protected storage → verified adapters.

Tools proposed: Xcode, physical supported device, Instruments, Git/GitHub, Figma, Swift Package Manager, Swift Testing/XCTest as appropriate, UI automation, TestFlight.

The first technical milestone is two authorized isolated services, persistent sessions, fast retained switching, and compact/expanded adaptation.

## 5. User: immersion, top tabs, standby, and switching tradeoffs

**User request, organized:**

I like the direction but want Duova to become the selected app. First login, then library/filter/search, then enter the service. Is full immersion better than persistent app-switching UI at the top? I like both. Services should retain standby behavior after leaving. Alternatively, should opening a new app discard state and require another app instance? Weigh both and decide. The referenced current design is conceptual.

### Assistant response: final UX direction

Combine both with full-screen immersion as the default and an instantly accessible switcher.

| Choice | Strength | Weakness |
| --- | --- | --- |
| Full-screen service | Immersion, maximum space, good compact experience | Switching needs discoverable control |
| Permanent app tabs | Fast visible switching | Occupies space and feels like a browser |
| Immersion plus floating switcher | Preserves both goals | Requires careful discovery/accessibility |

Login → library → immersive service → hidden quick switcher.

After successful authentication, default to the last active service; allow library or chosen-service startup preferences.

### State strategy

| Strategy | Benefit | Cost |
| --- | --- | --- |
| Destroy on every switch | Low resource use | Reloads and lost context |
| Keep every service running | Fast return while retained | High memory/battery; OS may terminate |
| Adaptive retention and restoration | Good continuity with bounded resource use | More lifecycle engineering |

Decision: adaptive resume and restoration. Preserve safe state rather than intentionally discarding it.

Active, Warm, Suspended, Restoring distinguish actual live retention from recoverable metadata. Third-party drafts and media buffers are not universally restorable.

Standby does not mean indefinite execution. OS suspension/termination remains authoritative. Website sessions do not automatically supply the native app's push notifications/background services.

### Controls and scenes

Discreet edge handle opens recents, Library, Notes, Layouts. Optional tabs on expanded layouts. Respect system gesture zones and accessibility.

- Tap another service: switch while retaining/restoring prior service where feasible.
- Open in New Window: supported OS scene request.
- Tap already-open service: focus/resume owner.
- Library: return to catalog.
- Close workspace: release resources, retain sign-in unless user signs out.
- Resize/fold: adapt without intentionally resetting.

Allow different services in different supported scenes. No duplicate independent service workspace.

### Background scenarios

Short return: attach retained live workspace.
Long return: restore service/route/layout and reload if needed.
OS termination: reconstruct protected saved metadata.
Force quit: preserve durable state, but no promise of ongoing work or unsaved third-party draft recovery.
New window: use supported OS scene activation.
Expired auth: supported reauthentication with safe return.

### Settings proposed

Startup: last app, library, chosen app.
Switcher: discreet edge handle, gesture with accessible fallback, optional expanded tabs.
Session preference: adaptive, favor recent readiness, favor lower memory/battery. These are preferences, not retention guarantees.

The key product rule: Duova appears when choosing, switching, customizing, or managing; the selected service owns the main experience while in use.

## 6. Final naming and execution instruction

**User:** “note from now call the app duova.. I changed the name.. to duova.”

**User:** “So I'm ready to start, first steps to set up... we will set up each service as needed.. we will go throug it step by step.”

### Current interpretation

- Final name: Duova.
- Create documentation before implementation.
- Preserve full product scope for design.
- Proceed incrementally; introduce external services only when the feature needs them.
- Do not install the whole proposed stack or implement 240 integrations at once.
- Retain strict concurrency as a pending setup requirement from the earlier interrupted request.
- Start with project/toolchain verification, native shell planning, and a small isolated-service proof.
- The companion blueprint is the normalized specification; earlier proposals remain traceable here.
