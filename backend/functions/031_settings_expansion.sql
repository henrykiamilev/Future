-- ============================================================================
-- SETTINGS EXPANSION — Notification prefs, connected accounts, blocked users
-- ============================================================================

-- 1. Notification preferences (per-type on/off)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS notify_likes BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notify_comments BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notify_follows BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notify_reactions BOOLEAN NOT NULL DEFAULT true;

-- 2. Connected accounts (TikTok, X, Website)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS tiktok_handle TEXT
    CONSTRAINT chk_tiktok CHECK (tiktok_handle IS NULL OR char_length(tiktok_handle) <= 50);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS x_handle TEXT
    CONSTRAINT chk_x_handle CHECK (x_handle IS NULL OR char_length(x_handle) <= 50);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS website_url TEXT
    CONSTRAINT chk_website CHECK (website_url IS NULL OR char_length(website_url) <= 200);

-- ============================================================================
-- get_blocked_users: Return all users blocked by the current user
-- ============================================================================
CREATE OR REPLACE FUNCTION get_blocked_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_result JSONB;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', u.id,
            'username', u.username,
            'displayName', u.display_name,
            'profilePhotoUrl', u.profile_photo_url
        )
        ORDER BY b.created_at DESC
    ), '[]'::jsonb)
    INTO v_result
    FROM blocks b
    JOIN users u ON u.id = b.blocked_id
    WHERE b.blocker_id = v_uid;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- unblock_user: Remove a block
-- ============================================================================
CREATE OR REPLACE FUNCTION unblock_user(p_target_user_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM blocks
    WHERE blocker_id = auth.uid()
      AND blocked_id = p_target_user_id::UUID;
END;
$$;

-- ============================================================================
-- Update get_user_profile to return new columns
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
    tiktok_handle TEXT,
    x_handle TEXT,
    website_url TEXT,
    total_likes BIGINT,
    follower_count BIGINT,
    following_count BIGINT,
    is_following BOOLEAN,
    is_follower BOOLEAN,
    follow_is_pending BOOLEAN,
    is_own_profile BOOLEAN,
    comments_enabled BOOLEAN,
    onboarding_completed_at TIMESTAMPTZ,
    profile_theme TEXT,
    notify_likes BOOLEAN,
    notify_comments BOOLEAN,
    notify_follows BOOLEAN,
    notify_reactions BOOLEAN,
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
        u.tiktok_handle,
        u.x_handle,
        u.website_url,
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
        u.profile_theme,
        u.notify_likes,
        u.notify_comments,
        u.notify_follows,
        u.notify_reactions,
        -- Signature posts (max 3)
        COALESCE(
            (SELECT jsonb_agg(sig ORDER BY created_at DESC)
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
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;
