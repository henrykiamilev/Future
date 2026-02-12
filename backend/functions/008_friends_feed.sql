-- ============================================================================
-- FRIENDS FEED — REVERSE CHRONOLOGICAL WITH CURSOR PAGINATION
-- ============================================================================
-- Shows posts from followed users (approved follows only).
-- 3-day visibility window enforced.
-- Render-ready response (no N+1).
-- ============================================================================

CREATE OR REPLACE FUNCTION get_friends_feed(
    p_cursor TIMESTAMPTZ DEFAULT NULL,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    username TEXT,
    author_photo TEXT,
    image_url TEXT,
    image_width INT,
    image_height INT,
    like_count BIGINT,
    view_count BIGINT,
    is_liked BOOLEAN,
    created_at TIMESTAMPTZ,
    tags JSONB
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.user_id,
        u.username,
        u.profile_photo_url,
        p.image_url,
        p.image_width,
        p.image_height,
        p.like_count,
        p.view_count,
        EXISTS (
            SELECT 1 FROM likes l
            WHERE l.post_id = p.id AND l.user_id = v_viewer_id
        ) AS is_liked,
        p.created_at,
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'label', t.label,
                    'external_url', t.external_url,
                    'position_x', t.position_x,
                    'position_y', t.position_y
                )
            )
            FROM tags t WHERE t.post_id = p.id),
            '[]'::JSONB
        ) AS tags
    FROM posts p
    JOIN users u ON u.id = p.user_id
    WHERE p.is_hidden = FALSE
      AND p.expires_at > now()
      AND u.is_banned = FALSE
      -- Only posts from users the viewer follows
      AND EXISTS (
          SELECT 1 FROM follows f
          WHERE f.follower_id = v_viewer_id
            AND f.following_id = p.user_id
            AND f.is_approved = TRUE
      )
      -- Block check
      AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker_id = p.user_id AND b.blocked_id = v_viewer_id)
             OR (b.blocker_id = v_viewer_id AND b.blocked_id = p.user_id)
      )
      -- Cursor pagination
      AND (p_cursor IS NULL OR p.created_at < p_cursor)
    ORDER BY p.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
