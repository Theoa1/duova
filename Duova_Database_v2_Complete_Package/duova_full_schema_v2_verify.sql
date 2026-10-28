-- DUOVA v2 — READ-ONLY INSTALL VERIFICATION
-- Run in SQL Editor AFTER duova_full_schema_v2_dev.sql
-- SQL Editor privileges bypass RLS; this is CONFIG verification only.

-- 1. Tables and enabled RLS
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled,
       (SELECT count(*) FROM pg_policies p
        WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS policy_count
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname LIKE 'duova_%'
ORDER BY c.relname;

-- 2. Inspect category seed
SELECT slug, display_name, sort_order, is_visible
FROM public.duova_categories ORDER BY sort_order;

-- 3. Ensure authenticated has no writable privileges on public catalog tables
SELECT table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public' AND grantee='authenticated'
 AND table_name IN ('duova_apps','duova_categories','duova_style_assets','duova_adapter_versions','duova_app_layouts')
ORDER BY table_name, privilege_type;

-- 4. Confirm Supabase Auth user table remains authoritative
SELECT EXISTS(SELECT 1 FROM information_schema.tables
              WHERE table_schema='auth' AND table_name='users') AS auth_users_exists,
       EXISTS(SELECT 1 FROM information_schema.tables
              WHERE table_schema='auth' AND table_name='identities') AS auth_identities_exists;

-- 5. Verify no custom plaintext password column was created in a Duova public table
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema='public' AND table_name LIKE 'duova_%'
  AND column_name IN ('password', 'password_hash', 'password_plaintext', 'oauth_access_token','cookie_jar');
-- Expect 0 rows for query 5.
