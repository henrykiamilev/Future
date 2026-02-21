-- ============================================================================
-- PHASE 0 REMEDIATION — Run in Supabase SQL Editor (one shot)
-- ============================================================================
-- Fixes 3 issues preventing the app from working:
--   A) Ambiguous get_friends_feed overload (feed crash)
--   B) Missing public.users row for auth user (profile 404)
--   C) Storage path verification (image HTTP 400)
--
-- Safe to re-run. Uses IF EXISTS and ON CONFLICT throughout.
-- ============================================================================


-- ============================================================================
-- FIX A: DROP THE OLD v1 get_friends_feed OVERLOAD
-- ============================================================================
-- 016_security_hardening.sql accidentally created a v1 overload:
--   get_friends_feed(p_cursor TIMESTAMPTZ, p_limit INT)
-- The v2 version (from deploy_feed_v2.sql) is:
--   get_friends_feed(p_cursor_score REAL, p_cursor_id UUID, p_limit INT)
-- When the iOS app sends NULL cursors, Postgres can't disambiguate.
-- ============================================================================

-- Step A1: Drop the stale v1 overload by its exact signature
DROP FUNCTION IF EXISTS public.get_friends_feed(TIMESTAMPTZ, INT);

-- Step A2: Verify only the v2 overload remains
-- EXPECTED: Exactly 1 row showing (p_cursor_score real, p_cursor_id uuid, p_limit integer)
SELECT
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS arguments,
    pg_get_function_result(p.oid) AS returns
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'get_friends_feed';


-- ============================================================================
-- FIX B: ENSURE public.users ROW EXISTS FOR YOUR AUTH ACCOUNT
-- ============================================================================
-- The auth trigger (handle_new_user) should have created this row on signup.
-- If it didn't fire (e.g. trigger wasn't deployed yet when you signed up),
-- we backfill now.
--
-- IMPORTANT: Replace 'YOUR_USERNAME' below with your desired username.
-- Your auth UUID is pulled automatically from auth.users.
-- ============================================================================

-- Step B1: Check if you already have a public.users row
-- EXPECTED: If this returns 0 rows, proceed to B2
SELECT u.id, u.username, u.created_at
FROM public.users u
WHERE u.id = auth.uid();

-- Step B2: Backfill your user row (safe — ON CONFLICT does nothing)
-- CHANGE 'your_username' to whatever you want (3-30 chars, lowercase recommended)
INSERT INTO public.users (id, username)
VALUES (
    auth.uid(),
    'your_username'
)
ON CONFLICT (id) DO NOTHING;

-- Step B3: Verify the row now exists
-- EXPECTED: 1 row with your UUID and username
SELECT u.id, u.username, u.visibility, u.is_banned, u.created_at
FROM public.users u
WHERE u.id = auth.uid();

-- Step B4: Verify the auth trigger exists for future signups
-- EXPECTED: 1 row showing on_auth_user_created trigger
SELECT tgname, tgtype, tgenabled
FROM pg_trigger
WHERE tgname = 'on_auth_user_created';


-- ============================================================================
-- FIX C: STORAGE — VERIFY BUCKET AND SEED IMAGE PATHS
-- ============================================================================
-- The seed data writes URLs like:
--   https://rylyzntjznnwmysszbzq.supabase.co/storage/v1/object/public/posts/seed/sofia_1.jpg
--   https://rylyzntjznnwmysszbzq.supabase.co/storage/v1/object/public/posts/profiles/sofia.jpg
--
-- HTTP 400 means either:
--   (a) The 'posts' bucket doesn't exist or isn't public, OR
--   (b) The files were never uploaded to seed/ and profiles/ folders
--
-- Run this query to check what the bucket looks like:
-- ============================================================================

-- Step C1: Verify the 'posts' bucket exists and is public
-- EXPECTED: 1 row with name='posts', public=true
SELECT id, name, public, created_at
FROM storage.buckets
WHERE name = 'posts';

-- Step C2: If the bucket doesn't exist, create it (uncomment to run):
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('posts', 'posts', true)
-- ON CONFLICT (id) DO UPDATE SET public = true;

-- Step C3: List what's actually in the posts bucket
-- EXPECTED: You should see objects in seed/ and profiles/ folders
SELECT name, bucket_id, created_at
FROM storage.objects
WHERE bucket_id = 'posts'
ORDER BY name
LIMIT 50;

-- Step C4: Check specifically for the seed images referenced by demo content
-- EXPECTED: 12 rows (6 profiles + 6 seed posts)
SELECT name, bucket_id
FROM storage.objects
WHERE bucket_id = 'posts'
  AND (name LIKE 'seed/%' OR name LIKE 'profiles/%')
ORDER BY name;


-- ============================================================================
-- VERIFICATION: TEST THE FEED FUNCTION
-- ============================================================================
-- After running fixes A and B, test the friends feed:
-- EXPECTED: Returns rows (or empty array if you don't follow anyone) — NO ERROR

SELECT * FROM get_friends_feed(
    p_cursor_score := NULL,
    p_cursor_id := NULL,
    p_limit := 20
);

-- Test your profile:
-- EXPECTED: 1 row with your profile data
SELECT * FROM get_user_profile(auth.uid());
