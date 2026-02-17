-- ============================================================================
-- MIGRATION 003: CRITICAL FIXES
-- Account creation atomicity, profile decode alignment, delete account,
-- onboarding persistence, followers column fix
-- ============================================================================
--
-- Run this in Supabase SQL Editor AFTER migration 002.
-- If you have NOT run 002 yet, run 002 first (it has the column fix too).
--
-- This migration is IDEMPOTENT — safe to run multiple times.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1) ONBOARDING: Add server-side completion timestamp
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

-- ============================================================================
-- 2) AUTH TRIGGER: Atomically create public.users on signup
-- ============================================================================
-- When Supabase GoTrue creates an auth.users row, this trigger
-- automatically inserts the corresponding public.users row.
-- The username is passed via raw_user_meta_data during signUp().
-- This runs INSIDE the auth.users INSERT transaction — if the
-- public.users INSERT fails, the entire signup is rolled back.
-- No orphaned records possible.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, username)
    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data->>'username',
            'user_' || LEFT(NEW.id::TEXT, 8)
        )
    );
    RETURN NEW;
END;
$$;

-- Drop if exists to avoid duplicate trigger error
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- 3) RLS POLICIES: Add missing INSERT and DELETE on users
-- ============================================================================

-- Safe: DROP IF EXISTS + CREATE avoids errors on re-run
DO $$
BEGIN
    -- INSERT policy (defense-in-depth; trigger uses SECURITY DEFINER)
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'users' AND policyname = 'users_insert_own'
    ) THEN
        CREATE POLICY users_insert_own ON public.users
            FOR INSERT
            WITH CHECK (id = auth.uid());
    END IF;

    -- DELETE policy (for delete_own_account and PostgREST deletes)
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'users' AND policyname = 'users_delete_own'
    ) THEN
        CREATE POLICY users_delete_own ON public.users
            FOR DELETE
            USING (id = auth.uid());
    END IF;
END
$$;

-- ============================================================================
-- 4) DELETE ACCOUNT: Removes both public.users and auth.users
-- ============================================================================
-- SECURITY DEFINER runs as postgres, which has access to auth schema.
-- Deleting public.users cascades to posts, follows, likes, comments, etc.
-- Deleting auth.users prevents re-authentication.
-- ============================================================================

CREATE OR REPLACE FUNCTION delete_own_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'not_authenticated';
    END IF;

    -- Delete from public.users (cascades to posts, follows, likes, etc.)
    DELETE FROM public.users WHERE id = v_user_id;

    -- Delete from auth.users to prevent re-authentication
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- ============================================================================
-- 5) PROFILE FUNCTION: Add comments_enabled + onboarding_completed_at
-- ============================================================================
-- Replaces the existing function. The RETURNS TABLE now includes the
-- two new columns that the Swift client expects.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_profile(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT,
    bio TEXT,
    visibility account_visibility,
    instagram_handle TEXT,
    snapchat_handle TEXT,
    total_likes BIGINT,
    follower_count BIGINT,
    following_count BIGINT,
    is_following BOOLEAN,
    is_follower BOOLEAN,
    follow_is_pending BOOLEAN,
    is_own_profile BOOLEAN,
    comments_enabled BOOLEAN,
    onboarding_completed_at TIMESTAMPTZ,
    signature_posts JSONB,
    live_posts JSONB
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url,
        u.bio,
        u.visibility,
        u.instagram_handle,
        u.snapchat_handle,
        u.total_likes,
        u.follower_count,
        u.following_count,
        -- Relationship status
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.follower_id = v_viewer_id
              AND f.following_id = u.id
              AND f.is_approved = TRUE
        ) AS is_following,
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.follower_id = u.id
              AND f.following_id = v_viewer_id
              AND f.is_approved = TRUE
        ) AS is_follower,
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.follower_id = v_viewer_id
              AND f.following_id = u.id
              AND f.is_approved = FALSE
        ) AS follow_is_pending,
        (u.id = v_viewer_id) AS is_own_profile,
        u.comments_enabled,
        u.onboarding_completed_at,
        -- Signature posts (max 3)
        COALESCE(
            (SELECT jsonb_agg(sig ORDER BY sig.created_at DESC)
             FROM (
                SELECT
                    jsonb_build_object(
                        'id', p.id,
                        'image_url', p.image_url,
                        'image_width', p.image_width,
                        'image_height', p.image_height,
                        'like_count', p.like_count,
                        'created_at', p.created_at,
                        'tags', COALESCE(
                            (SELECT jsonb_agg(jsonb_build_object(
                                'label', t.label,
                                'external_url', t.external_url
                            )) FROM tags t WHERE t.post_id = p.id),
                            '[]'::JSONB
                        )
                    ) AS sig,
                    p.created_at
                FROM posts p
                WHERE p.user_id = u.id
                  AND p.is_signature = TRUE
                  AND p.is_hidden = FALSE
             ) sub
            ),
            '[]'::JSONB
        ) AS signature_posts,
        -- Live posts (last 3 active, non-signature)
        COALESCE(
            (SELECT jsonb_agg(live ORDER BY live_created DESC)
             FROM (
                SELECT
                    jsonb_build_object(
                        'id', p.id,
                        'image_url', p.image_url,
                        'image_width', p.image_width,
                        'image_height', p.image_height,
                        'like_count', p.like_count,
                        'created_at', p.created_at,
                        'tags', COALESCE(
                            (SELECT jsonb_agg(jsonb_build_object(
                                'label', t.label,
                                'external_url', t.external_url
                            )) FROM tags t WHERE t.post_id = p.id),
                            '[]'::JSONB
                        )
                    ) AS live,
                    p.created_at AS live_created
                FROM posts p
                WHERE p.user_id = u.id
                  AND p.expires_at > now()
                  AND p.is_hidden = FALSE
                ORDER BY p.created_at DESC
                LIMIT 3
             ) sub
            ),
            '[]'::JSONB
        ) AS live_posts
    FROM users u
    WHERE u.id = p_user_id
      AND u.is_banned = FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================================
-- 6) FOLLOWERS FIX: Replace f.status with f.is_approved
-- ============================================================================
-- These CREATE OR REPLACE the existing functions from migration 002.
-- If 002 was already run with the bug, this overwrites with the fix.
-- If 002 was run with the fix already, this is a no-op (same definition).
-- ============================================================================

CREATE OR REPLACE FUNCTION get_followers(
    p_user_id UUID,
    p_limit INT DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url
    FROM public.follows f
    JOIN public.users u ON u.id = f.follower_id
    WHERE f.following_id = p_user_id
      AND f.is_approved = TRUE
    ORDER BY f.created_at DESC
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION get_following(
    p_user_id UUID,
    p_limit INT DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url
    FROM public.follows f
    JOIN public.users u ON u.id = f.following_id
    WHERE f.follower_id = p_user_id
      AND f.is_approved = TRUE
    ORDER BY f.created_at DESC
    LIMIT p_limit;
END;
$$;

COMMIT;
