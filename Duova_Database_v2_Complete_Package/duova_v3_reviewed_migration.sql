-- DUOVA v3 — reviewed additive migration for Supabase project duova-dev.
-- Based on the uploaded v3 add-on; designed to run AFTER Duova v2 (25 tables).
-- Preservation: does NOT drop/truncate/rewrite existing user tables or records.
-- New tables: duova_user_preferences, duova_user_app_preferences, duova_app_credentials.
-- Explicit security repair: removes insecure public email sign-in method lookup IF it exists.
-- Deliberately does NOT create or upload website cookies, access tokens or session caches.
-- Password manager: secret_enc reserved for future explicitly opted-in client-encrypted sync;
--     do not populate until key recovery, encryption and threat review are implemented.
-- dv2: prefix is an envelope FORMAT marker only; SQL cannot prove the contents are encrypted.
-- Existing v2 duova_user_settings and duova_user_app_state remain intact; decide on a
--    migration/read-path before switching the Swift app to these newer typed preferences.
-- If data has been added, back up the database first. Apply to dev, not production.

BEGIN;

DO $check_v2$
BEGIN
  IF to_regclass('public.duova_profiles') IS NULL
     OR to_regclass('public.duova_user_app_state') IS NULL
     OR to_regprocedure('duova_private.set_updated_at()') IS NULL THEN
    RAISE EXCEPTION 'Duova v2 prerequisite tables/function missing: install/verify v2 before v3.';
  END IF;
END;
$check_v2$;

-- 1. Account-wide user overrides, client encrypted (no plaintext preferences).
CREATE TABLE IF NOT EXISTS public.duova_user_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 2. App-specific encrypted preferences. app_ref is stable per-account HMAC-derived ID.
CREATE TABLE IF NOT EXISTS public.duova_user_app_preferences (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_ref text NOT NULL CHECK (app_ref ~ '^[A-Za-z0-9_-]{43}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, app_ref)
);

-- 3. App sign-in metadata. No third-party session cookies or tokens.
CREATE TABLE IF NOT EXISTS public.duova_app_credentials (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_ref text NOT NULL CHECK (app_ref ~ '^[A-Za-z0-9_-]{43}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, app_ref)
);

-- Typed preferences preserve the uploaded field names.
ALTER TABLE public.duova_user_preferences
  ADD COLUMN IF NOT EXISTS appearance_mode_enc text,
  ADD COLUMN IF NOT EXISTS color_style_enc text,
  ADD COLUMN IF NOT EXISTS motion_level_enc text,
  ADD COLUMN IF NOT EXISTS expanded_layout_enc text,
  ADD COLUMN IF NOT EXISTS panel_ratio_enc text,
  ADD COLUMN IF NOT EXISTS opening_behavior_enc text,
  ADD COLUMN IF NOT EXISTS switcher_side_enc text,
  ADD COLUMN IF NOT EXISTS gesture_style_enc text,
  ADD COLUMN IF NOT EXISTS favorites_enc text,
  ADD COLUMN IF NOT EXISTS encryption_version integer NOT NULL DEFAULT 2 CHECK (encryption_version > 0),
  ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0);

ALTER TABLE public.duova_user_app_preferences
  ADD COLUMN IF NOT EXISTS app_slug_enc text,
  ADD COLUMN IF NOT EXISTS appearance_mode_enc text,
  ADD COLUMN IF NOT EXISTS motion_level_enc text,
  ADD COLUMN IF NOT EXISTS expanded_layout_enc text,
  ADD COLUMN IF NOT EXISTS panel_ratio_enc text,
  ADD COLUMN IF NOT EXISTS opening_behavior_enc text,
  ADD COLUMN IF NOT EXISTS switcher_side_enc text,
  ADD COLUMN IF NOT EXISTS gesture_style_enc text,
  ADD COLUMN IF NOT EXISTS encryption_version integer NOT NULL DEFAULT 2 CHECK (encryption_version > 0),
  ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0);

ALTER TABLE public.duova_app_credentials
  ADD COLUMN IF NOT EXISTS app_slug_enc text,
  ADD COLUMN IF NOT EXISTS auth_method_enc text,
  ADD COLUMN IF NOT EXISTS login_identifier_enc text,
  ADD COLUMN IF NOT EXISTS secret_enc text,
  ADD COLUMN IF NOT EXISTS code_delivery_enc text,
  ADD COLUMN IF NOT EXISTS encryption_version integer NOT NULL DEFAULT 2 CHECK (encryption_version > 0),
  ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  ADD COLUMN IF NOT EXISTS last_authenticated_at timestamptz;

-- Client-format checks for dv2 envelopes. These are syntactic checks, NOT proof
-- that AES-GCM/ChaCha20-Poly1305 were used or that keys are secure.
-- Null means inherit the account-level default or no credential stored.
DO $ciphertext_checks$
DECLARE rec record;
DECLARE constraint_name text;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      ('duova_user_preferences', 'appearance_mode_enc', 4096),
      ('duova_user_preferences', 'color_style_enc', 4096),
      ('duova_user_preferences', 'motion_level_enc', 4096),
      ('duova_user_preferences', 'expanded_layout_enc', 4096),
      ('duova_user_preferences', 'panel_ratio_enc', 4096),
      ('duova_user_preferences', 'opening_behavior_enc', 4096),
      ('duova_user_preferences', 'switcher_side_enc', 4096),
      ('duova_user_preferences', 'gesture_style_enc', 4096),
      ('duova_user_preferences', 'favorites_enc', 65536),
      ('duova_user_app_preferences', 'app_slug_enc', 4096),
      ('duova_user_app_preferences', 'appearance_mode_enc', 4096),
      ('duova_user_app_preferences', 'motion_level_enc', 4096),
      ('duova_user_app_preferences', 'expanded_layout_enc', 4096),
      ('duova_user_app_preferences', 'panel_ratio_enc', 4096),
      ('duova_user_app_preferences', 'opening_behavior_enc', 4096),
      ('duova_user_app_preferences', 'switcher_side_enc', 4096),
      ('duova_user_app_preferences', 'gesture_style_enc', 4096),
      ('duova_app_credentials', 'app_slug_enc', 4096),
      ('duova_app_credentials', 'auth_method_enc', 4096),
      ('duova_app_credentials', 'login_identifier_enc', 8192),
      ('duova_app_credentials', 'secret_enc', 8192),
      ('duova_app_credentials', 'code_delivery_enc', 4096)
    ) AS checks(table_name, column_name, max_length)
  LOOP
    constraint_name := rec.column_name || '_cipher_format';
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint co
      JOIN pg_class t ON t.oid = co.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'public' AND t.relname = rec.table_name
        AND co.conname = constraint_name
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (%I IS NULL OR '
        || '(length(%I) BETWEEN 60 AND %s AND left(%I, 4) = ''dv2:'' '
        || 'AND substring(%I from 5) ~ ''^[A-Za-z0-9_-]+$''))',
        rec.table_name, constraint_name, rec.column_name,
        rec.column_name, rec.max_length, rec.column_name, rec.column_name
      );
    END IF;
  END LOOP;
END;
$ciphertext_checks$;

-- Security: enforce per-owner row access, and deny anonymous API access.
DO $secure_v3$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'duova_user_preferences','duova_user_app_preferences','duova_app_credentials'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO authenticated', t);

    EXECUTE format('DROP POLICY IF EXISTS duova_owner_select ON public.%I', t);
    EXECUTE format('CREATE POLICY duova_owner_select ON public.%I FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()))', t);
    EXECUTE format('DROP POLICY IF EXISTS duova_owner_insert ON public.%I', t);
    EXECUTE format('CREATE POLICY duova_owner_insert ON public.%I FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()))', t);
    EXECUTE format('DROP POLICY IF EXISTS duova_owner_update ON public.%I', t);
    EXECUTE format('CREATE POLICY duova_owner_update ON public.%I FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()))', t);
    EXECUTE format('DROP POLICY IF EXISTS duova_owner_delete ON public.%I', t);
    EXECUTE format('CREATE POLICY duova_owner_delete ON public.%I FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()))', t);

    EXECUTE format('DROP TRIGGER IF EXISTS duova_touch_updated_at ON public.%I', t);
    EXECUTE format('CREATE TRIGGER duova_touch_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION duova_private.set_updated_at()', t);
  END LOOP;
END;
$secure_v3$;

-- Remove unsafe function that discloses other people's existence and sign-in methods.
-- Individual users should discover their OWN linked methods via Auth, after signing in.
DROP FUNCTION IF EXISTS public.duova_sign_in_methods(text);

COMMIT;

-- Notes: This migration is additive. If the uploaded v3 SQL was already applied,
-- it may have added session_cache_enc to duova_app_credentials; this migration
-- intentionally does NOT delete an existing column/data. Never use that column.
-- Use a separate audited/backup migration to remove it safely, if present.
