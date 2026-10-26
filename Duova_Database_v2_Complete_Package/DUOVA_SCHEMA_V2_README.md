# Duova database blueprint — v2.0 (development)

**Files**
- `duova_full_schema_v2_dev.sql` — complete non-destructive schema for `duova-dev`, including the known earlier 5-table baseline upgrade.
- `duova_full_schema_v2_verify.sql` — read-only metadata verification.

**Deployment**: In Supabase dashboard → select **duova-dev** → **SQL Editor** → **New Query** → paste the complete v2 file → **Run**. Do not run on production. The migration runs in a transaction (`BEGIN...COMMIT`); a SQL error prevents the changes in that transaction from committing. Run the verification query afterward.

## Data dictionary: 25 Duova public tables

### A. Approved catalog and per-app design (13)
| Table | Identifier | Purpose |
|---|---|---|
| `duova_categories` | `slug` | Social, Streaming, Activity, Maps & Travel, Food, Fashion, Productivity, Other |
| `duova_apps` | `slug` | Official URLs, display names, approved logos, categories, compatibility and legal status, feature rank |
| `duova_app_domains` | `(app_slug,hostname,purpose)` | Verified exact hostnames for navigation/auth/media; iPhone runtime must still validate redirects |
| `duova_app_capabilities` | `(app_slug,capability_key)` | Supported, limited or unsupported interactions |
| `duova_app_views` | `(app_slug,view_key)` | Content panes such as feed, comments, messages, document and notes |
| `duova_adapter_versions` | `(app_slug,version,release_channel)` | Reviewed adapter configuration; no arbitrary native script execution |
| `duova_style_assets` | `(app_slug,style_version,theme,posture)` | Versioned **CSS source** plus digest, publish status, asset rights review |
| `duova_global_theme_tokens` | `(theme,version)` | Official light/dark design tokens; seeded with Duova colors |
| `duova_category_theme_tokens` | `(category_slug,theme,version)` | Category-specific token overrides |
| `duova_category_layout_defaults` | `(category_slug,posture)` | Shared layout presets for five display contexts |
| `duova_app_layouts` | `(app_slug,posture)` | Overrides such as primary pane, secondary pane and split ratio |
| `duova_app_launch_assets` | `(app_slug,theme,asset_version)` | Authorized loading-animation assets and modes |
| `duova_catalog_metadata` | `id=1` | Catalog version to support local caching and incremental updates |

### B. Accounts, settings and workspace persistence (7)
| Table | Identifier | Purpose |
|---|---|---|
| `duova_profiles` | `user_id` | Client-encrypted first/last/display/username, avatar asset reference |
| `duova_user_settings` | `(user_id,scope_kind,scope_key)` | Encrypted global and category-level preferences |
| `duova_user_app_state` | `(user_id,app_slug,state_kind)` | Encrypted app-specific preferences and restorable snapshots (v1-compatible) |
| `duova_user_app_library` | `(user_id,app_slug)` | **Optional** cloud favorites and recent-app metadata; metadata visible to backend operator; keep local-only when desired |
| `duova_user_workspaces` | `id` | Encrypted workspace title and recoverable state; associates workspace with primary app |
| `duova_workspace_panes` | `(workspace_id,pane_number)` | Primary/secondary pane pointers and encrypted pane snapshot |
| `duova_notes` | `id` | Encrypted note payloads, revision, pinned status |

### C. Sensitive/related records (5)
| Table | Purpose |
|---|---|
| `duova_note_app_links` | Explicit note-to-app relationship (metadata, not note body) |
| `duova_vault_items` | **Future opt-in sync only**, opaque encrypted credential vault items; no plaintext password fields |
| `duova_user_devices` | Device public wrapping-key metadata, not live sessions or secrets |
| `duova_user_key_envelopes` | Per-device wrapped symmetric keys, never a master key or unwrapped secret |
| `duova_app_suggestions` | User-submitted public app name/URL and status for moderation; these are not end-to-end encrypted so a reviewer can process them |

## Where Duova login information actually lives

| Information | Actual source | Rule |
|---|---|---|
| Account user id | `auth.users.id` | Canonical UUID |
| Email/verification | `auth.users` | Not stored as an editable profile email |
| Sign-in method: Apple/email/other OAuth | `auth.identities.provider` | A user can link several identities; methods are **not** reliable as a single mutable text field |
| Password-based login | Supabase Auth (managed hashing) | Never copy password/hash to `public.duova_*` |
| Passkey credentials | Supabase Auth when supported/enabled | Not duplicated in app-managed tables |
| Touch ID | LocalAuthentication + Keychain on iPhone | Local authorization, not a cloud password |
| First, last, display name, username | `duova_profiles` encrypted columns | App encrypts before upload; locally decrypt for display |
| Session tokens | iPhone Keychain + Supabase Auth | Never put JWT/refresh tokens in app catalog or state tables |

**Admin-only query for support diagnostics (do not expose as a public view or execute from iPhone client):**

```sql
SELECT u.id AS user_id, u.email,
       COALESCE(array_agg(DISTINCT i.provider) FILTER (WHERE i.provider IS NOT NULL), ARRAY[]::text[]) AS linked_login_providers,
       u.created_at AS account_created_at
FROM auth.users AS u
LEFT JOIN auth.identities AS i ON i.user_id = u.id
GROUP BY u.id, u.email, u.created_at
ORDER BY u.created_at DESC;
```

Provider identity list answers *which providers are linked*. Determining exactly which one was used for a particular sign-in needs audited Auth events rather than an editable `login_type` field.

## Encryption model (the SQL does NOT encrypt data by itself)
1. Duova app-owned protected content is encrypted **on the iPhone** with authenticated encryption (AES-GCM) before cloud writes.
2. Keys are managed with protected Keychain/Secure Enclave-compatible mechanisms; ciphertext stored in tables is useless without the required client keys.
3. For multi-device syncing, keys must be securely wrapped for each authorized device and recoverable through an explicitly designed recovery flow.
4. Define a versioned envelope format (e.g. `dv1:<base64url(nonce|ciphertext|tag)>` and authenticated associated data bound to user_id/table/record_id) before inserting private content. *Do not store plaintext as an interim placeholder.*
5. App names, published CSS, supported URLs, category tokens and review status must be queryable, so they are **not end-to-end encrypted**. They are protected by TLS, database-at-rest encryption, and read-only authenticated access.
6. Private notes and profile ciphertext cannot be searched by name/body on the cloud; decrypt in an authorized device and build local full-text search.
7. `duova_user_app_library` and pane-to-service mappings contain **metadata in readable columns**, so a backend operator could infer service usage. They should be optional cloud synchronization, or redesigned as opaque encrypted snapshots if zero server visibility is non-negotiable.
8. Live WebKit view objects, raw cookies, passwords for third-party websites, media buffers and authentication sessions **do not belong in cloud tables**. Website storage remains in app-specific `WKWebsiteDataStore` profiles protected by iOS.
9. A database field called `encrypted_payload` does not *prove* it contains encrypted data; encryption implementation and tests are required before sending real data.

## Security model
- All 25 tables have RLS enabled and explicit table grants.
- `anon` receives **no** direct table privileges.
- Catalog tables are **read-only for authenticated clients**, with publication/legal/rights checks.
- User tables use `(SELECT auth.uid()) = user_id` for `SELECT`, `INSERT`, `UPDATE`, and `DELETE` when relevant.
- Suggestions are user-inserted only as `submitted`; moderation requires trusted administrative access.
- Device and wrapped-key records are append/read only to ordinary users; session revocation is delegated to Supabase Auth rather than treating this table as a trust authority.
- The new user trigger creates only an empty public profile keyed to `auth.users.id`. Do not pull plaintext user metadata into it.
- Administrator-only tools should use elevated database credentials server-side, never inside the iPhone binary.
- Before production, create a two-user authorization test suite for all tables, including cross-user `SELECT/INSERT/UPDATE/DELETE` denial, unknown-app fallback, CSS publication, account deletion and device key access.
- Database schema cannot by itself guarantee URLs are safe from SSRF, CSS is safe from exfiltration, or brand artwork is licensed. A review/publishing workflow is required.

## Example catalog queries

**List published apps in a category**:
```sql
SELECT slug, display_name, official_url, icon_asset_path, capability_status
FROM public.duova_apps
WHERE category_slug = 'social' AND is_published = true
  AND legal_review_status = 'cleared'
ORDER BY sort_rank, display_name
LIMIT 30;
```

**Find published CSS for one app, theme and layout**:
```sql
SELECT style_version, css_source, sha256_hex
FROM public.duova_style_assets
WHERE app_slug = 'instagram' AND theme = 'dark'
  AND posture IN ('expanded','any') AND status = 'published'
  AND rights_reviewed = true
ORDER BY CASE WHEN posture = 'expanded' THEN 0 ELSE 1 END,
         style_version DESC
LIMIT 1;
```

**Get app-specific encrypted preferences for the signed-in user (only after client encryption is implemented)**:
```sql
SELECT app_slug, encrypted_payload, revision, updated_at
FROM public.duova_user_app_state
WHERE user_id = auth.uid() AND app_slug = 'instagram'
  AND state_kind = 'preferences';
```

**Do not test RLS using privileged SQL Editor output alone.** Create two normal test users, use their real Supabase Auth JWTs, and verify that they cannot read/write one another's records. The verification SQL confirms metadata configuration, not authorization behavior.

## Deployment guidance
- Use **`duova-dev` only**. Before deploying, make a backup if you have written data beyond the known five-table starter.
- A rerun is designed to be non-destructive against the exact v1 starter schema already provided; **other, manually altered schema versions are not guaranteed compatible**.
- The script creates catalog tables but intentionally **does not seed unverified third-party apps or CSS**. We will add verified adapters individually.
- Apply this as a version-controlled Supabase migration in future; do not manage production schema exclusively by repeated manual SQL Editor pastes.

---

## v3 add-on: preferences, saved app logins

File: `duova_v3_reviewed_migration.sql`. Run it **after** the v2 schema, in the SQL Editor of `duova-dev`. It's safe to run again; it never drops or rewrites data. It stops with an error if v2 isn't installed.

### What it adds

| Table | One row per | Holds |
|---|---|---|
| `duova_user_preferences` | user | appearance, color style, animation level, expanded layout, panel ratio, opening behavior, floating switcher side, gesture style, favorites |
| `duova_user_app_preferences` | user + app | that app's overrides of the same settings (NULL = use the default) |
| `duova_app_credentials` | user + app | sign-in method, email/username, password, how the code arrives |

It **removes** `duova_sign_in_methods(email)` if an earlier draft created it: anyone could call it to learn whether an email has an account and how it signs in. The sign-in screen no longer uses it and says "Wrong email or password" either way.

No website cookies or sessions go to the cloud. An app's session stays double-encrypted on the device. If an earlier draft added `session_cache_enc`, the app never reads or writes it; remove it in a separate, backed-up migration.

### Device or database?

- **Device only:** App Lock on/off and timeout, Touch ID / Face ID sign-in, launch history, both encryption keys, one-time codes. These protect or describe one device.
- **Database (encrypted):** everything in the three tables above, so it follows the account.

### Encryption

Every `*_enc` column is a `dv2` envelope made on the device: ChaCha20-Poly1305 (vault key) inside AES-256-GCM (master key), each with its own nonce, both bound to user + table + row + column. The two keys are separate device-only Keychain items. The columns reject anything that isn't `dv2`, so plaintext can't be stored by accident. Apps are identified by an HMAC (`app_ref`), not by name. On the device, saved logins are additionally wrapped by `SecureStore` (AES-256-GCM, its own key, iOS file protection).

One-time codes are **never** stored, only how they arrive.

**Other devices:** see the v4 add-on. A new device gets the keys only when a device that has them approves it. Duova never overwrites data it can't open.

### Dashboard settings the app's sign-in uses

1. **Email templates** (Authentication → Emails): add `{{ .Token }}` to *Confirm signup*, *Magic Link* and *Reset Password*, e.g. `Your Duova code: {{ .Token }}`. Links keep working too.
2. **Passkeys:** enable them and set the relying party to a domain you own that serves an `apple-app-site-association` file listing the app under `webcredentials`. The app's entitlement must match (`webcredentials:<that domain>`).
3. **Apple:** enable the Apple provider with the bundle ID `com.agyemangjabez-icloud.com.duova` as a client ID.
4. Keep Auth rate limits on.

---

## v4 add-on: device key sharing, app sign-in recipes

File: `duova_schema_v4_devices_app_signin.sql`. Run it **after** v2 and v3. It's safe to run again, and it stops with an error if v2 or v3 is missing.

### Device key sharing

Uses the v2 tables `duova_user_devices` and `duova_user_key_envelopes`.

1. The first device makes the account's two keys and seals a copy to itself.
2. A new device signs in, registers its public key (X25519) and shows a twelve-digit code, made from its own key with PBKDF2-SHA256 (200,000 rounds). It never makes keys of its own.
3. A device with the keys shows the request with the same code. After Face ID / Touch ID / passcode, it seals both keys to the new device with HPKE (X25519, HKDF-SHA256, ChaCha20-Poly1305), bound to account, device and key version.
4. The new device opens the envelope and keeps the keys only if they match the account's `key_fingerprint` (an HMAC computed with the keys, safe to store).

The server stores only public keys and sealed envelopes, so it can't read the keys. The approving device recomputes the code from the stored public key and the person compares both screens, so a key the server swaps in shows a different code. The code is long and slow to compute so the server can't search for a fake key with the same code. Format checks in the database don't make a key trustworthy; the code comparison does.

**Lost every device?** "Lost your other devices?" on the waiting screen erases the encrypted data nobody can open any more, forgets every device, and makes new keys.

**Removing a device** stops it from being approved again. A device that already received keys keeps them until "Start over" makes new ones. Full revocation (rotating keys and re-encrypting everything) isn't built yet.

### App sign-in recipes

`duova_app_login_recipes` holds, per app, the login page, CSS selectors for the fields, the cookies that mean "signed in", and hints for a second step. Rows are seeded **unpublished**; set `is_published = true` only after testing a recipe. Clients can only read published rows, and without one the app uses its built-in copy. Edit a row in the dashboard when a site changes its login page; the app picks it up on next launch.

- **A database row can't redirect a password.** The sites, login page and session-cookie names always come from the app; a row can only update selectors, the check page and the note, and can only make support stricter. The page script types a password only into a real password field on the app's own sites.
- **Fallback field finder.** When no selector matches, Duova finds the fields itself, and on the second try asks Apple's on-device model. The model only sees field descriptions, never the login.
- **Three tries, all by Duova.** Duova tries the saved login up to three times (kept across launches); there is no "Try again". After the third it shows "We couldn't sign in." and stops until the person signs in themselves or changes the saved login.
- **Second steps go to the person.** A code or approval step is never automated; the card shows "MFA needed".
- **Sessions stay on the device.** After signing in, the app's cookies are kept double-encrypted on this device only, never in the cloud. The web views themselves store nothing on disk.
- **Google apps** (Gmail, Docs, Slides, Maps, YouTube): Google blocks sign-in inside apps, so their cards say so instead of trying. Excel signs in through Microsoft's two-step page (email, then password).

