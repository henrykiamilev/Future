-- ============================================================================
-- PROFILE QUERIES — RENDER-READY (NO N+1)
-- ============================================================================

-- --------------------------------------------------------------------------
-- GET USER PROFILE (with signature + live posts + stats in one query)
-- --------------------------------------------------------------------------
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
