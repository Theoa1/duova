-- DUOVA / SUPABASE — SCHEMA v5 ADD-ON: ACCOUNT DELETION, KEY COMMITMENT, PREFERENCE REVISIONS
-- Run in duova-dev AFTER v2, v3 and v4. Safe to re-run (idempotent).
-- Does not drop, truncate or rewrite existing data, except where a person
-- deletes their own account or explicitly starts over (both below).
--
-- A. ACCOUNT DELETION  public.duova_delete_my_account()
--   Deletes the caller's Supabase Auth user. Every Duova table references
--   auth.users ON DELETE CASCADE, so profiles, preferences, saved logins,
--   devices and key envelopes go in the same transaction; Auth's own sessions,
--   identities, passkeys and MFA factors go with the user. The app signs the
--   person in again (password) or refreshes the session right before calling
--   it, and the function refuses an access token older than five minutes, so
--   an old leaked token can't delete the account.
--
-- B. KEY COMMITMENT  public.duova_account_key_commitments
--   One row per account naming the ONE key set (version + fingerprint) that is
--   the account's. A new account's first device must win this row (primary
--   key) before it keeps any keys, so two devices signing in at once can't
--   each make a different key set. Envelopes must match the committed
--   fingerprint (trigger), so no second key set can be shared out.
--
-- C. START OVER  public.duova_start_over_keys(seen_version, new_version, fingerprint, device)
--   For when every device with the keys is gone. In ONE transaction: checks
--   nobody else started over first, erases the encrypted data nobody can open,
--   forgets every device and envelope, and commits the new key set. Either all
--   of it happens or none of it does. The device only replaces its keys after
--   this succeeds.
--
-- D. PREFERENCES  public.duova_save_preferences(expected_revision, account, apps)
--   Saves account and per-app preferences together, only if the stored
--   revision is still the one the device last read (optimistic concurrency).
--   Returns the new revision, or -1 when another device saved first; the app
--   then merges and tries again. Values are dv2 envelopes; the existing column
--   checks still apply.

BEGIN;

DO $check_v4$
BEGIN
  IF to_regclass('public.duova_user_key_envelopes') IS NULL
     OR to_regclass('public.duova_user_preferences') IS NULL
     OR to_regclass('public.duova_user_app_preferences') IS NULL
     OR to_regclass('public.duova_app_login_recipes') IS NULL THEN
    RAISE EXCEPTION 'Duova v2, v3 and v4 must be installed before v5.';
  END IF;
END;
$check_v4$;

-- ---------- A. ACCOUNT DELETION ----------
CREATE OR REPLACE FUNCTION public.duova_delete_my_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  uid uuid := auth.uid();
  issued bigint := nullif(auth.jwt() ->> 'iat', '')::bigint;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not signed in.' USING ERRCODE = '42501';
  END IF;
  IF issued IS NULL OR issued < extract(epoch FROM now())::bigint - 300 THEN
    RAISE EXCEPTION 'Sign in again first.' USING ERRCODE = '42501';
  END IF;
  DELETE FROM auth.users WHERE id = uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found.' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.duova_delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duova_delete_my_account() TO authenticated;

-- ---------- B. KEY COMMITMENT ----------
CREATE TABLE IF NOT EXISTS public.duova_account_key_commitments (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  key_version integer NOT NULL CHECK (key_version > 0),
  key_fingerprint text NOT NULL CHECK (key_fingerprint ~ '^[A-Za-z0-9_-]{43}$'),
  device_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.duova_account_key_commitments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.duova_account_key_commitments FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_account_key_commitments FROM PUBLIC, anon, authenticated;
-- No UPDATE or DELETE for clients: the commitment only changes through start over.
GRANT SELECT, INSERT ON TABLE public.duova_account_key_commitments TO authenticated;

DROP POLICY IF EXISTS duova_owner_select ON public.duova_account_key_commitments;
CREATE POLICY duova_owner_select ON public.duova_account_key_commitments FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS duova_owner_insert ON public.duova_account_key_commitments;
CREATE POLICY duova_owner_insert ON public.duova_account_key_commitments FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Existing accounts: commit the key set their newest envelopes already use.
INSERT INTO public.duova_account_key_commitments (user_id, key_version, key_fingerprint, device_id)
SELECT DISTINCT ON (e.user_id) e.user_id, e.key_version, e.key_fingerprint, e.device_id
FROM public.duova_user_key_envelopes e
WHERE e.key_fingerprint ~ '^[A-Za-z0-9_-]{43}$'
ORDER BY e.user_id, e.key_version DESC
ON CONFLICT (user_id) DO NOTHING;

-- Envelopes must carry the committed key set.
CREATE OR REPLACE FUNCTION duova_private.check_envelope_commitment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.duova_account_key_commitments c
    WHERE c.user_id = NEW.user_id AND c.key_version = NEW.key_version
      AND c.key_fingerprint = NEW.key_fingerprint
  ) THEN
    RAISE EXCEPTION 'Envelope does not match the account''s committed keys.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS duova_envelope_matches_commitment ON public.duova_user_key_envelopes;
CREATE TRIGGER duova_envelope_matches_commitment
  BEFORE INSERT OR UPDATE ON public.duova_user_key_envelopes
  FOR EACH ROW EXECUTE FUNCTION duova_private.check_envelope_commitment();

-- ---------- C. START OVER ----------
CREATE OR REPLACE FUNCTION public.duova_start_over_keys(
  seen_version integer, new_version integer, new_fingerprint text, new_device uuid
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  uid uuid := auth.uid();
  current_version integer;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not signed in.' USING ERRCODE = '42501';
  END IF;
  IF new_fingerprint IS NULL OR new_fingerprint !~ '^[A-Za-z0-9_-]{43}$' OR new_version IS NULL OR new_version < 1 THEN
    RAISE EXCEPTION 'Invalid key commitment.' USING ERRCODE = '22023';
  END IF;

  SELECT key_version INTO current_version
  FROM public.duova_account_key_commitments WHERE user_id = uid FOR UPDATE;
  IF coalesce(current_version, 0) <> coalesce(seen_version, 0) THEN
    RAISE EXCEPTION 'Keys changed on another device.' USING ERRCODE = '40001';
  END IF;
  IF new_version <= coalesce(current_version, 0) THEN
    RAISE EXCEPTION 'Key version must increase.' USING ERRCODE = '22023';
  END IF;

  -- Data sealed with keys nobody has any more. App suggestions are kept.
  DELETE FROM public.duova_app_credentials WHERE user_id = uid;
  DELETE FROM public.duova_user_app_preferences WHERE user_id = uid;
  DELETE FROM public.duova_user_preferences WHERE user_id = uid;
  DELETE FROM public.duova_workspace_panes WHERE user_id = uid;
  DELETE FROM public.duova_user_workspaces WHERE user_id = uid;
  DELETE FROM public.duova_note_app_links WHERE user_id = uid;
  DELETE FROM public.duova_notes WHERE user_id = uid;
  DELETE FROM public.duova_vault_items WHERE user_id = uid;
  DELETE FROM public.duova_user_app_state WHERE user_id = uid;
  DELETE FROM public.duova_user_app_library WHERE user_id = uid;
  DELETE FROM public.duova_user_settings WHERE user_id = uid;
  DELETE FROM public.duova_profiles WHERE user_id = uid;
  DELETE FROM public.duova_user_key_envelopes WHERE user_id = uid;
  DELETE FROM public.duova_user_devices WHERE user_id = uid;

  INSERT INTO public.duova_account_key_commitments (user_id, key_version, key_fingerprint, device_id)
  VALUES (uid, new_version, new_fingerprint, new_device)
  ON CONFLICT (user_id) DO UPDATE
    SET key_version = EXCLUDED.key_version, key_fingerprint = EXCLUDED.key_fingerprint,
        device_id = EXCLUDED.device_id, created_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.duova_start_over_keys(integer, integer, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duova_start_over_keys(integer, integer, text, uuid) TO authenticated;

-- ---------- D. PREFERENCES ----------
CREATE OR REPLACE FUNCTION public.duova_save_preferences(
  expected_revision bigint, account jsonb, apps jsonb
)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  uid uuid := auth.uid();
  current_revision bigint;
  next_revision bigint;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not signed in.' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(account) <> 'object' OR jsonb_typeof(apps) <> 'array' THEN
    RAISE EXCEPTION 'Invalid preferences.' USING ERRCODE = '22023';
  END IF;

  SELECT revision INTO current_revision
  FROM public.duova_user_preferences WHERE user_id = uid FOR UPDATE;

  IF current_revision IS NULL THEN
    IF coalesce(expected_revision, 0) <> 0 THEN RETURN -1; END IF;
    next_revision := 1;
    INSERT INTO public.duova_user_preferences (
      user_id, revision, appearance_mode_enc, color_style_enc, motion_level_enc, expanded_layout_enc,
      panel_ratio_enc, opening_behavior_enc, switcher_side_enc, gesture_style_enc, favorites_enc)
    VALUES (
      uid, next_revision, account ->> 'appearance_mode_enc', account ->> 'color_style_enc',
      account ->> 'motion_level_enc', account ->> 'expanded_layout_enc', account ->> 'panel_ratio_enc',
      account ->> 'opening_behavior_enc', account ->> 'switcher_side_enc', account ->> 'gesture_style_enc',
      account ->> 'favorites_enc')
    ON CONFLICT (user_id) DO NOTHING;
    -- Another device created the row first.
    IF NOT FOUND THEN RETURN -1; END IF;
  ELSE
    IF current_revision <> expected_revision THEN RETURN -1; END IF;
    next_revision := current_revision + 1;
    UPDATE public.duova_user_preferences SET
      revision = next_revision,
      appearance_mode_enc = account ->> 'appearance_mode_enc',
      color_style_enc = account ->> 'color_style_enc',
      motion_level_enc = account ->> 'motion_level_enc',
      expanded_layout_enc = account ->> 'expanded_layout_enc',
      panel_ratio_enc = account ->> 'panel_ratio_enc',
      opening_behavior_enc = account ->> 'opening_behavior_enc',
      switcher_side_enc = account ->> 'switcher_side_enc',
      gesture_style_enc = account ->> 'gesture_style_enc',
      favorites_enc = account ->> 'favorites_enc'
    WHERE user_id = uid;
  END IF;

  DELETE FROM public.duova_user_app_preferences p
  WHERE p.user_id = uid
    AND p.app_ref NOT IN (SELECT a ->> 'app_ref' FROM jsonb_array_elements(apps) a WHERE a ->> 'app_ref' IS NOT NULL);

  INSERT INTO public.duova_user_app_preferences (
    user_id, app_ref, revision, app_slug_enc, appearance_mode_enc, motion_level_enc, expanded_layout_enc,
    panel_ratio_enc, opening_behavior_enc, switcher_side_enc, gesture_style_enc)
  SELECT uid, a ->> 'app_ref', next_revision, a ->> 'app_slug_enc', a ->> 'appearance_mode_enc',
    a ->> 'motion_level_enc', a ->> 'expanded_layout_enc', a ->> 'panel_ratio_enc',
    a ->> 'opening_behavior_enc', a ->> 'switcher_side_enc', a ->> 'gesture_style_enc'
  FROM jsonb_array_elements(apps) a
  ON CONFLICT (user_id, app_ref) DO UPDATE SET
    revision = EXCLUDED.revision,
    app_slug_enc = EXCLUDED.app_slug_enc,
    appearance_mode_enc = EXCLUDED.appearance_mode_enc,
    motion_level_enc = EXCLUDED.motion_level_enc,
    expanded_layout_enc = EXCLUDED.expanded_layout_enc,
    panel_ratio_enc = EXCLUDED.panel_ratio_enc,
    opening_behavior_enc = EXCLUDED.opening_behavior_enc,
    switcher_side_enc = EXCLUDED.switcher_side_enc,
    gesture_style_enc = EXCLUDED.gesture_style_enc;

  RETURN next_revision;
END;
$$;

REVOKE ALL ON FUNCTION public.duova_save_preferences(bigint, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duova_save_preferences(bigint, jsonb, jsonb) TO authenticated;

COMMIT;

-- QUICK CHECK (read-only), after running:
-- SELECT proname, prosecdef FROM pg_proc
--  WHERE proname IN ('duova_delete_my_account', 'duova_start_over_keys', 'duova_save_preferences');
-- SELECT tablename, policyname, cmd FROM pg_policies WHERE tablename = 'duova_account_key_commitments';
-- SELECT count(*) FROM public.duova_account_key_commitments;
