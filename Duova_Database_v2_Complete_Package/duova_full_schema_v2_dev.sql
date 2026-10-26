-- DUOVA / SUPABASE — FULL DEVELOPMENT DATABASE SCHEMA v2.0
-- Prepared 2026-10-26 | PostgreSQL / Supabase
-- Run ONLY in Supabase project duova-dev after reviewing.
-- Designed for NEW installs AND NON-DESTRUCTIVE UPGRADES from the supplied 5-table v1.
-- Does NOT drop user tables, truncate data, or overwrite login credentials.
-- IMPORTANT: Existing v1 policies with known names are replaced with v2 policies.
-- New user-sensitive payloads are only containers for CLIENT-SIDE ciphertext.
-- Creating the schema does not automatically encrypt data or prove RLS works.
-- Auth/passwords/passkeys/sessions remain in Supabase's protected auth schema.
-- Do not store provider cookies, raw credentials, OAuth tokens, or secret API keys here.

BEGIN;

-- EXPOSED public: every application table below enables RLS and explicit grants.
-- NON-EXPOSED helper schema, for a trusted auth-user creation trigger.
CREATE SCHEMA IF NOT EXISTS duova_private;
REVOKE ALL ON SCHEMA duova_private FROM PUBLIC, anon, authenticated;

-- ---------- A. CATALOG / SEARCH / CATEGORY DESIGN ----------
CREATE TABLE IF NOT EXISTS public.duova_categories (
  slug text PRIMARY KEY CHECK (slug ~ '^[a-z0-9_-]+$'),
  display_name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_visible boolean NOT NULL DEFAULT true
);
ALTER TABLE public.duova_categories
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS icon_symbol text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS public.duova_apps (
  slug text PRIMARY KEY CHECK (slug ~ '^[a-z0-9_-]+$'),
  display_name text NOT NULL,
  category_slug text NOT NULL REFERENCES public.duova_categories(slug),
  official_url text NOT NULL CHECK (official_url ~ '^https://'),
  icon_asset_path text,
  capability_status text NOT NULL DEFAULT 'under_review'
      CHECK (capability_status IN ('under_review','optimized','enhanced_web','native_handoff','unsupported')),
  adapter_version text,
  is_published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.duova_apps
  ADD COLUMN IF NOT EXISTS short_description text,
  ADD COLUMN IF NOT EXISTS native_app_url text,
  ADD COLUMN IF NOT EXISTS searchable_aliases text[] NOT NULL DEFAULT ARRAY[]::text[],
  ADD COLUMN IF NOT EXISTS integration_mode text NOT NULL DEFAULT 'review'
    CHECK (integration_mode IN ('review','embedded_web','native_handoff','external_browser')),
  ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sort_rank integer NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS published_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS legal_review_status text NOT NULL DEFAULT 'pending'
    CHECK (legal_review_status IN ('pending','cleared','restricted','rejected')),
  ADD COLUMN IF NOT EXISTS min_client_build integer NOT NULL DEFAULT 1 CHECK (min_client_build >= 1);
CREATE INDEX IF NOT EXISTS duova_apps_category_idx
  ON public.duova_apps(category_slug, display_name);
CREATE INDEX IF NOT EXISTS duova_apps_published_idx
  ON public.duova_apps(category_slug, sort_rank, display_name)
  WHERE is_published = true;
CREATE INDEX IF NOT EXISTS duova_apps_search_idx
  ON public.duova_apps USING GIN
  (to_tsvector('simple', coalesce(display_name,'') || ' ' || coalesce(short_description,'') || ' ' || slug));

CREATE TABLE IF NOT EXISTS public.duova_app_domains (
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  hostname text NOT NULL CHECK (hostname = lower(hostname) AND hostname ~ '^[a-z0-9.-]+$'),
  purpose text NOT NULL DEFAULT 'navigation' CHECK (purpose IN ('navigation','auth','media','api','redirect')),
  allow_subdomains boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_slug, hostname, purpose)
);
CREATE INDEX IF NOT EXISTS duova_app_domains_hostname_idx ON public.duova_app_domains(hostname);

CREATE TABLE IF NOT EXISTS public.duova_app_capabilities (
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  capability_key text NOT NULL CHECK (capability_key ~ '^[a-z0-9_]+$'),
  support_status text NOT NULL DEFAULT 'unverified'
    CHECK (support_status IN ('unverified','supported','limited','unavailable')),
  requires_permission boolean NOT NULL DEFAULT false,
  verification_notes text,
  verified_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_slug, capability_key)
);

CREATE TABLE IF NOT EXISTS public.duova_app_views (
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  view_key text NOT NULL CHECK (view_key ~ '^[a-z0-9_]+$'),
  display_name text NOT NULL,
  view_role text NOT NULL DEFAULT 'either' CHECK (view_role IN ('primary','secondary','either')),
  support_status text NOT NULL DEFAULT 'unverified'
    CHECK (support_status IN ('unverified','supported','limited','unavailable')),
  sort_order integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_slug, view_key)
);

-- Config only. Do not put remote JavaScript/executable code into JSONB manifests.
CREATE TABLE IF NOT EXISTS public.duova_adapter_versions (
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  version integer NOT NULL CHECK (version > 0),
  release_channel text NOT NULL DEFAULT 'stable'
    CHECK (release_channel IN ('dev','beta','stable')),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','approved','published','retired','blocked')),
  manifest jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(manifest) = 'object'),
  min_client_build integer NOT NULL DEFAULT 1 CHECK (min_client_build >= 1),
  release_notes text,
  approved_at timestamptz,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_slug, version, release_channel)
);
CREATE INDEX IF NOT EXISTS duova_adapter_published_idx
  ON public.duova_adapter_versions(app_slug, release_channel, version DESC)
  WHERE status = 'published';

-- Reviewed CSS source per app/version/theme/posture.
-- IMPORTANT: CSS can request external URLs; audit @import, url(), tracking and content injection.
-- No client writes; production updater must only publish approved, versioned CSS.
CREATE TABLE IF NOT EXISTS public.duova_style_assets (
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  style_version integer NOT NULL CHECK (style_version > 0),
  theme text NOT NULL CHECK (theme IN ('light','dark')),
  posture text NOT NULL CHECK (posture IN ('any','compact','expanded','book','tabletop','narrow')),
  css_source text NOT NULL CHECK (length(css_source) BETWEEN 1 AND 200000),
  sha256_hex text NOT NULL CHECK (sha256_hex ~ '^[a-f0-9]{64}$'),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','approved','published','retired','blocked')),
  rights_reviewed boolean NOT NULL DEFAULT false,
  published_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_slug, style_version, theme, posture),
  CHECK (status <> 'published' OR (rights_reviewed AND published_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS duova_style_published_idx
  ON public.duova_style_assets(app_slug, theme, posture, style_version DESC)
  WHERE status = 'published';

CREATE TABLE IF NOT EXISTS public.duova_global_theme_tokens (
  theme text NOT NULL CHECK (theme IN ('light','dark')),
  version integer NOT NULL CHECK (version > 0),
  tokens jsonb NOT NULL CHECK (jsonb_typeof(tokens) = 'object'),
  is_published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (theme, version)
);

CREATE TABLE IF NOT EXISTS public.duova_category_theme_tokens (
  category_slug text NOT NULL REFERENCES public.duova_categories(slug) ON DELETE CASCADE,
  theme text NOT NULL CHECK (theme IN ('light','dark')),
  version integer NOT NULL CHECK (version > 0),
  tokens jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(tokens) = 'object'),
  is_published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (category_slug, theme, version)
);

CREATE TABLE IF NOT EXISTS public.duova_category_layout_defaults (
  category_slug text NOT NULL REFERENCES public.duova_categories(slug) ON DELETE CASCADE,
  posture text NOT NULL CHECK (posture IN ('compact','expanded','book','tabletop','narrow')),
  layout_config jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(layout_config) = 'object'),
  is_published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (category_slug, posture)
);

CREATE TABLE IF NOT EXISTS public.duova_app_layouts (
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  posture text NOT NULL CHECK (posture IN ('compact','expanded','book','tabletop','narrow')),
  primary_view_key text,
  secondary_view_key text,
  primary_share smallint NOT NULL DEFAULT 60 CHECK (primary_share BETWEEN 25 AND 90),
  layout_config jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(layout_config) = 'object'),
  is_published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_slug, posture),
  FOREIGN KEY (app_slug, primary_view_key) REFERENCES public.duova_app_views(app_slug, view_key),
  FOREIGN KEY (app_slug, secondary_view_key) REFERENCES public.duova_app_views(app_slug, view_key)
);

-- Only licensed artwork/animations; paths refer to approved application/CDN assets.
CREATE TABLE IF NOT EXISTS public.duova_app_launch_assets (
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  theme text NOT NULL CHECK (theme IN ('light','dark')),
  asset_version integer NOT NULL CHECK (asset_version > 0),
  animation_type text NOT NULL DEFAULT 'native'
    CHECK (animation_type IN ('native','static','rive','lottie','website_native')),
  asset_path text,
  rights_reviewed boolean NOT NULL DEFAULT false,
  is_published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (app_slug, theme, asset_version),
  CHECK (NOT is_published OR rights_reviewed)
);

-- Version pin for client-side incremental catalog refresh.
CREATE TABLE IF NOT EXISTS public.duova_catalog_metadata (
  id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  catalog_version bigint NOT NULL DEFAULT 1 CHECK (catalog_version > 0),
  published_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.duova_catalog_metadata(id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- ---------- B. AUTH-LINKED USER PROFILE & ACCOUNT SETTINGS ----------
-- EMAIL/PASSWORD/PROVIDERS: Source of truth = auth.users / auth.identities.
-- The following user-visible names MUST be CLIENT ENCRYPTED before upload.
CREATE TABLE IF NOT EXISTS public.duova_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  encrypted_profile_payload text,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.duova_profiles
  ADD COLUMN IF NOT EXISTS first_name_encrypted text,
  ADD COLUMN IF NOT EXISTS last_name_encrypted text,
  ADD COLUMN IF NOT EXISTS display_name_encrypted text,
  ADD COLUMN IF NOT EXISTS username_encrypted text,
  ADD COLUMN IF NOT EXISTS avatar_asset_path text,
  ADD COLUMN IF NOT EXISTS encryption_version integer NOT NULL DEFAULT 1 CHECK (encryption_version > 0),
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- A single encrypted JSON envelope for global settings, plus inherited category overrides.
CREATE TABLE IF NOT EXISTS public.duova_user_settings (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope_kind text NOT NULL CHECK (scope_kind IN ('global','category')),
  scope_key text NOT NULL CHECK (scope_key ~ '^[a-z0-9_-]+$'),
  encrypted_payload text NOT NULL CHECK (length(encrypted_payload) BETWEEN 16 AND 1000000),
  encryption_version integer NOT NULL DEFAULT 1 CHECK (encryption_version > 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, scope_kind, scope_key),
  CHECK ((scope_kind = 'global' AND scope_key = 'global') OR scope_kind = 'category')
);

-- Compatible with the original v1 table and its state_kind constraint.
-- Personal app state = encrypted per app, e.g. preferences, workspace snapshot, favorite/recent.
CREATE TABLE IF NOT EXISTS public.duova_user_app_state (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  state_kind text NOT NULL CHECK (state_kind IN ('preferences','workspace','favorite','recent')),
  encrypted_payload text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, app_slug, state_kind)
);
ALTER TABLE public.duova_user_app_state
  ADD COLUMN IF NOT EXISTS encryption_version integer NOT NULL DEFAULT 1 CHECK (encryption_version > 0),
  ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0);
CREATE INDEX IF NOT EXISTS duova_user_app_state_user_idx
  ON public.duova_user_app_state(user_id, updated_at DESC);

-- Optional sync metadata. An app identity is queryable; private web content is never stored here.
CREATE TABLE IF NOT EXISTS public.duova_user_app_library (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  is_favorite boolean NOT NULL DEFAULT false,
  is_hidden boolean NOT NULL DEFAULT false,
  favorite_position integer CHECK (favorite_position IS NULL OR favorite_position >= 0),
  last_opened_at timestamptz,
  open_count integer NOT NULL DEFAULT 0 CHECK (open_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, app_slug)
);
CREATE INDEX IF NOT EXISTS duova_user_library_favorites_idx
  ON public.duova_user_app_library(user_id, favorite_position, app_slug)
  WHERE is_favorite;
CREATE INDEX IF NOT EXISTS duova_user_library_recent_idx
  ON public.duova_user_app_library(user_id, last_opened_at DESC NULLS LAST);

-- Multiple Duova scenes; state is a ciphertext envelope, NOT a serialized WebView/cookie jar.
CREATE TABLE IF NOT EXISTS public.duova_user_workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  primary_app_slug text REFERENCES public.duova_apps(slug) ON DELETE SET NULL,
  encrypted_title text,
  encrypted_state_snapshot text,
  encryption_version integer NOT NULL DEFAULT 1 CHECK (encryption_version > 0),
  is_archived boolean NOT NULL DEFAULT false,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, id)
);
CREATE INDEX IF NOT EXISTS duova_workspaces_user_active_idx
  ON public.duova_user_workspaces(user_id, updated_at DESC) WHERE NOT is_archived;
CREATE INDEX IF NOT EXISTS duova_workspaces_primary_app_idx
  ON public.duova_user_workspaces(user_id, primary_app_slug, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.duova_workspace_panes (
  user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  pane_number smallint NOT NULL CHECK (pane_number BETWEEN 1 AND 3),
  app_slug text REFERENCES public.duova_apps(slug) ON DELETE RESTRICT,
  view_key text,
  encrypted_pane_state text,
  encryption_version integer NOT NULL DEFAULT 1 CHECK (encryption_version > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id, pane_number),
  FOREIGN KEY (user_id, workspace_id)
    REFERENCES public.duova_user_workspaces(user_id, id) ON DELETE CASCADE,
  FOREIGN KEY (app_slug, view_key)
    REFERENCES public.duova_app_views(app_slug, view_key),
  CHECK (view_key IS NULL OR app_slug IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS duova_panes_user_idx ON public.duova_workspace_panes(user_id, workspace_id);

-- ---------- C. ENCRYPTED NOTES / OPTIONAL FUTURE VAULT ----------
CREATE TABLE IF NOT EXISTS public.duova_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  encrypted_payload text NOT NULL CHECK (length(encrypted_payload) BETWEEN 16 AND 1000000),
  encryption_version integer NOT NULL DEFAULT 1 CHECK (encryption_version > 0),
  is_pinned boolean NOT NULL DEFAULT false,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, id)
);
CREATE INDEX IF NOT EXISTS duova_notes_user_recent_idx ON public.duova_notes(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.duova_note_app_links (
  user_id uuid NOT NULL,
  note_id uuid NOT NULL,
  app_slug text NOT NULL REFERENCES public.duova_apps(slug) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (note_id, app_slug),
  FOREIGN KEY (user_id, note_id) REFERENCES public.duova_notes(user_id,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS duova_note_links_user_app_idx ON public.duova_note_app_links(user_id,app_slug);

-- Future optional encrypted vault sync. The vault is LOCAL-ONLY by default.
-- No plaintext password, URL, username, TOTP secret or credential metadata here.
CREATE TABLE IF NOT EXISTS public.duova_vault_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  encrypted_payload text NOT NULL CHECK (length(encrypted_payload) BETWEEN 16 AND 1000000),
  encryption_version integer NOT NULL DEFAULT 1 CHECK (encryption_version > 0),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS duova_vault_user_idx ON public.duova_vault_items(user_id,updated_at DESC);

-- ---------- D. KEY WRAPPING / DEVICES (NO MASTER KEYS IN DB) ----------
CREATE TABLE IF NOT EXISTS public.duova_user_devices (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL,
  encrypted_label text,
  public_wrapping_key text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_id)
);

CREATE TABLE IF NOT EXISTS public.duova_user_key_envelopes (
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  key_version integer NOT NULL CHECK (key_version > 0),
  wrapped_key_ciphertext text NOT NULL CHECK (length(wrapped_key_ciphertext) BETWEEN 32 AND 10000),
  wrapping_algorithm text NOT NULL DEFAULT 'device_envelope_v1',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_id, key_version),
  FOREIGN KEY (user_id,device_id)
    REFERENCES public.duova_user_devices(user_id, device_id) ON DELETE CASCADE
);

-- ---------- E. APP SUGGESTIONS / MODERATION ----------
CREATE TABLE IF NOT EXISTS public.duova_app_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  app_name text NOT NULL CHECK (length(trim(app_name)) BETWEEN 2 AND 120),
  website_url text NOT NULL CHECK (website_url ~ '^https://'),
  review_status text NOT NULL DEFAULT 'submitted'
    CHECK (review_status IN ('submitted','under_review','approved','declined')),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.duova_app_suggestions
  ADD COLUMN IF NOT EXISTS category_slug text REFERENCES public.duova_categories(slug),
  ADD COLUMN IF NOT EXISTS user_comment text CHECK (user_comment IS NULL OR length(user_comment) <= 2000),
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
CREATE INDEX IF NOT EXISTS duova_suggestions_user_idx
  ON public.duova_app_suggestions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS duova_suggestions_review_idx
  ON public.duova_app_suggestions(review_status,created_at DESC);

-- ---------- F. TIMESTAMPS & NEW-ACCOUNT SKELETON ----------
CREATE OR REPLACE FUNCTION duova_private.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION duova_private.create_auth_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- Only user_id, never plaintext metadata or password hashes.
  INSERT INTO public.duova_profiles(user_id) VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION duova_private.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION duova_private.create_auth_profile() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS duova_after_auth_user_created ON auth.users;
CREATE TRIGGER duova_after_auth_user_created
  AFTER INSERT ON auth.users FOR EACH ROW
  EXECUTE FUNCTION duova_private.create_auth_profile();

-- Existing Auth users (if any) get an empty profile, never a copied password.
INSERT INTO public.duova_profiles(user_id)
SELECT id FROM auth.users
ON CONFLICT (user_id) DO NOTHING;

-- Trigger timestamps for all mutable tables, including upgraded v1 tables.
DO $duova_timestamps$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'duova_categories','duova_apps','duova_app_capabilities','duova_app_views',
    'duova_style_assets','duova_global_theme_tokens','duova_category_theme_tokens','duova_category_layout_defaults',
    'duova_app_layouts','duova_app_launch_assets','duova_profiles','duova_user_settings',
    'duova_user_app_state','duova_user_app_library','duova_user_workspaces',
    'duova_workspace_panes','duova_notes','duova_vault_items'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS duova_touch_updated_at ON public.%I', t);
    EXECUTE format('CREATE TRIGGER duova_touch_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION duova_private.set_updated_at()', t);
  END LOOP;
END;
$duova_timestamps$;

-- ---------- G. NON-NEGOTIABLE PERMISSIONS ----------
-- Restrict all project tables before granting minimal rights to authenticated callers.

ALTER TABLE public.duova_categories ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_categories FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_apps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_apps FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_app_domains ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_app_domains FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_app_capabilities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_app_capabilities FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_app_views ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_app_views FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_adapter_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_adapter_versions FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_style_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_style_assets FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_global_theme_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_global_theme_tokens FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_category_theme_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_category_theme_tokens FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_category_layout_defaults ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_category_layout_defaults FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_app_layouts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_app_layouts FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_app_launch_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_app_launch_assets FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_catalog_metadata ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_catalog_metadata FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_profiles FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_user_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_user_settings FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_user_app_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_user_app_state FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_user_app_library ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_user_app_library FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_user_workspaces ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_user_workspaces FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_workspace_panes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_workspace_panes FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_notes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_notes FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_note_app_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_note_app_links FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_vault_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_vault_items FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_user_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_user_devices FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_user_key_envelopes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_user_key_envelopes FROM PUBLIC, anon, authenticated;

ALTER TABLE public.duova_app_suggestions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.duova_app_suggestions FROM PUBLIC, anon, authenticated;

GRANT SELECT ON TABLE public.duova_categories TO authenticated;

GRANT SELECT ON TABLE public.duova_apps TO authenticated;

GRANT SELECT ON TABLE public.duova_app_domains TO authenticated;

GRANT SELECT ON TABLE public.duova_app_capabilities TO authenticated;

GRANT SELECT ON TABLE public.duova_app_views TO authenticated;

GRANT SELECT ON TABLE public.duova_adapter_versions TO authenticated;

GRANT SELECT ON TABLE public.duova_style_assets TO authenticated;

GRANT SELECT ON TABLE public.duova_global_theme_tokens TO authenticated;

GRANT SELECT ON TABLE public.duova_category_theme_tokens TO authenticated;

GRANT SELECT ON TABLE public.duova_category_layout_defaults TO authenticated;

GRANT SELECT ON TABLE public.duova_app_layouts TO authenticated;

GRANT SELECT ON TABLE public.duova_app_launch_assets TO authenticated;

GRANT SELECT ON TABLE public.duova_catalog_metadata TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_profiles TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_user_settings TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_user_app_state TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_user_app_library TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_user_workspaces TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_workspace_panes TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_notes TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_note_app_links TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.duova_vault_items TO authenticated;

GRANT SELECT, INSERT ON TABLE public.duova_user_devices TO authenticated;

GRANT SELECT, INSERT ON TABLE public.duova_user_key_envelopes TO authenticated;

GRANT SELECT, INSERT ON TABLE public.duova_app_suggestions TO authenticated;

-- Existing v1 policy names, removed to avoid duplicated permissive rules.
DROP POLICY IF EXISTS duova_category_read ON public.duova_categories;
DROP POLICY IF EXISTS duova_app_read ON public.duova_apps;
DROP POLICY IF EXISTS duova_profile_read ON public.duova_profiles;
DROP POLICY IF EXISTS duova_profile_insert ON public.duova_profiles;
DROP POLICY IF EXISTS duova_profile_update ON public.duova_profiles;
DROP POLICY IF EXISTS duova_profile_delete ON public.duova_profiles;
DROP POLICY IF EXISTS duova_state_read ON public.duova_user_app_state;
DROP POLICY IF EXISTS duova_state_insert ON public.duova_user_app_state;
DROP POLICY IF EXISTS duova_state_update ON public.duova_user_app_state;
DROP POLICY IF EXISTS duova_state_delete ON public.duova_user_app_state;
DROP POLICY IF EXISTS duova_suggestion_read ON public.duova_app_suggestions;
DROP POLICY IF EXISTS duova_suggestion_insert ON public.duova_app_suggestions;

DROP POLICY IF EXISTS duova_read_published ON public.duova_categories;
CREATE POLICY duova_read_published ON public.duova_categories
FOR SELECT TO authenticated USING (is_visible = true);

DROP POLICY IF EXISTS duova_read_published ON public.duova_apps;
CREATE POLICY duova_read_published ON public.duova_apps
FOR SELECT TO authenticated USING (is_published = true AND capability_status IN ('optimized','enhanced_web','native_handoff') AND legal_review_status = 'cleared');

DROP POLICY IF EXISTS duova_read_published ON public.duova_app_domains;
CREATE POLICY duova_read_published ON public.duova_app_domains
FOR SELECT TO authenticated USING (is_verified = true AND EXISTS (SELECT 1 FROM public.duova_apps a WHERE a.slug = app_slug AND a.is_published AND a.legal_review_status = 'cleared'));

DROP POLICY IF EXISTS duova_read_published ON public.duova_app_capabilities;
CREATE POLICY duova_read_published ON public.duova_app_capabilities
FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.duova_apps a WHERE a.slug = app_slug AND a.is_published AND a.legal_review_status = 'cleared'));

DROP POLICY IF EXISTS duova_read_published ON public.duova_app_views;
CREATE POLICY duova_read_published ON public.duova_app_views
FOR SELECT TO authenticated USING (support_status IN ('supported','limited') AND EXISTS (SELECT 1 FROM public.duova_apps a WHERE a.slug = app_slug AND a.is_published AND a.legal_review_status = 'cleared'));

DROP POLICY IF EXISTS duova_read_published ON public.duova_adapter_versions;
CREATE POLICY duova_read_published ON public.duova_adapter_versions
FOR SELECT TO authenticated USING (status = 'published' AND EXISTS (SELECT 1 FROM public.duova_apps a WHERE a.slug = app_slug AND a.is_published AND a.legal_review_status = 'cleared'));

DROP POLICY IF EXISTS duova_read_published ON public.duova_style_assets;
CREATE POLICY duova_read_published ON public.duova_style_assets
FOR SELECT TO authenticated USING (status = 'published' AND rights_reviewed = true AND EXISTS (SELECT 1 FROM public.duova_apps a WHERE a.slug = app_slug AND a.is_published AND a.legal_review_status = 'cleared'));

DROP POLICY IF EXISTS duova_read_published ON public.duova_global_theme_tokens;
CREATE POLICY duova_read_published ON public.duova_global_theme_tokens
FOR SELECT TO authenticated USING (is_published = true);

DROP POLICY IF EXISTS duova_read_published ON public.duova_category_theme_tokens;
CREATE POLICY duova_read_published ON public.duova_category_theme_tokens
FOR SELECT TO authenticated USING (is_published = true AND EXISTS (SELECT 1 FROM public.duova_categories c WHERE c.slug = category_slug AND c.is_visible = true));

DROP POLICY IF EXISTS duova_read_published ON public.duova_category_layout_defaults;
CREATE POLICY duova_read_published ON public.duova_category_layout_defaults
FOR SELECT TO authenticated USING (is_published = true AND EXISTS (SELECT 1 FROM public.duova_categories c WHERE c.slug = category_slug AND c.is_visible = true));

DROP POLICY IF EXISTS duova_read_published ON public.duova_app_layouts;
CREATE POLICY duova_read_published ON public.duova_app_layouts
FOR SELECT TO authenticated USING (is_published = true AND EXISTS (SELECT 1 FROM public.duova_apps a WHERE a.slug = app_slug AND a.is_published AND a.legal_review_status = 'cleared'));

DROP POLICY IF EXISTS duova_read_published ON public.duova_app_launch_assets;
CREATE POLICY duova_read_published ON public.duova_app_launch_assets
FOR SELECT TO authenticated USING (is_published = true AND rights_reviewed = true AND EXISTS (SELECT 1 FROM public.duova_apps a WHERE a.slug = app_slug AND a.is_published AND a.legal_review_status = 'cleared'));

DROP POLICY IF EXISTS duova_read_published ON public.duova_catalog_metadata;
CREATE POLICY duova_read_published ON public.duova_catalog_metadata
FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS duova_owner_select ON public.duova_profiles;
CREATE POLICY duova_owner_select ON public.duova_profiles FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_profiles;
CREATE POLICY duova_owner_insert ON public.duova_profiles FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_profiles;
CREATE POLICY duova_owner_update ON public.duova_profiles FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_profiles;
CREATE POLICY duova_owner_delete ON public.duova_profiles FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_user_settings;
CREATE POLICY duova_owner_select ON public.duova_user_settings FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_user_settings;
CREATE POLICY duova_owner_insert ON public.duova_user_settings FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_user_settings;
CREATE POLICY duova_owner_update ON public.duova_user_settings FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_user_settings;
CREATE POLICY duova_owner_delete ON public.duova_user_settings FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_user_app_state;
CREATE POLICY duova_owner_select ON public.duova_user_app_state FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_user_app_state;
CREATE POLICY duova_owner_insert ON public.duova_user_app_state FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_user_app_state;
CREATE POLICY duova_owner_update ON public.duova_user_app_state FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_user_app_state;
CREATE POLICY duova_owner_delete ON public.duova_user_app_state FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_user_app_library;
CREATE POLICY duova_owner_select ON public.duova_user_app_library FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_user_app_library;
CREATE POLICY duova_owner_insert ON public.duova_user_app_library FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_user_app_library;
CREATE POLICY duova_owner_update ON public.duova_user_app_library FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_user_app_library;
CREATE POLICY duova_owner_delete ON public.duova_user_app_library FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_user_workspaces;
CREATE POLICY duova_owner_select ON public.duova_user_workspaces FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_user_workspaces;
CREATE POLICY duova_owner_insert ON public.duova_user_workspaces FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_user_workspaces;
CREATE POLICY duova_owner_update ON public.duova_user_workspaces FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_user_workspaces;
CREATE POLICY duova_owner_delete ON public.duova_user_workspaces FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_workspace_panes;
CREATE POLICY duova_owner_select ON public.duova_workspace_panes FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_workspace_panes;
CREATE POLICY duova_owner_insert ON public.duova_workspace_panes FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_workspace_panes;
CREATE POLICY duova_owner_update ON public.duova_workspace_panes FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_workspace_panes;
CREATE POLICY duova_owner_delete ON public.duova_workspace_panes FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_notes;
CREATE POLICY duova_owner_select ON public.duova_notes FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_notes;
CREATE POLICY duova_owner_insert ON public.duova_notes FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_notes;
CREATE POLICY duova_owner_update ON public.duova_notes FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_notes;
CREATE POLICY duova_owner_delete ON public.duova_notes FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_note_app_links;
CREATE POLICY duova_owner_select ON public.duova_note_app_links FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_note_app_links;
CREATE POLICY duova_owner_insert ON public.duova_note_app_links FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_note_app_links;
CREATE POLICY duova_owner_update ON public.duova_note_app_links FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_note_app_links;
CREATE POLICY duova_owner_delete ON public.duova_note_app_links FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_vault_items;
CREATE POLICY duova_owner_select ON public.duova_vault_items FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_vault_items;
CREATE POLICY duova_owner_insert ON public.duova_vault_items FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_update ON public.duova_vault_items;
CREATE POLICY duova_owner_update ON public.duova_vault_items FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_delete ON public.duova_vault_items;
CREATE POLICY duova_owner_delete ON public.duova_vault_items FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_user_devices;
CREATE POLICY duova_owner_select ON public.duova_user_devices FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_user_devices;
CREATE POLICY duova_owner_insert ON public.duova_user_devices FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_user_key_envelopes;
CREATE POLICY duova_owner_select ON public.duova_user_key_envelopes FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_insert ON public.duova_user_key_envelopes;
CREATE POLICY duova_owner_insert ON public.duova_user_key_envelopes FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS duova_owner_select ON public.duova_app_suggestions;
CREATE POLICY duova_owner_select ON public.duova_app_suggestions
FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS duova_owner_insert ON public.duova_app_suggestions;
CREATE POLICY duova_owner_insert ON public.duova_app_suggestions
FOR INSERT TO authenticated WITH CHECK (
  user_id = (SELECT auth.uid()) AND review_status = 'submitted'
);

-- ----------- H. GLOBAL THEME AND BASE CATEGORY SEED -----------
-- Brand constants; global theme is meant to be queryable, never sensitive.
INSERT INTO public.duova_global_theme_tokens(theme, version, tokens, is_published) VALUES
('light',1,'{"background":"#FFFFFF","surface":"#FFFFFF","surfaceSecondary":"#F7F9FC","textPrimary":"#0F172A","textSecondary":"#475569","brandBlue":"#0A84FF","brandIndigo":"#5E5CE6","brandPurple":"#BF5AF2","pink":"#FF375F","teal":"#64D2FF","emerald":"#30D158","amber":"#FF9F0A"}'::jsonb,true),
('dark',1,'{"background":"#050508","surface":"#0B0B10","surfaceSecondary":"#111117","textPrimary":"#F5F7FF","textSecondary":"#A3A9BA","brandBlue":"#0A84FF","brandIndigo":"#5E5CE6","brandPurple":"#BF5AF2","pink":"#FF375F","teal":"#64D2FF","emerald":"#30D158","amber":"#FF9F0A"}'::jsonb,true)
ON CONFLICT (theme,version) DO NOTHING;

-- ----------- I. BASE CATEGORY SEED (no app is published by this seed) -----------
INSERT INTO public.duova_categories(slug,display_name,sort_order,description,icon_symbol) VALUES
('social','Social',10,'Feeds, communities and messaging','bubble.left.and.bubble.right'),
('streaming','Streaming',20,'Video, music, podcasts and live content','play.rectangle'),
('activity','Activity',30,'Fitness, wellness and tracking','figure.run'),
('maps_travel','Maps & Travel',40,'Navigation, transportation and trips','map'),
('food','Food & Delivery',50,'Restaurants, ordering, groceries and delivery','fork.knife'),
('fashion','Fashion & Shopping',60,'Products, retail and marketplaces','bag'),
('productivity','Productivity',70,'Docs, spreadsheets, writing and work','doc.text'),
('other','Other',80,'Real estate, dating, events and other services','square.grid.2x2')
ON CONFLICT (slug) DO UPDATE SET
 display_name = EXCLUDED.display_name,
 sort_order = EXCLUDED.sort_order,
 description = EXCLUDED.description,
 icon_symbol = EXCLUDED.icon_symbol;

COMMIT;

-- RUNTIME RULES:
-- (1) User email, auth methods, passkeys, password hashes, OAuth links, session tokens
--     are exclusively owned by Supabase Auth. Never duplicate password fields.
-- (2) first_name_encrypted, last_name_encrypted and encrypted_payload columns MUST
--     receive authenticated client-encrypted, versioned ciphertext. No plaintext tests.
-- (3) True server-side search of encrypted names/notes isn't possible without leakage.
--     Do searchable/decrypted private content locally after authorized unlocking.
-- (4) Even ciphertext leaks some metadata: user ID, linked app slug and update time.
--     Local-only metadata is the more private option. Exposing catalog text is intentional.
-- (5) Browser cookies and native credentials never get uploaded to these tables.
-- (6) Existing v1 profile/state rows remain; do NOT treat old data as encrypted
--     unless it was genuinely encrypted client-side.
-- (7) RLS is NOT proven until ordinary authenticated role tests pass.
-- (8) This schema's setup grants are not a substitute for application validation.
-- (9) Before production, lock down auth settings, backups, rate limiting, verified
--     app assets, CSS sanitizer, content security and account deletion workflows.

