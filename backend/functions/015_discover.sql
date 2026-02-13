-- ============================================================================
-- DISCOVER — SUGGESTED USERS & EXPLORE POSTS
-- ============================================================================

-- --------------------------------------------------------------------------
-- SUGGESTED USERS (trending / most-followed users the viewer doesn't follow)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_suggested_users(p_limit INT DEFAULT 10)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT,
    follower_count BIGINT
) AS $$
    SELECT u.id, u.username, u.display_name, u.profile_photo_url, u.follower_count
    FROM users u
    WHERE u.visibility = 'public'
      AND u.is_banned = FALSE
      AND u.id != auth_uid()
      AND NOT EXISTS (
          SELECT 1 FROM follows f
          WHERE f.follower_id = auth_uid() AND f.following_id = u.id
      )
      AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker_id = auth_uid() AND b.blocked_id = u.id)
             OR (b.blocker_id = u.id AND b.blocked_id = auth_uid())
      )
    ORDER BY u.follower_count DESC
    LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- --------------------------------------------------------------------------
-- EXPLORE POSTS (top-ranked posts from pre-computed feed_scores)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_explore_posts(p_limit INT DEFAULT 30)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    username TEXT,
    author_photo TEXT,
    image_url TEXT,
    image_width INT,
    image_height INT,
    like_count BIGINT,
    created_at TIMESTAMPTZ,
    score DOUBLE PRECISION
) AS $$
    SELECT
        p.id,
        p.user_id,
        u.username,
        u.profile_photo_url,
        p.image_url,
        p.image_width,
        p.image_height,
        p.like_count,
        p.created_at,
        fs.base_score
    FROM feed_scores fs
    JOIN posts p ON p.id = fs.post_id
    JOIN users u ON u.id = p.user_id
    WHERE u.visibility = 'public'
      AND u.is_banned = FALSE
      AND p.is_hidden = FALSE
      AND p.expires_at > now()
    ORDER BY fs.base_score DESC
    LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
