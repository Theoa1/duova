# Duova — Product, Design, and Engineering Blueprint

Version: 0.1 — planning baseline  
Date: 2026-10-26  
Status: Specification; application features not yet implemented  
Conversation provenance: DUOVA_CONVERSATION.md

## 1. Product definition and scope

**Duova is a native launcher and adaptive workspace for compatible web services.** Users sign in to Duova, find a service, and enter an immersive experience designed around available screen space. The selected service becomes the main interface. Duova remains available for switching, layout changes, notes, privacy, and settings.

The product targets the user's iPhone Duo vision, including compact and expanded use. Device-specific features must be established from the installed SDK and primary documentation before implementation. Do not hard-code historical screen dimensions, hinge geometry, OS versions, or scene restrictions from the pasted discussion.

### Confirmed product direction

- Public name: **Duova**. Paneva and Duo Optimizer are historical names.
- Native iPhone application.
- First-use authentication, followed by a searchable categorized library.
- Immersive service mode with no permanent Duova header or browser address bar.
- Accessible discreet switcher; optional expanded-mode tabs.
- Configurable secondary content per supported service.
- Global defaults with independent per-app customization.
- Persistent service sessions subject to provider expiry.
- Adaptive warm retention and restoration, rather than intentional state destruction.
- Multiple different service workspaces; no conflicting duplicate workspace for the same service.
- Quick notes and a Settings-accessible notes library.
- Strong service separation and protection of app-owned sensitive data.
- Authentic authorized service branding.
- Eight integration categories and 240 research candidates.
- Suggestions by app name and website.
- Siri/Shortcuts integration when implemented.
- AI-assisted adaptation is future scope.
- Build incrementally, setting up external services only when needed.

### Proposed decisions requiring implementation validation

SwiftUI/UIKit/WebKit; SQLite/GRDB; CryptoKit/Keychain; Go/PostgreSQL; scene management; optional whole-database encryption; exact support for fold-related APIs; authentication provider; account recovery model; vault release timing.

These are architecture recommendations, not installed dependencies or completed integrations.

### Explicit limits

Duova cannot promise permanent provider login, all native app features, continuous background execution, arbitrary provider push notifications, guaranteed recovery of unsaved third-party drafts, universal DRM playback, or native-speed cold loading of every website.

Do not advertise a service as supported merely because it appears in the candidate catalog. No service has been compatibility-certified by this document.

## 2. Experience principles

1. **Immersion:** choosing happens in Duova; working happens in the service.
2. **Continuity:** preserve the current task through switching and resizing whenever technically supported.
3. **Local responsiveness:** library, search, preferences, and saved native notes do not wait for third-party servers.
4. **Capability honesty:** expose only verified routes, panels, and actions.
5. **Isolation:** service data and privileges remain scoped.
6. **Accessible control:** essential actions always have a visible/discoverable non-gesture path.
7. **Progressive complexity:** compact mode stays focused; expanded mode adds useful information.
8. **User control:** settings changes in one service do not unexpectedly alter another.
9. **Recoverability:** every loading, auth, storage, and adapter failure has a defined recovery state.
10. **No artificial delay:** never slow the app to display a branded loader.

## 3. Navigation and primary journey

### First use

Launch → Welcome/Login → account authorization → optional security setup → brief library introduction → App Library → service details if needed → service authentication → immersive workspace.

Permission requests occur when the corresponding feature is used, not in an up-front permission barrage.

### Returning use

Launch → unlock if required → preferred destination:
- Resume last service (default after a successful session).
- Open Library.
- Open a chosen service.

If restoration fails, retain a responsive native shell and offer retry, library, or supported handoff.

### Library navigation

Keep **Apps** and **Settings** as the primary visible destinations. Workspace management is always available through the switcher. An expanded navigation layout may expose **Workspaces** as a third destination; it must not make the compact launcher unnecessarily complex.

### Immersive navigation

Hide library tabs, category controls, and Duova title on service launch.

Keep a small reachable handle for:
- Recent services and active workspaces.
- Library.
- Secondary-panel selection and layout.
- Quick Note.
- Current service settings.
- Close workspace.

A gesture is optional. VoiceOver action, keyboard command where supported, and ordinary tap access remain available. Never make a three-finger gesture the sole exit.

### Interaction comparison and final choice

| Mode | Appropriate use | Decision |
| --- | --- | --- |
| Full-screen service | Compact and immersive workflows | Default |
| Floating switcher | Fast switching with minimal chrome | Default switching mechanism |
| Persistent top tabs | User prefers visible switching on a wide scene | Optional per-app/expanded setting |
| Destructive switch | Explicit reset requested by user | Never ordinary switching behavior |

## 4. Authentication and login design brief

This is the first UI design task.

### Login composition

- Duova wordmark and restrained product statement.
- Primary supported account sign-in action.
- Sign in with Apple and passkey flows are candidates; show only implemented options.
- Clear account-creation/recovery path.
- Privacy and terms access.
- Accessible spacing, keyboard handling, large text, and light/dark treatments.
- No imitation provider login form.

### Required states

Initial, authorizing, canceled, success, network unavailable, service unavailable, credential rejected, account recovery, revoked session, account deletion completion, and device unlock required.

Disable duplicate submissions during authorization. Preserve non-sensitive form data after recoverable errors. Never display success until authentication succeeds.

### Identity boundaries

Duova account and third-party service accounts are different. Signing into Duova does not sign into Instagram or Google.

Face ID is a local unlock/authorization mechanism, not a substitute for account authentication or recovery.

Use provider-supported authorization flows. System browser authorization does not imply its cookies can be copied into an embedded WKWebView. Each integration must prove a supported post-authentication path.

### Design acceptance

Login is understandable without a tutorial, accessible with large text/VoiceOver, recovers from cancellation, and proceeds to the library. Returning users do not unnecessarily see login.

## 5. App Library design

### Compact layout

1. Small Duova header and Settings/profile access.
2. Native search field.
3. Category filter row at the top.
4. Recent-services rail.
5. Favorites/pinned services.
6. Searchable list of available services.
7. Suggest an App action, including in empty search results.

### Filters

All · Social · Streaming · Activity · Maps · Food · Fashion · Productivity · Other.

Favorites and Recently Used are virtual filters. They do not create additional adapter categories.

### Search

Search locally by canonical name, aliases, category, and favorites. Clearly distinguish:
- No matching name.
- Matching service under review.
- Unsupported service.
- Available service.
- Offline but cached catalog.

Recent searches and recently opened services are distinct histories. The story-like rail defaults to **recently opened** for predictable resumption; a search screen can show recent search terms.

### Recent rail

8–12 entries, authorized logos, readable labels, active-state indicators. Tap resumes; long-press/context menu provides open, details, favorite, and settings. No automatic third-party previews.

### App row

Official logo, service name, category, compatibility status, favorite/active indicators as appropriate. Do not display all 240 research candidates as launchable.

### Expanded layout

Optional category sidebar → central catalog/search → app details/preview pane when space allows. Primary launch should remain a predictable single explicit action. A preview mode may be offered, but avoid requiring double-taps for normal navigation.

### App details

Capabilities, unavailable features, authentication expectations, verified layouts, required permissions, last compatibility check, independent-product disclosure, launch/handoff action.

## 6. Full screen and state inventory

These are 45 primary design surfaces, not 45 mandatory independent navigation destinations. Shared components should handle repeated states.

| ID | Surface | Content and important states |
| --- | --- | --- |
| 01 | Splash | Minimal native launch appearance; no fixed delay |
| 02 | Welcome | Value proposition; sign-in/create-account entry |
| 03 | Create account | Supported identity method; validation; cancellation |
| 04 | Login | Authorizing; failure; recovery; success |
| 05 | Recovery | Verification, unavailable recovery, completion |
| 06 | Security setup | Passkey/app-lock choices; explanation; deferred setup |
| 07 | Onboarding | Launch/switch/layout explanation; accessible alternatives |
| 08 | Preferences | Favorite services/categories; optional skip |
| 09 | Permission education | Purpose, scope, allow/deny; actual system request on use |
| 10 | Compact library | Search, filters, recents, favorites, list |
| 11 | Expanded library | Sidebar/catalog/details; responsive collapse |
| 12 | Library search | Query, recent terms, results, empty/offline states |
| 13 | Category results | Selected filter, count, sorting, no matches |
| 14 | Service detail | Verified capabilities, limitations, launch/handoff |
| 15 | Launch transition | Warm immediate display; cold progress; retry |
| 16 | Compact service | Focused content; condensed navigation; switcher handle |
| 17 | Expanded service | Main canvas; optional companion content |
| 18 | Dual-pane service | Context link, focus, divider, pane identity |
| 19 | Secondary-view picker | Available choices only; unsupported explanation |
| 20 | Pane editor | Ratio, swap, close companion, reset |
| 21 | Narrow/system split scene | Collapse internal split; preserve configuration |
| 22 | Book arrangement | Only if supported; safe geometry and reading order |
| 23 | Tabletop arrangement | Only if supported; content and controls |
| 24 | Floating switcher | Recents, library, notes, layout, close |
| 25 | Workspace overview | Active/warm/suspended state; focus/close |
| 26 | Saved workspaces | Named presets, edit, remove, unavailable service |
| 27 | Provider sign-in | Supported official flow; cancellation and expiry |
| 28 | Service permission | Service identity, requested capability, deny/revoke |
| 29 | Compatibility fallback | Limited mode, safe web, browser/native handoff |
| 30 | Offline/reconnect | Cached shell; retry; no false save claim |
| 31 | Quick note | Text, title, autosave status, optional app link |
| 32 | Notes library | Search, tags, pinned notes, locked/empty states |
| 33 | Note editor | Edit, save, export, delete, conflict if sync exists |
| 34 | Suggest an app | Name, URL, category, optional request |
| 35 | Suggestion result | Submitted, duplicate, failed, retry, review status |
| 36 | Settings overview | Account, personalization, security, tools, support |
| 37 | Profile | Name/email/image, identity methods, devices, deletion |
| 38 | Vault | Locked/unlocked list; add/search; recovery information |
| 39 | Vault entry | Add/edit/reveal/copy/delete with protection |
| 40 | Privacy/security | App lock, device sessions, privacy controls |
| 41 | Per-app settings | Layout, appearance, gestures, permissions, storage |
| 42 | Appearance/gestures | Defaults, conflicts, accessible fallback, reset |
| 43 | Storage/performance | Per-service usage; distinct cleanup operations |
| 44 | Siri/Shortcuts | Supported actions, examples, locked/failure behavior |
| 45 | Help/diagnostics | Compatibility reports; redacted diagnostics; about |

Shared overlays: load error, auth expiry, failed upload, unsaved-work warning, storage full, denied permission, broken adapter, unsafe navigation, app update required, active service elsewhere, deletion confirmation, unsupported capability.

## 7. Adaptive layout matrix

Use actual scene dimensions, safe areas, keyboard geometry, accessibility requirements, and supported platform capabilities. Device name alone must not decide layout.

| Situation | Primary behavior | State that should survive |
| --- | --- | --- |
| Compact | Single pane; secondary content in sheet/navigation | Route, selection, app-owned drafts |
| Expanded | Primary canvas plus selected companion if suitable | Selection, scroll where supported, layout |
| Narrow OS scene | Collapse internal split; keep companion choice | Both pane routes and preference |
| Compact landscape | Reduce chrome and adapt height | Active input and media where possible |
| Keyboard visible | Keep input and actions visible | Caret/selection when provider supports |
| Large Dynamic Type | Collapse columns if needed | Focus and navigation |
| Book posture, if supported | Respect reported reserved areas | Linked pane selection |
| Tabletop posture, if supported | Main content plus reachable controls | Playback/editor continuity |
| Standing/tent, if supported | Appropriate media/read-only layout | Playback, explicit privacy rules |
| External/mirrored display | Supported presentation only | Sensitive content privacy |
| Background return | Resume retained or restore saved workspace | Safe durable metadata |
| Process termination | Recreate view and service profile | No promise of unsaved web DOM recovery |

Never move important controls over a system-reported obstruction. Do not invent a hinge angle or query private APIs.

### Split controls

Default proposal: 60/40, with 50/50 and 70/30 presets. Enforce minimum readable pane widths. Provide swap, focus, close companion, restore, and accessible resize alternatives.

Some “companion panels” may be native; others may require a second provider web document. A service must prove the latter works without duplicate submissions, conflicting navigation, or redundant media playback.

### Continuity contract

Preserve app-owned notes and preferences durably. Preserve provider route/scroll/selection only where reliable and allowed. For unsaved third-party content, show accurate status and avoid eviction where practical; never claim a durable save based only on a visible editor.

## 8. Workspace, scene, and session lifecycle

### Independent concepts

- **Service:** canonical catalog entry, such as Instagram.
- **Profile:** persistent isolated website-data identity for that service and Duova account.
- **Workspace:** one service's current task and pane configuration.
- **Pane:** primary or secondary view within a workspace.
- **Scene:** an OS-managed Duova window.
- **Saved preset:** a configuration, not a captured authenticated page.

### State machine

Unloaded → Loading → Active → Warm → Suspended → Restoring → Active.

Failure states include load failure, authentication required, unsupported, and adapter disabled. Closing releases live resources; signing out additionally clears relevant authentication according to explicit user intent.

### Ownership policy

One independent workspace per canonical service per local Duova account. Two panes in that workspace are allowed. Multiple scenes may own different services.

Registry updates must be atomic. Two simultaneous launch requests must resolve to one owner. If an owner disappears, reconcile stale records before opening another.

Focus existing owner when supported; otherwise provide a recoverable move/resume path. Never assume the OS will grant a new scene request.

This policy does not prohibit using the official provider app or the same service on another device. Multi-account support within one provider is not baseline scope.

### Retention policy

Start with one primary live WebView, a second only when required by the active layout, and at most one recent warm workspace when memory permits. Treat this as a provisional global resource budget, not a fixed per-window allocation.

Avoid background polling and hidden autoplay. Active media/editor behavior needs a deliberate policy. Memory pressure evicts nonessential views first.

### Restoration record

Store account/service/profile IDs, adapter version, safe route if permitted, primary/secondary choices, ratio, scene association, timestamp, and non-sensitive restoration hints.

Do not persist passwords, raw cookies, arbitrary web DOM, private message text, or opaque URL query secrets in ordinary workspace records.

### Background scenarios

| Event | Required result |
| --- | --- |
| Briefly leave Duova | Return to retained active workspace if available |
| Return after long inactivity | Restore profile/route/layout; reload if needed |
| OS kills web process | Recreate content safely; avoid replaying submissions |
| OS kills Duova | Reconstruct protected durable state |
| Force quit | Durable state remains; no background-execution promise |
| Provider session expires | Reauthenticate through supported flow |
| Open another service | Preserve prior safe state; do not intentionally reset |
| Close workspace | Release rendering resources; retain sign-in profile |
| Sign out of provider | Clear that provider's local session as supported |
| Sign out of Duova | Lock/disassociate local account data per explicit policy |

## 9. Category design templates

| Category | Compact pattern | Expanded companion | Main constraints |
| --- | --- | --- | --- |
| Social | Feed/video/chat | Messages, comments, profile | Private API limits, uploads, privacy |
| Streaming | Player and transport controls | Queue, episodes, chat | DRM, subscriptions, playback capability |
| Activity & Fitness | Summary/workout/plan | Metrics, history, route | Sensitive health data; no implicit sensor access |
| Maps & Travel | Map or itinerary | Results, route, booking | Accurate location, provider booking behavior |
| Food & Delivery | Restaurants/menu/order | Cart, tracking | Prices, fees, consent, payment integrity |
| Fashion & Shopping | Catalog/product | Filters, comparison, details | Variants, inventory, cart consistency |
| Productivity | Document/canvas/inbox | Files, comments, tools | Editing fidelity, unsaved work, collaboration |
| Other | Workflow-specific | Listing/chat/event/provider details | Sub-template and provider verification |

### Shared template requirements

Each category defines spacing, navigation conventions, loading/error treatment, pane-selection patterns, and common accessibility behavior. It does not define a universal stylesheet to inject into all services.

Other sub-templates: real estate, dating, events/tickets, home services/pet care, communities.

Native health, sensor, notification, camera, location, payment, and file permissions remain individually scoped. A website must not inherit privileged native functionality merely because its category suggests it.

## 10. Complete 240-candidate catalog

**Research backlog, not verified support and not a current US top-30 ranking.** The supplied discussion selected these candidates. Numbers below are identifiers within each list, not popularity ranks. Official URLs, current branding, US availability, web capability, provider terms, and market evidence must be researched before publication.

Every row begins **Under review**. Companion views are design hypotheses only. A provider without a permitted usable website gets a truthful handoff/unsupported outcome.

### Social — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | Instagram | Feed + Messages/Comments |
| 2 | TikTok | Video + Comments |
| 3 | Snapchat | Conversations + available web content |
| 4 | Facebook | Feed + Messenger |
| 5 | Threads | Feed + Replies |
| 6 | X | Timeline + Post/Replies |
| 7 | Reddit | Subreddit + Comment thread |
| 8 | Pinterest | Boards + Pin details |
| 9 | LinkedIn | Feed + Messaging |
| 10 | WhatsApp | Conversations + Chat |
| 11 | Facebook Messenger | Chat list + Conversation |
| 12 | Telegram | Chats + Conversation |
| 13 | Discord | Servers/channels + Chat |
| 14 | Signal | Messaging; web capability unverified |
| 15 | Bluesky | Feed + Thread |
| 16 | BeReal | Feed + Post details |
| 17 | Tumblr | Dashboard + Post |
| 18 | Nextdoor | Neighborhood feed + Details |
| 19 | WeChat | Messaging; possible native handoff |
| 20 | LINE | Messaging; possible native handoff |
| 21 | GroupMe | Groups + Conversation |
| 22 | Viber | Messaging; possible native handoff |
| 23 | Lemon8 | Feed + Post details |
| 24 | Clapper | Video + Comments |
| 25 | Mastodon | Timeline + Conversation |
| 26 | Quora | Questions + Answers |
| 27 | Substack | Publication + Article/Discussion |
| 28 | Locket | Native-first; web capability unverified |
| 29 | Letterboxd | Films + Reviews/Diary |
| 30 | Skool | Community + Discussion |

Prototype archetypes: Instagram, TikTok, Reddit, Discord, WhatsApp.

### Streaming & Entertainment — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | YouTube | Player + Recommendations/Comments |
| 2 | Netflix | Player + Episodes |
| 3 | Amazon Prime Video | Player + Watchlist |
| 4 | Disney+ | Player + Series details |
| 5 | Hulu | Player + Episodes |
| 6 | HBO Max | Player + Related content |
| 7 | Peacock | Player + Series guide |
| 8 | Paramount+ | Player + Episodes |
| 9 | Apple TV | Player + Watchlist |
| 10 | YouTube TV | Player + Channel guide |
| 11 | Tubi | Player + Discovery |
| 12 | Pluto TV | Live player + Guide |
| 13 | Twitch | Stream + Live chat |
| 14 | Kick | Stream + Chat |
| 15 | Crunchyroll | Player + Episodes |
| 16 | Spotify | Now Playing + Queue |
| 17 | Apple Music | Now Playing + Library |
| 18 | SoundCloud | Player + Tracks |
| 19 | Pandora | Player + Stations |
| 20 | iHeartRadio | Player + Stations |
| 21 | Audible | Audiobook + Chapters |
| 22 | Amazon Music | Player + Playlist |
| 23 | ESPN | Live content + Scores |
| 24 | DAZN | Stream + Event information |
| 25 | Fubo | Stream + Channel guide |
| 26 | Sling TV | Stream + Guide |
| 27 | Plex | Player + Library |
| 28 | The Roku Channel | Player + Discovery |
| 29 | ReelShort | Short drama + Episodes |
| 30 | DramaBox | Short drama + Episode selector |

Prototype archetypes: YouTube, Spotify, Twitch, Netflix, Plex. Test playback/DRM on target hardware before designing guaranteed playback features.

### Activity & Fitness — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | Strava | Activity feed + Route |
| 2 | MyFitnessPal | Daily log + Nutrition |
| 3 | AllTrails | Trail map + Details |
| 4 | Planet Fitness | Workout + Club details |
| 5 | Peloton | Class + Workout information |
| 6 | Fitbit | Dashboard + Activity history |
| 7 | Garmin Connect | Activities + Metrics |
| 8 | Oura | Daily metrics + Trends |
| 9 | Flo | Calendar + Insights |
| 10 | Yuka | Product details + History |
| 11 | Cal AI | Food log + Analysis |
| 12 | Cronometer | Diary + Nutrients |
| 13 | Noom | Daily plan + Progress |
| 14 | WeightWatchers | Food log + Progress |
| 15 | Headspace | Session + Program |
| 16 | Calm | Session + Library |
| 17 | LADDER | Workout + Exercise details |
| 18 | Fitbod | Workout + Exercise reference |
| 19 | ClassPass | Classes + Booking |
| 20 | Apple Fitness+ | Native capability review required |
| 21 | Nike Run Club | Runs + Coaching |
| 22 | Nike Training Club | Workout + Instructions |
| 23 | Zwift | Activity + Session metrics |
| 24 | BetterMe | Plan + Progress |
| 25 | Finch | Goals + Check-in |
| 26 | RISE | Sleep dashboard + Analysis |
| 27 | StepsApp | Steps + History |
| 28 | Sweat | Workout + Plan |
| 29 | EōS Fitness | Club + Workout |
| 30 | WeWard | Steps + Rewards |

Prototype archetypes: Strava, MyFitnessPal, AllTrails, Peloton, Cronometer. Do not assume browser availability of wearable/health data.

### Maps & Travel — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | Google Maps | Map + Place details |
| 2 | Apple Maps | Map + Results |
| 3 | Waze | Route + Trip details |
| 4 | Google Earth | Globe + Place information |
| 5 | MapQuest | Map + Directions |
| 6 | HERE WeGo | Map + Routes |
| 7 | Uber | Ride selection + Trip |
| 8 | Lyft | Ride options + Trip |
| 9 | Waymo | Ride interface + Trip |
| 10 | Airbnb | Search + Listing |
| 11 | Booking.com | Hotels + Room selection |
| 12 | Expedia | Trip results + Booking |
| 13 | Hotels.com | Hotel list + Property |
| 14 | Priceline | Listings + Details |
| 15 | Tripadvisor | Destinations + Reviews |
| 16 | KAYAK | Search + Trip options |
| 17 | Skyscanner | Flights + Details |
| 18 | Hopper | Prices + Planning |
| 19 | Turo | Vehicles + Listing |
| 20 | Getaround | Cars + Booking |
| 21 | Amtrak | Schedule + Trip |
| 22 | American Airlines | Flights + Trip |
| 23 | Delta Air Lines | Trips + Flight details |
| 24 | United Airlines | Flights + Trip |
| 25 | Southwest Airlines | Flights + Check-in |
| 26 | JetBlue | Flights + Trip |
| 27 | Marriott Bonvoy | Hotels + Reservations |
| 28 | Hilton Honors | Hotels + Stays |
| 29 | FlightAware | Flight map + Status |
| 30 | Rome2Rio | Route map + Transport choices |

Prototype archetypes: Google Maps, Airbnb, Booking.com, Uber, FlightAware. Independently verify booking, check-in, location, payment, and live navigation.

### Food & Delivery — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | DoorDash | Restaurants + Cart/Tracking |
| 2 | Uber Eats | Menu + Cart |
| 3 | Grubhub | Restaurants + Order |
| 4 | Instacart | Groceries + Cart |
| 5 | McDonald's | Menu + Order |
| 6 | Starbucks | Menu + Order/Rewards |
| 7 | Chick-fil-A | Menu + Order |
| 8 | Taco Bell | Menu + Cart |
| 9 | Chipotle | Customization + Cart |
| 10 | Dunkin' | Menu + Rewards |
| 11 | Domino's | Pizza builder + Order |
| 12 | Burger King | Menu + Offers |
| 13 | Wendy's | Menu + Cart |
| 14 | Subway | Sandwich builder + Order |
| 15 | Pizza Hut | Menu + Cart |
| 16 | Little Caesars | Menu + Order |
| 17 | Wingstop | Menu + Cart |
| 18 | Panda Express | Menu + Order |
| 19 | Panera Bread | Menu + Cart |
| 20 | Popeyes | Menu + Order |
| 21 | Dutch Bros | Drinks + Rewards |
| 22 | 7 Brew | Drinks + Rewards |
| 23 | Yelp | Listings + Reviews |
| 24 | OpenTable | Restaurants + Reservation |
| 25 | Resy | Restaurants + Availability |
| 26 | Toast | Restaurants + Order |
| 27 | Too Good To Go | Available food + Pickup |
| 28 | Caviar | Restaurants + Cart |
| 29 | Sweetgreen | Menu + Customization |
| 30 | Crumbl | Menu + Order details |

Prototype archetypes: DoorDash, Uber Eats, Yelp, OpenTable, Starbucks. Never hide required fees or alter checkout semantics.

### Fashion & Shopping — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | Amazon Shopping | Products + Details/Cart |
| 2 | Walmart | Results + Item details |
| 3 | Target | Products + Cart |
| 4 | SHEIN | Catalog + Product |
| 5 | Temu | Products + Cart |
| 6 | Vinted | Listings + Item |
| 7 | Depop | Feed + Listing |
| 8 | Poshmark | Listings + Seller |
| 9 | Mercari | Products + Item |
| 10 | eBay | Search + Listing |
| 11 | Etsy | Products + Shop |
| 12 | Shop | Discover + Tracking |
| 13 | Whatnot | Live sale + Listings |
| 14 | AliExpress | Catalog + Cart |
| 15 | ASOS | Products + Filters |
| 16 | Zara | Catalog + Product |
| 17 | H&M | Collection + Item |
| 18 | Uniqlo | Collection + Details |
| 19 | Nike | Products + Details |
| 20 | Adidas | Products + Details |
| 21 | StockX | Item + Market prices |
| 22 | GOAT | Sneaker listing + Details |
| 23 | Farfetch | Designer catalog + Details |
| 24 | SSENSE | Catalog + Product |
| 25 | Fashion Nova | Products + Cart |
| 26 | Nordstrom | Items + Details |
| 27 | Macy's | Products + Filters |
| 28 | Sephora | Products + Reviews |
| 29 | Ulta Beauty | Products + Reviews |
| 30 | Quince | Catalog + Item |

Prototype archetypes: Amazon, Depop, SHEIN, Zara, StockX.

### Productivity — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | Google Docs | Document + Comments/Outline |
| 2 | Google Sheets | Spreadsheet + Formula/Sheets |
| 3 | Google Slides | Slide + Speaker notes |
| 4 | Google Drive | Files + Preview |
| 5 | Gmail | Inbox + Message |
| 6 | Google Calendar | Calendar + Event |
| 7 | Microsoft Word | Document + Comments |
| 8 | Microsoft Excel | Spreadsheet + Sheet/Formula tools |
| 9 | Microsoft PowerPoint | Slides + Notes |
| 10 | Microsoft OneDrive | Files + Preview |
| 11 | Microsoft Outlook | Inbox + Message |
| 12 | Microsoft Teams | Chats/channels + Content |
| 13 | Microsoft OneNote | Notebooks + Page |
| 14 | Notion | Navigation + Page |
| 15 | Slack | Channels + Conversation |
| 16 | Zoom | Meeting + Chat/Participants |
| 17 | Dropbox | Files + Preview |
| 18 | Trello | Board + Card |
| 19 | Asana | Projects + Task |
| 20 | Airtable | Records + Record details |
| 21 | ClickUp | Tasks + Details |
| 22 | monday.com | Board + Item |
| 23 | Canva | Design + Assets |
| 24 | Figma | Canvas + Layers/Comments |
| 25 | ChatGPT | Conversation + Related context |
| 26 | Claude | Conversation + Artifacts |
| 27 | Google Gemini | Conversation + Related work |
| 28 | Apple Pages | Document + Comments; web compatibility review |
| 29 | Apple Numbers | Spreadsheet + Tables; web compatibility review |
| 30 | Apple Keynote | Slides + Notes; web compatibility review |

Prototype archetypes: Google Docs, Google Sheets, Gmail, Notion, Excel. Later candidates: Microsoft To Do, Miro, Obsidian, Box, Adobe Acrobat, Linear. Do not confuse a native-only tool with an embeddable editor.

### Other — 30

| # | Service | Proposed companion |
| --- | --- | --- |
| 1 | Zillow | Property map + Listing |
| 2 | StreetEasy | Listings + Property |
| 3 | Redfin | Map + Listing |
| 4 | Realtor.com | Listings + Home |
| 5 | Apartments.com | Listings + Apartment |
| 6 | Trulia | Map + Listing |
| 7 | Homes.com | Properties + Details |
| 8 | HotPads | Rental map + Details |
| 9 | Zumper | Listings + Property |
| 10 | Rent.com | Apartments + Details |
| 11 | Hinge | Discovery + Conversations, if permitted |
| 12 | Tinder | Discovery + Matches/Chat |
| 13 | Bumble | Discovery + Chat |
| 14 | OkCupid | Profiles + Conversation |
| 15 | Match | Discovery + Messages |
| 16 | eHarmony | Matches + Conversations |
| 17 | Plenty of Fish | Discover + Messages |
| 18 | Coffee Meets Bagel | Matches + Conversation |
| 19 | Badoo | Discovery + Chat |
| 20 | Happn | Discovery + Conversation |
| 21 | Grindr | Discovery + Conversations |
| 22 | HER | Profiles + Chats |
| 23 | Feeld | Discovery + Chat |
| 24 | Eventbrite | Events + Tickets |
| 25 | Partiful | Events + Guest information |
| 26 | Ticketmaster | Events + Tickets |
| 27 | Meetup | Groups + Events |
| 28 | Thumbtack | Providers + Quotes |
| 29 | Taskrabbit | Services + Booking |
| 30 | Rover | Caregivers + Booking |

Prototype archetypes: Zillow, StreetEasy, Hinge, Tinder, Eventbrite. Native verification, anti-abuse systems, ticket presentation, and permitted web access must be evaluated individually.

### Ranking research procedure

Before calling anything “top 30 in the USA,” define metric (downloads, active users, revenue, or editorial priority), source, category mapping, geographic scope, and capture date. Custom categories do not directly map to store categories. Retain evidence per candidate. If sources do not support thirty ranked entries, publish “priority candidates” rather than invent rankings.

## 11. Compatibility and provider onboarding

### Status taxonomy

| Status | Meaning | Launch action |
| --- | --- | --- |
| Under review | No completed capability/permission assessment | Details or request updates |
| Full optimization | Defined important journeys verified | Adapted workspace |
| Enhanced web | Usable website plus tested improvements | Enhanced workspace |
| Limited web | Known significant limitations | Explain before launch |
| Native handoff | Embedded experience unsuitable | Supported official app/browser |
| Unsupported | Unsafe, unavailable, or not permitted | Explanation; no false launch |

Maintain independent technical, security, branding, and permission statuses. “Full” always refers to explicitly listed supported workflows, not parity with every native capability.

### Per-service record

Stable ID; canonical name; category; aliases; US availability evidence; official website/native link; approved logo provenance; allowed origins/subdomains; auth mechanism; supported routes; panels; unsupported actions; permissions; cache behavior; profile identity; layout constraints; min OS/app version; adapter version; last tested date; test evidence; known defects; fallback; licensing/terms review; rollout state.

### Onboarding sequence

1. Verify official identity, URLs, and service availability.
2. Review permission/terms and branding.
3. Test authentication in target environment.
4. Test essential journeys without transformations.
5. Implement minimum safe adaptation.
6. Test pane behavior, forms, uploads, checkout, accessibility, and restoration.
7. Verify profile and bridge isolation.
8. Record limitations and readiness.
9. Controlled rollout with rollback.
10. Reverify after provider or SDK changes.

No login bypass, hidden consent acceptance, ad/payment manipulation, or use of private APIs.

## 12. Ten detailed reference designs

These are design archetypes, not a promise that each is technically launchable.

| Service | Screens to design | Continuity test | Fallback |
| --- | --- | --- | --- |
| Instagram | Feed, Reels, post, comments, messages, profile, search, upload | Opening comments preserves feed; changing pane preserves task | Unsupported upload/panel disclosed |
| TikTok | Feed, comments, creator, search, following, share | Comments do not restart/advance video | Playback/recording limitation |
| Google Docs | Files, editor, toolbar, comments, share, save/conflict | Resize preserves editing context where supported | Safe official editor handoff |
| Excel | Workbooks, sheets, cells, formula, ranges, filters, save | Selected cell/formula preserved where supported | Unsupported editing explanation |
| YouTube | Home, player, fullscreen, Shorts, subscriptions, playlist, comments | Pane changes avoid unnecessary player recreation | Player/provider restriction |
| Google Maps | Search, map, places, routes, saved, location permission | Details preserve map viewport and search | Supported browser/native route |
| DoorDash | Discovery, menu, customization, cart, address, checkout, tracking | Cart and selections remain consistent | Official checkout/handoff |
| Zillow | Search, filters, map, list, photos, saved, contact | Selection does not reset map/filter | Safe web mode |
| Hinge | Discovery, match, profile, chat, verification, privacy | Only verified permitted workflows | Native handoff by default until proven |
| Spotify | Home, search, library, player, queue, playlist, reconnect | One intended playback source | Provider playback limitation |

## 13. Per-app settings and inheritance

### Groups

**Layouts:** single/split/adaptive, primary route, companion choice, ratios, compact behavior, preferred expanded arrangement.

**Personalize:** system/light/dark where supported, typography preferences, motion, gesture assignment, floating-control location, switcher style.

**Startup:** resume, home route, designated destination; service must support the route.

**Performance:** adaptive retention preference, media behavior, storage controls.

**Permissions:** camera, microphone, location, files, notifications only if implemented; clear scope and revocation.

### Resolution model

Start with global defaults → category defaults → verified service defaults → explicit user global preferences → explicit user per-app overrides. Apply capability constraints, security policies, and system accessibility requirements as final restrictions.

Persist whether a property is inherited or explicitly overridden. Do not copy global defaults into every service and then lose inheritance. Reset restores inheritance, not a stale snapshot.

### Presets

Reading, Messaging, Focused, Multitasking are examples. A preset stores configuration, not authenticated content. Preview effect; apply to selected service; reset individual fields or all overrides.

A requested unavailable panel should fall back predictably and explain why.

## 14. Native notes

### Quick Note

Small corner action opens a sheet/overlay while preserving the service. Editable title and text, autosave indicator, optional tags and service association, explicit save/close.

Only attach page URL or selected excerpt when the user asks. Strip or reject sensitive URL parameters where appropriate. Website scripts cannot read native notes.

### Notes library

Settings → Notes, also accessible from switcher. Search after unlock, pinned notes, tags, app association, create/edit/delete, intentional export. Include empty, locked, save-failed, storage-full, and recovery states.

### Durability

Persist encrypted drafts promptly. Distinguish saved locally from synchronized. On failure retain editable content and show a visible error. Never rely solely on a live web view or clipboard.

### Sync

Local-only baseline is acceptable. Optional later sync requires key/recovery/conflict/deletion design. Do not claim end-to-end encryption unless the server cannot decrypt and the recovery design preserves that property.

## 15. Vault and account security UI

The vault belongs in the full design scope but is a separate audited implementation workstream.

Required designs: lock/unlock, list/search, add/edit entry, generated password, reveal/copy, biometric failure, auto-lock, delete, export/import warning, recovery state.

Prefer supported system password/passkey facilities in the baseline. A custom password manager must not be rushed to satisfy a settings mockup. If deferred, omit nonfunctional controls from shipped UI and clearly record the milestone.

Never scrape credentials from provider login pages. Never expose vault reads through the web bridge.

User-presence requirements, app-lock timeout, clipboard behavior, key loss, device migration, cloud recovery, and data deletion need explicit decisions before implementation.

## 16. Settings information architecture

| Group | Pages and operations |
| --- | --- |
| Account | Name/email/photo, identity methods, devices, export, sign out, deletion |
| Layouts | Global defaults, per-service overrides, saved presets |
| Personalize | Theme, motion, gestures, switcher, control placement |
| Security | App lock, trusted devices, sessions, privacy controls |
| Passwords | Vault only when securely implemented |
| Notes | Search, organize, edit, export |
| Siri & Shortcuts | Available actions and examples |
| App Preferences | Startup app, resume rules, defaults |
| Storage | Per-service usage and distinct cleanup actions |
| Notifications | Only supported notification sources; no parity claim |
| Support | Help, compatibility reports, suggestions, diagnostics, about |

### Destructive and cleanup actions

- **Clear temporary cache:** disposable resources; avoid cookie deletion, explain if provider state may still be affected.
- **Clear website data:** cookies/storage may be removed; reauthentication expected.
- **Reset layout:** only Duova configuration.
- **Remove favorite:** only launcher organization.
- **Close workspace:** release live resources.
- **Sign out of service:** provider session cleanup.
- **Delete notes/vault/account data:** explicit scope and confirmation.
- **Delete Duova account:** Duova-owned data and device policy; not deletion of provider accounts.

Do not put these behind an ambiguous “Clear All.”

## 17. Loading and motion

### Warm launch

Attach retained content immediately. Do not replay a splash just to show branding.

### Cold launch

Native surface with authorized service logo → create isolated view → load → bounded readiness assessment → reveal → remove overlay. The website's own loader can continue naturally.

### Original provider animations

Use the actual website loader or separately licensed supplied assets. Do not extract native-app animations or imply Duova is the provider. Fallback is Duova-owned motion around authorized branding.

### Motion rules

Bundle launch assets, avoid heavy dependencies for simple animation, honor Reduce Motion, use quick transitions without fixed delay. About 150 ms crossfade is a prototype parameter, not a requirement.

Estimated navigation progress is not interactivity. Adapter readiness must have a timeout and safe recovery. Show real loading state rather than fabricated percentages.

## 18. Performance and caching

### Startup pipeline

Native shell → local catalog/favorites/recents → cached authorized icons → first visible metadata → asynchronous catalog refresh. Instantiate third-party content only after deliberate launch.

### Cache layers

| Layer | Contents | Ownership |
| --- | --- | --- |
| UI memory | Current selection/navigation | Duova |
| Catalog | Names/categories/capabilities/search | Duova; replaceable |
| Assets | Authorized icons/animations | Duova; versioned |
| Workspace metadata | Safe routes/layout/ownership hints | Protected Duova data |
| Website data | Cookies/storage/HTTP cache | WebKit-managed per-service profile |
| Warm views | Live rendered service | Volatile and resource-bound |
| Notes/vault | Sensitive encrypted payloads | Durable protected user data |

Private website pages, messages, and authentication data must not be copied into a generic Duova cache.

### Provisional measurement budgets

| Metric | Target | Measurement condition |
| --- | --- | --- |
| Cached library interactive | Under 1 second | p95 on supported hardware, offline catalog |
| Local search feedback | Under 100 ms | Representative full catalog |
| Retained service switch | Under 200 ms | View already resident and ready |
| Navigation/scrolling | Aim for 60 fps or appropriate display cadence | Instruments and real device |
| Third-party WebViews on library startup | Zero | No user-selected service restoration |

Auto-resuming a chosen service is a distinct path and may create its view. Do not treat that as library preloading.

Measure cold/warm launch separately, memory by scene, energy, CPU, web process termination, network requests, and privacy-safe adapter failures. Do not log page text or auth-bearing URLs.

## 19. Security architecture and threat boundaries

This section specifies design requirements; it is not a claim of completed security review.

### Threat model

Untrusted provider pages, injected third-party scripts, compromised adapters, malicious suggested URLs, phishing redirects, bridge misuse, accidental cross-service data sharing, leaked logs/backups, lost devices, and interrupted writes.

### Boundaries

Native trusted shell; individual service data stores; restricted script bridge; protected account/notes/vault repositories; backend API; adapter distribution channel.

### Required protections

| Area | Requirement |
| --- | --- |
| Network | HTTPS/TLS, normal trust validation, no silent insecure downgrade |
| Backend access | Authentication, per-user authorization, rate limits |
| App tokens | Keychain with deliberate access class/revocation |
| Notes/vault payloads | Authenticated encryption and safe key lifecycle |
| Keys | Keychain; appropriate hardware-backed protection where supported |
| Data at rest | iOS Data Protection plus app-owned encryption as designed |
| Website profiles | Separate stable stores; no shared default store by accident |
| Bridge | Minimal typed operations, verified origin/frame, no generic file/secret access |
| Navigation | Parsed URLs, approved origins, deliberate external handoff |
| Permissions | User action, purpose, per-service policy and revocation |
| Logs | No passwords, cookies, private content, or sensitive URLs |
| Backups | Explicit key/data restore behavior and exclusion policy |
| Previews | Mask sensitive scene snapshots where feasible |
| Clipboard | User-triggered; avoid unsafe delayed overwrite of newer clipboard data |
| Account deletion | Clear scope, key destruction policy, backend/device cleanup |
| Adapters | Reviewed versioning, integrity checks, rollback, kill switch |

### Important encryption distinctions

Plaintext exists while data is displayed or edited. WebKit manages website storage; do not claim Duova applies AES-GCM to every provider cookie/cache file. Secure Enclave is not a general-purpose database for arbitrary symmetric keys.

A Keychain-protected encryption key is not automatically an end-to-end encryption design. Recovery, migration, sync, and backups determine who can decrypt.

Do not claim complete isolation at a hardware/process level from separate cookie stores alone. iOS/WebKit manage process sandboxing; Duova must prevent sharing through its own bridge and repositories.

### Account separation

A second Duova account on the same device must not inherit another account's service profiles, notes, or preferences. Profile mapping needs account scope. Define logout behavior before adding account switching.

### Sensitive operation policy

No automatic purchases, hidden form submissions, silent consent acceptance, credential extraction, or automated replay of payment requests during restoration.

## 20. Technology architecture

### Recommended baseline, introduced as needed

| Layer | Proposed choice | Setup timing |
| --- | --- | --- |
| Language | Swift, verified toolchain version | Foundation |
| Native UI | SwiftUI | Foundation |
| Targeted integration | UIKit | When SwiftUI integration requires it |
| Web rendering | WKWebView | Isolation proof |
| Concurrency | async/await, actors, main-actor UI | Foundation |
| Catalog/persistence | SQLite + GRDB | First durable repository |
| Private payload protection | CryptoKit + Keychain + Data Protection | Before saving sensitive data |
| Whole-file encryption | Evaluate SQLCipher integration | Only if required by data model |
| Native motion | SwiftUI/Core Animation | Shell/design |
| Voice | App Intents/App Shortcuts | After routing is stable |
| Backend | Go, one deployable API | Real account/suggestion service |
| Server database | Managed PostgreSQL | Backend persistence |
| Static assets | Object storage/CDN | Remote assets/catalog |
| Diagnostics | Instruments, MetricKit where appropriate | Early performance work |
| Tests | Swift Testing and UI automation | Alongside meaningful behavior |

No need to create cloud accounts, deploy infrastructure, install animation libraries, or add Redis during documentation/design.

### Swift concurrency plan

The earlier request to enable strict concurrency remains pending.

At foundation setup:
1. Inspect actual Swift language mode and build settings.
2. Enable complete strict concurrency where applicable; Swift 6 language mode enforces its concurrency rules.
3. Keep UI and WebKit interactions on their required actor.
4. Use actors or otherwise explicit isolation for mutable registry/persistence coordination.
5. Pass Sendable value snapshots across isolation boundaries.
6. Use structured tasks, cancellation, and lifecycle ownership.
7. Fix diagnostics rather than suppressing them with broad unchecked conformances or unsafe annotations.
8. Build through Xcode and verify appropriate configurations.

Do not change build settings as part of this documentation-only step.

### Module boundaries

App: entry, routing, scenes.  
Core: auth, security, networking, persistence, cache, diagnostics.  
Engine: WebView ownership, sessions, workspaces, layout, navigation policy, adapters.  
Features: login, library, settings, notes, vault, suggestions, Siri.  
DesignSystem: tokens, components, motion, themes.  
Adapters: category templates plus service implementations.  
Resources: authorized assets and bundled catalog.  
Tests: isolation, state transitions, persistence, UI, performance, adapter regressions.

Avoid premature packages for every folder. Begin with clear ownership inside one application target; extract modules when useful.

## 21. Data model and persistence

| Entity/table | Main fields and rules |
| --- | --- |
| apps | Stable ID, name, aliases, category, official URL, status |
| categories | Stable ID, display name, sort order |
| app_categories | Membership if multiple discovery categories are later useful |
| app_capabilities | Explicit supported features and limitations |
| app_adapters | Version, compatibility, integrity metadata, rollback |
| favorites | Account ID, service ID, sort position |
| recent_apps | Account ID, service ID, last-used time |
| workspaces | Service owner, safe state, lifecycle, scene reference |
| workspace_panels | Pane roles, supported routes, ratio |
| app_preferences | Explicit override values and inheritance flags |
| app_session_profiles | Account/service mapping to stable store UUID |
| notes | Encrypted content; protect sensitive metadata too |
| vault_entries | Encrypted credential payload; no plaintext secret index |
| sync_queue | App-owned encrypted operations if sync exists |
| schema_migrations | Versioned and tested changes |

Catalog records can be bundled/public. User behavior such as recents, workspace URLs, and note metadata may be sensitive even without passwords; protect according to the threat model.

Use transactions for ownership and related state updates. Plan migration/rollback and storage-full behavior. Do not persist live WKWebView objects.

Local catalog search can use simple indexed matching initially; FTS5 is an option, not a requirement for 240 records. Do not overengineer search before measuring.

## 22. Backend responsibilities

Duova-specific accounts, devices, session revocation, catalog/adapters, suggestions, compatibility reports, rollout metadata, optional encrypted sync.

Third-party service traffic remains direct through supported platform networking. Do not proxy all provider sites through Duova servers.

Begin with one API and PostgreSQL. Introduce CDN/object storage when assets/configuration require remote delivery. Cache verified catalog locally so backend outages do not remove the launcher.

Authentication needs concrete decisions: provider, passkeys/Apple sign-in integration, recovery, token rotation, device revocation, deletion, and secrets management. Do not select a cloud vendor solely for a theoretical speed advantage.

Suggestion backend must not blindly fetch submitted URLs. If remote inspection is later added, validate DNS/IP/redirect destinations and block private/local/metadata endpoints.

## 23. Adapter runtime

### Adapter contract

Service identity; allowed origins; entry routes; supported actions/panels; presentation rules; readiness checks; navigation mapping; permission requests; safe restoration; version constraints; failure detection; fallback.

### Rules

- Category templates share native patterns.
- Each service owns its reviewed CSS/JavaScript behavior.
- Verify message origin and main/subframe expectations.
- Isolated script worlds reduce conflicts but do not make messages inherently trusted.
- Do not expose arbitrary native method execution.
- Do not hide essential provider search unless replaced by a working accessible action.
- Preserve consent, payment, privacy, identity, and required disclosures.
- Disable failed transformations instead of leaving half-hidden pages.
- Prefer constrained configuration; remotely delivered executable behavior requires platform-policy review.
- A signed package confirms source/integrity, not functional safety.

### Rollout

Local bundled known-good adapter → staged update → health checks → rollback or safe web/handoff. Never depend on a remote kill switch being reachable to recover from a clearly detected local failure.

## 24. Siri and shortcuts

Candidate actions:
- Open a supported service.
- Resume a workspace.
- Show Library.
- Open Notes.
- Apply a supported named layout.

Resolve services by stable catalog identity and aliases. Respect existing ownership. Unknown service → understandable failure or library search. Locked sensitive actions should request supported unlock/foreground behavior.

Exact phrases are not guaranteed. Implement using the installed App Intents contract and current documentation. Do not expose note or vault content through unintended voice responses.

## 25. Suggest an App

Fields: required name, required official website URL if known, category, optional desired optimization. Provide a path to report “no website known” rather than encouraging invented links.

States: editing, validation error, submitting, submitted, duplicate, offline retry, rejected, under review, available.

Submission is a request, not instant support. No AI execution in baseline. Avoid collecting private account credentials or private provider URLs.

Settings and empty library search both link here.

## 26. Accessibility and design tokens

### Required accessibility behavior

Dynamic Type, VoiceOver pane order, keyboard navigation, Switch Control, Reduce Motion, adequate targets, readable contrast, captions where provider supports them, focus restoration, accessible loading/save announcements, reachable switcher, and left/right control placement.

Embedded web content may require additional validation; native shell accessibility does not certify a provider page.

### Design-system deliverables

Typography scale; semantic colors; spacing; corner radii; elevation; safe-area rules; compact/expanded breakpoints; icon treatment; motion durations; focus/selection states; error/success/loading patterns.

Reusable components: login actions, search, filters, service row/tile, status badge, recent rail, pane header, divider, switcher, quick note, inherited-setting row, permission explainer, compatibility fallback, destructive confirmation.

Use authentic assets only after provenance/permission review. Placeholder typography or neutral boxes in mockups must not be mistaken for production provider branding.

## 27. Failure and recovery matrix

| Failure/event | UX | Engineering rule |
| --- | --- | --- |
| No network at launch | Cached library, offline status | No network-gated native shell |
| Site timeout | Retry, library, supported handoff | Bounded loading state |
| Expired provider login | Official reauthentication | Safe return route; no token bypass |
| Web process termination | Recovering state | Recreate view; no replay of form submission |
| Broken adapter | Safe mode or handoff | Disable transformations |
| Provider blocks embedding | Explain limitation | No evasion |
| Memory pressure | Preserve active work where feasible | Release nonessential views |
| Duplicate service request | Focus/move existing workspace | Atomic ownership |
| Fold/resize | Continuous adaptive layout | No routine reload |
| Offline third-party edit | Accurate save uncertainty | Do not claim provider sync |
| Native note save failure | Visible retry/error | Keep unsaved text available |
| Permission denied | Usable alternative | No repeated coercive prompts |
| Storage full | Explain cleanup options | Avoid silent data loss |
| Checkout interruption | Official recovery flow | Never automatically resubmit |
| Key unavailable | Locked/recovery state | Never replace with plaintext storage |
| Unknown adapter version | Safe known-good fallback | No unvalidated privilege expansion |

## 28. Future AI optimization

Not a release dependency.

Pipeline: validated authorized URL → permitted structure analysis → category/component mapping → constrained adaptation proposal → login/forms/layout/accessibility/security tests → human approval → signed staged release → regression monitoring and rollback.

Do not send users' private sessions, messages, passwords, or notes to an AI service as part of adaptation. Use approved test data and controlled test accounts.

AI cannot establish permission, fabricate unavailable functionality, bypass anti-abuse protections, or eliminate maintenance when websites change.

## 29. Distribution and service permissions

Before public release, review current official App Store requirements for functionality, third-party content, account deletion, privacy, hosted software where applicable, and distribution. Review each service's terms and branding rights.

This document does not provide legal clearance or guarantee App Store acceptance. The previous conversation's source labels are not usable citations.

Product value should be demonstrated through native workspace continuity, accessible adaptation, notes, customization, and isolation. Use independent-product disclosure. Never imply provider sponsorship.

## 30. Incremental setup and release plan

### Step 0 — Current documentation milestone

Deliver this blueprint and conversation record. No cloud setup or feature implementation.

Observed project: starter SwiftUI ContentView showing “Hello, world!” and MyApp entry with WindowGroup. No implemented service engine is established by those files.

### Step 1 — Project foundation

- Inspect installed toolchain, actual deployment targets, supported destinations, signing, and source-control state.
- Verify any Duo-specific API through local Apple documentation.
- Confirm Swift language mode and strict concurrency; address diagnostics.
- Establish initial folders/ownership without adding every proposed dependency.
- Confirm a clean Xcode build.
- Record actual tested OS/device support rather than copied assumptions.

Exit: reproducible starter build with explicit concurrency policy and known platform capabilities.

### Step 2 — Design the first three surfaces

Login → Library → Immersive workspace shell.

Use local sample data and visibly nonfunctional design placeholders only during design. Specify compact/expanded, dark/light, large-text, loading/error, and switcher states.

Exit: complete reviewable UI flow before backend or broad integration.

### Step 3 — Isolated service proof

Begin with controlled test content and then one or two permitted compatible services. Verify persistent per-service stores, navigation restrictions, no accidental profile sharing, and basic restoration.

Exit: two distinct service profiles remain independent across relaunch.

### Step 4 — Lifecycle and adaptive workspace

Central WebView manager, warm/suspend/restore, owner registry, safe scene activation, secondary pane, resizing continuity, process-termination recovery.

Exit: fast retained switching, no duplicate workspace, graceful memory pressure.

### Step 5 — Durable local features

Introduce persistence package only now if needed. Add favorites, recents, preferences, protected notes, app-lock/key lifecycle, and precise cleanup actions.

Exit: data survives relaunch and failures without plaintext leaks.

### Step 6 — Real account and minimal backend

Choose hosting/auth provider when needed. Implement account lifecycle, profile, revocation, recovery, deletion, and suggestion API.

Exit: real login and account operations with documented security boundaries.

### Step 7 — First production adapters

Select services based on verified feasibility, not popularity alone. Test category archetypes, publish capability labels, implement fallback and rollback.

Exit: small supported catalog with evidence.

### Step 8 — Siri, presets, and polish

Stable routing enables shortcuts. Add reviewed presets, per-app overrides, loading polish, accessibility, privacy-safe diagnostics.

### Step 9 — Release hardening

Isolation review, threat-model review, real-device performance, accessibility, migrations, restore tests, provider permission review, distribution review, controlled beta.

A custom vault ships only after its independent security gate. AI remains later.

### Step 10 — Expansion

Expand toward 20–30 verified integrations, then through the 240-candidate backlog. Revalidate each service continuously. Do not activate all candidates automatically.

## 31. Acceptance criteria

### Native shell

- Cached library works without third-party requests.
- Search and filters work offline over cached records.
- Login and unlock have distinct states.
- Startup preference behaves as documented.
- Every immersive view has an accessible exit/switch action.

### Workspaces

- Distinct services use distinct profile identities.
- Same-service concurrent launch resolves one owner.
- Two supported panes do not create duplicate independent workspaces.
- Switching does not intentionally discard safe state.
- Resizing does not routinely reload providers.
- Web process termination recovers without resubmitting forms.
- Unsupported scene creation degrades gracefully.

### Security and data

- Service bridge cannot access another profile, notes, vault, or arbitrary files.
- Sensitive records are protected with documented keys/access classes.
- Logs contain no auth or private content.
- Clearing cache and signing out are distinct operations.
- Encrypted note save failures are visible and recoverable.
- Account switching cannot inherit another account's website profile.
- Backup, key loss, and deletion behavior are tested.

### Adapters

- Auth, principal routes, forms, uploads/payment where relevant, and fallback are tested.
- Broken selectors do not leave required controls hidden.
- Native handoff is truthful and understandable.
- Only verified capabilities appear in pane picker.
- Catalog and logo permissions are recorded.
- Rollback is possible.

### Performance/accessibility

- Provisional budgets are measured, not marketed as achieved.
- Dynamic Type, VoiceOver, keyboard, and Reduce Motion are checked.
- No essential gesture-only path.
- Native loading remains responsive during provider delays.
- Warm retention stays within measured resource budgets.

## 32. First design sprint deliverables

1. Login → Library → Search/filter → service launch.
2. Immersive service → switcher → another service → resume.
3. Primary content → select companion → swap/focus → compact collapse.
4. Quick Note → autosave → Settings → Notes library.
5. Per-app Layouts/Personalize → override → reset inheritance.
6. Expired login/offline/broken adapter → recover or handoff.
7. Different-service scenes where the actual platform supports them.

Create compact and expanded variants for each, with accessibility and error states. The Instagram/Docs/Maps prototypes are illustrative until their integrations pass feasibility checks.

## 33. Open decisions and verification backlog

- Actual supported Duo hardware/SDK capabilities and scene restrictions.
- Minimum OS and deployment destinations.
- Final identity provider, hosting, and recovery model.
- First two feasible authorized services.
- Official branding permissions.
- Current US popularity research and category methodology.
- Specific encrypted storage integration.
- Vault timing and independent security review.
- Local-only notes versus end-to-end sync.
- Multi-account provider support beyond baseline.
- Whether expanded Workspaces navigation merits a permanent destination.
- Supported notifications/background media per provider.
- Current distribution requirements.

These are tracked decisions, not reasons to block native UI design. Resolve each at the milestone where it becomes necessary.
