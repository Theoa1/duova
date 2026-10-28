-- DUOVA / SUPABASE — SCHEMA v4 ADD-ON: DEVICE KEY SHARING + APP SIGN-IN RECIPES
-- Run in duova-dev AFTER duova_full_schema_v2_dev.sql and
-- duova_v3_reviewed_migration.sql. Safe to re-run (idempotent).
-- Does not drop, truncate or rewrite existing data.
--
-- DEVICE KEY SHARING (duova_user_devices / duova_user_key_envelopes, from v2)
--   Each device makes an X25519 key pair; only the PUBLIC half is stored here.
--   A device that already holds the account's two keys (master + vault) seals
--   them to a new device with HPKE (RFC 9180: X25519, HKDF-SHA256,
--   ChaCha20-Poly1305), binding account | device | key version. The server only
--   ever stores that sealed envelope ("dk1:...") and can't open it.
--   key_fingerprint is an HMAC computed WITH the keys over a fixed label: it
--   lets a device check it has the right keys and reveals nothing about them.
--   A new device shows a twelve-digit code derived from its OWN public key
--   (PBKDF2-SHA256, 200,000 rounds); the approving device recomputes it from
--   this table and the person compares the two screens. A key swapped by the
--   server gives a different code. Twelve slow digits keep the server from
--   searching for a substitute key that happens to give the same code.
--   No format check here proves a key is trustworthy; the person comparing
--   the codes does.
--
-- APP SIGN-IN RECIPES (duova_app_login_recipes, new)
--   Per app: login page, CSS selectors for the fields, and how to tell sign-in
--   worked. Read-only for clients; edit them in the dashboard when a site
--   changes. Rows start UNPUBLISHED: set is_published = true only after a
--   recipe is tested. Even published, a row can't change where a password
--   may go: the app keeps its own built-in sites, login page and session
--   cookie names, only allows stricter support, and only ever types a
--   password into a real password field. Without a published row the app
--   uses its built-in copy.
--   No credentials, cookies or sessions are stored here or anywhere in the
--   cloud; an app's session stays encrypted on the device.

BEGIN;

DO $check_v3$
BEGIN
  IF to_regclass('public.duova_user_devices') IS NULL
     OR to_regclass('public.duova_user_key_envelopes') IS NULL
     OR to_regclass('public.duova_app_credentials') IS NULL
     OR to_regprocedure('duova_private.set_updated_at()') IS NULL THEN
    RAISE EXCEPTION 'Duova v2 and v3 must be installed before v4.';
  END IF;
END;
$check_v3$;

-- ---------- A. DEVICES ----------
ALTER TABLE public.duova_user_devices
  DROP CONSTRAINT IF EXISTS duova_user_devices_public_key_format;
ALTER TABLE public.duova_user_devices
  ADD CONSTRAINT duova_user_devices_public_key_format
  CHECK (public_wrapping_key IS NULL OR public_wrapping_key ~ '^[A-Za-z0-9_-]{43}$') NOT VALID;

-- The device's name ("iPhone"), double-encrypted (dv2) like other private data.
ALTER TABLE public.duova_user_devices
  DROP CONSTRAINT IF EXISTS encrypted_label_is_dv2;
ALTER TABLE public.duova_user_devices
  ADD CONSTRAINT encrypted_label_is_dv2
  CHECK (encrypted_label IS NULL OR (length(encrypted_label) BETWEEN 60 AND 4096
    AND left(encrypted_label, 4) = 'dv2:' AND substring(encrypted_label from 5) ~ '^[A-Za-z0-9_-]+$')) NOT VALID;

-- ---------- B. KEY ENVELOPES ----------
ALTER TABLE public.duova_user_key_envelopes
  ADD COLUMN IF NOT EXISTS key_fingerprint text;

ALTER TABLE public.duova_user_key_envelopes
  DROP CONSTRAINT IF EXISTS duova_key_envelopes_fingerprint_format;
ALTER TABLE public.duova_user_key_envelopes
  ADD CONSTRAINT duova_key_envelopes_fingerprint_format
  CHECK (key_fingerprint IS NULL OR key_fingerprint ~ '^[A-Za-z0-9_-]{43}$') NOT VALID;

ALTER TABLE public.duova_user_key_envelopes
  DROP CONSTRAINT IF EXISTS duova_key_envelopes_format;
ALTER TABLE public.duova_user_key_envelopes
  ADD CONSTRAINT duova_key_envelopes_format
  CHECK (wrapping_algorithm <> 'hpke_x25519_sha256_chachapoly_v1'
    OR wrapped_key_ciphertext ~ '^dk1:[A-Za-z0-9_-]+$') NOT VALID;

ALTER TABLE public.duova_user_key_envelopes
  DROP CONSTRAINT IF EXISTS duova_key_envelopes_algorithm;
ALTER TABLE public.duova_user_key_envelopes
  ADD CONSTRAINT duova_key_envelopes_algorithm
  CHECK (wrapping_algorithm IN ('device_envelope_v1', 'hpke_x25519_sha256_chachapoly_v1')) NOT VALID;

CREATE INDEX IF NOT EXISTS duova_key_envelopes_version_idx
  ON public.duova_user_key_envelopes(user_id, key_version DESC);

-- ---------- C. DEVICE ROW-LEVEL SECURITY ----------
-- Owners can read and add (v2), now also rename (label only) and remove.
-- Removing a device also removes its envelopes (ON DELETE CASCADE from v2).
ALTER TABLE public.duova_user_devices FORCE ROW LEVEL SECURITY;
ALTER TABLE public.duova_user_key_envelopes FORCE ROW LEVEL SECURITY;

GRANT UPDATE (encrypted_label) ON TABLE public.duova_user_devices TO authenticated;
GRANT DELETE ON TABLE public.duova_user_devices TO authenticated;
GRANT DELETE ON TABLE public.duova_user_key_envelopes TO authenticated;

DROP POLICY IF EXISTS duova_owner_update ON public.duova_user_devices;
CREATE POLICY duova_owner_update ON public.duova_user_devices FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS duova_owner_delete ON public.duova_user_devices;
CREATE POLICY duova_owner_delete ON public.duova_user_devices FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS duova_owner_delete ON public.duova_user_key_envelopes;
CREATE POLICY duova_owner_delete ON public.duova_user_key_envelopes FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- ---------- D. APP SIGN-IN RECIPES ----------
CREATE TABLE IF NOT EXISTS public.duova_app_login_recipes (
  app_slug text PRIMARY KEY CHECK (app_slug ~ '^[A-Za-z0-9_-]{1,64}$'),
  login_url text NOT NULL CHECK (login_url ~ '^https://'),
  check_url text NOT NULL CHECK (check_url ~ '^https://'),
  hosts text[] NOT NULL CHECK (cardinality(hosts) BETWEEN 1 AND 10),
  session_cookies text[] NOT NULL DEFAULT ARRAY[]::text[],
  identifier_selector text CHECK (length(identifier_selector) <= 500),
  password_selector text CHECK (length(password_selector) <= 500),
  submit_selector text CHECK (length(submit_selector) <= 500),
  next_selector text CHECK (length(next_selector) <= 500),
  mfa_selector text CHECK (length(mfa_selector) <= 500),
  mfa_url_hints text[] NOT NULL DEFAULT ARRAY[]::text[],
  error_selector text CHECK (length(error_selector) <= 500),
  support text NOT NULL DEFAULT 'automatic' CHECK (support IN ('automatic', 'manual', 'unavailable')),
  note text CHECK (note IS NULL OR length(note) <= 60),
  is_published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS duova_touch_updated_at ON public.duova_app_login_recipes;
CREATE TRIGGER duova_touch_updated_at BEFORE UPDATE ON public.duova_app_login_recipes
  FOR EACH ROW EXECUTE FUNCTION duova_private.set_updated_at();

ALTER TABLE public.duova_app_login_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.duova_app_login_recipes FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_app_login_recipes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.duova_app_login_recipes TO authenticated;
DROP POLICY IF EXISTS duova_read_published ON public.duova_app_login_recipes;
CREATE POLICY duova_read_published ON public.duova_app_login_recipes FOR SELECT TO authenticated
  USING (is_published = true);

-- Apps no longer in the catalog (Netflix, Uber and WhatsApp were replaced by
-- Twitch, Google Slides and Excel).
DELETE FROM public.duova_app_login_recipes WHERE app_slug IN ('netflix', 'uber', 'whatsapp');

-- Same starting points as the app's built-in copies, unpublished until tested.
-- Existing rows are kept, so dashboard edits survive re-running this file.
INSERT INTO public.duova_app_login_recipes
  (app_slug, login_url, check_url, hosts, session_cookies,
   identifier_selector, password_selector, submit_selector, next_selector,
   mfa_selector, mfa_url_hints, error_selector, support, note, is_published)
VALUES
  ('instagram', 'https://www.instagram.com/accounts/login/', 'https://www.instagram.com/',
   ARRAY['instagram.com'], ARRAY['sessionid'],
   'input[name="username"]', 'input[name="password"]', 'button[type="submit"]', NULL,
   'input[name="verificationCode"], input[name="security_code"]', ARRAY['two_factor', '/challenge/'],
   '#slfErrorAlert, [role="alert"]', 'automatic', NULL, false),
  ('spotify', 'https://accounts.spotify.com/en/login', 'https://accounts.spotify.com/en/status',
   ARRAY['spotify.com'], ARRAY['sp_dc'],
   '#login-username', '#login-password', '#login-button', NULL,
   'input[autocomplete="one-time-code"]', ARRAY['/challenge'],
   '[data-encore-id="banner"], [role="alert"]', 'automatic', NULL, false),
  ('twitch', 'https://www.twitch.tv/login', 'https://www.twitch.tv/settings/profile',
   ARRAY['twitch.tv'], ARRAY['auth-token'],
   '#login-username', '#password-input', '[data-a-target="passport-login-button"]', NULL,
   'input[autocomplete="one-time-code"], [data-a-target="tw-input"][inputmode="numeric"]', ARRAY[]::text[],
   '[data-a-target="passport-error-message"], [role="alert"]', 'automatic', NULL, false),
  ('tiktok', 'https://www.tiktok.com/login/phone-or-email/email', 'https://www.tiktok.com/setting',
   ARRAY['tiktok.com'], ARRAY['sessionid'],
   'input[name="username"]', 'input[type="password"]', 'button[type="submit"]', NULL,
   'input[autocomplete="one-time-code"]', ARRAY['verify'],
   '[class*="ErrorText"], [role="alert"]', 'automatic', NULL, false),
  ('excel', 'https://login.microsoftonline.com/', 'https://www.office.com/',
   ARRAY['microsoftonline.com', 'live.com', 'microsoft.com', 'office.com'],
   ARRAY['ESTSAUTH', 'ESTSAUTHPERSISTENT', '__Host-MSAAUTH'],
   'input[name="loginfmt"]', 'input[name="passwd"]', '#idSIButton9', '#idSIButton9',
   'input[name="otc"], #idTxtBx_SAOTCC_OTC, #idRichContext_DisplaySign', ARRAY['/proofs/', 'SAOTC'],
   '#usernameError, #passwordError, [role="alert"]', 'automatic', NULL, false),
  ('gmail', 'https://accounts.google.com/', 'https://myaccount.google.com/',
   ARRAY['google.com', 'youtube.com'], ARRAY['SID', '__Secure-3PSID'],
   NULL, NULL, NULL, NULL, NULL, ARRAY['/challenge/'], NULL, 'unavailable', 'Google blocks in-app sign-in.', false),
  ('googleDocs', 'https://accounts.google.com/', 'https://myaccount.google.com/',
   ARRAY['google.com', 'youtube.com'], ARRAY['SID', '__Secure-3PSID'],
   NULL, NULL, NULL, NULL, NULL, ARRAY['/challenge/'], NULL, 'unavailable', 'Google blocks in-app sign-in.', false),
  ('googleMaps', 'https://accounts.google.com/', 'https://myaccount.google.com/',
   ARRAY['google.com', 'youtube.com'], ARRAY['SID', '__Secure-3PSID'],
   NULL, NULL, NULL, NULL, NULL, ARRAY['/challenge/'], NULL, 'unavailable', 'Google blocks in-app sign-in.', false),
  ('youtube', 'https://accounts.google.com/', 'https://myaccount.google.com/',
   ARRAY['google.com', 'youtube.com'], ARRAY['SID', '__Secure-3PSID'],
   NULL, NULL, NULL, NULL, NULL, ARRAY['/challenge/'], NULL, 'unavailable', 'Google blocks in-app sign-in.', false),
  ('googleSlides', 'https://accounts.google.com/', 'https://myaccount.google.com/',
   ARRAY['google.com', 'youtube.com'], ARRAY['SID', '__Secure-3PSID'],
   NULL, NULL, NULL, NULL, NULL, ARRAY['/challenge/'], NULL, 'unavailable', 'Google blocks in-app sign-in.', false)
ON CONFLICT (app_slug) DO NOTHING;

COMMIT;

-- QUICK CHECK (read-only), after running:
-- SELECT column_name FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'duova_user_key_envelopes';
-- SELECT tablename, policyname, cmd FROM pg_policies
--  WHERE tablename IN ('duova_user_devices', 'duova_user_key_envelopes', 'duova_app_login_recipes');
-- SELECT app_slug, support, is_published FROM public.duova_app_login_recipes ORDER BY app_slug;
