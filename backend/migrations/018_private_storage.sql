-- ============================================================================
-- MIGRATION 018: Private Storage + Authenticated Image Access
-- ============================================================================
-- Converts the 'posts' storage bucket from public to private.
--
-- Changes:
--   1. Strip full public URLs from posts.image_url and users.profile_photo_url
--      to relative paths (e.g. "seeds/sofia_1.jpg" instead of full URL)
--   2. Add storage RLS policies for authenticated access
--   3. Bucket must be flipped to private in the Supabase Dashboard AFTER
--      deploying the iOS update with auth headers.
--
-- Safe to re-run: uses WHERE + LIKE guard, ON CONFLICT, and IF NOT EXISTS.
-- Reversible: relative paths still work with public bucket if you revert.
-- ============================================================================


-- ============================================================================
-- STEP 1: Strip known URL prefix from posts.image_url
-- ============================================================================
-- Only strips the EXACT known prefix. Leaves all other values unchanged.

UPDATE posts
SET image_url = REPLACE(
    image_url,
    'https://rylyzntjznnwmysszbzq.supabase.co/storage/v1/object/public/posts/',
    ''
)
WHERE image_url LIKE 'https://rylyzntjznnwmysszbzq.supabase.co/storage/v1/object/public/posts/%';


-- ============================================================================
-- STEP 2: Strip known URL prefix from users.profile_photo_url
-- ============================================================================

UPDATE users
SET profile_photo_url = REPLACE(
    profile_photo_url,
    'https://rylyzntjznnwmysszbzq.supabase.co/storage/v1/object/public/posts/',
    ''
)
WHERE profile_photo_url LIKE 'https://rylyzntjznnwmysszbzq.supabase.co/storage/v1/object/public/posts/%';


-- ============================================================================
-- STEP 3: Storage RLS — authenticated read for all objects in 'posts' bucket
-- ============================================================================
-- Visibility model: any authenticated user can view any image.
-- This matches the Discover feed where public profiles are visible to all.

-- Enable RLS on storage.objects (may already be enabled by Supabase)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Read: any authenticated user can read objects in the posts bucket
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE policyname = 'storage_authenticated_read'
          AND tablename = 'objects'
          AND schemaname = 'storage'
    ) THEN
        CREATE POLICY storage_authenticated_read ON storage.objects
            FOR SELECT
            USING (bucket_id = 'posts' AND auth.uid() IS NOT NULL);
    END IF;
END $$;

-- Upload: any authenticated user can upload to the posts bucket
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE policyname = 'storage_user_upload'
          AND tablename = 'objects'
          AND schemaname = 'storage'
    ) THEN
        CREATE POLICY storage_user_upload ON storage.objects
            FOR INSERT
            WITH CHECK (bucket_id = 'posts' AND auth.uid() IS NOT NULL);
    END IF;
END $$;

-- Update: allow authenticated users to update their own uploads
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE policyname = 'storage_user_update'
          AND tablename = 'objects'
          AND schemaname = 'storage'
    ) THEN
        CREATE POLICY storage_user_update ON storage.objects
            FOR UPDATE
            USING (bucket_id = 'posts' AND auth.uid() = owner)
            WITH CHECK (bucket_id = 'posts' AND auth.uid() = owner);
    END IF;
END $$;


-- ============================================================================
-- STEP 4: Verification queries (run manually after migration)
-- ============================================================================
-- Check that no full URLs remain:
-- SELECT count(*) FROM posts WHERE image_url LIKE 'https://%';
-- SELECT count(*) FROM users WHERE profile_photo_url LIKE 'https://%';
-- EXPECTED: 0 for both (except any externally-hosted images)

-- Check storage policies exist:
-- SELECT policyname FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage';
-- EXPECTED: storage_authenticated_read, storage_user_upload, storage_user_update


-- ============================================================================
-- DEPLOYMENT ORDER (critical — do NOT flip bucket before iOS update):
-- ============================================================================
-- 1. Deploy iOS update with backward-compatible URL handling (hasPrefix check)
-- 2. Run this migration (strips URLs + adds RLS policies)
-- 3. In Supabase Dashboard → Storage → posts bucket → Settings → toggle Public OFF
-- 4. Verify: direct public URL returns 401 in browser; app still loads images
