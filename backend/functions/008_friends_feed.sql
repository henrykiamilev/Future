-- ============================================================================
-- FRIENDS FEED v2 — RELATIONSHIP-WEIGHTED RANKING + CAUGHT-UP DETECTION
-- ============================================================================
-- Replaces the v1 reverse-chronological friends feed with a scored feed
-- that ranks by: freshness (50%) + relationship strength (35%) + engagement (15%).
--
-- Returns a finite feed that ends with is_caught_up = TRUE when all
-- eligible friend posts have been seen for today.
--
-- Cursor: (score, id) ranked pagination — same pattern as main feed.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_friends_feed(
    p_cursor_score REAL DEFAULT NULL,
    p_cursor_id UUID DEFAULT NULL,
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
    tags JSONB,
    feed_score REAL,
    is_caught_up BOOLEAN,
    friends_remaining INT,
    display_name TEXT,
    caption TEXT,
    location TEXT
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
    v_total_unseen INT;
    v_capped_limit INT;
BEGIN
    -- Enforce page size ceiling
    v_capped_limit := LEAST(GREATEST(p_limit, 1), 20);

    -- Count total unseen friend posts (active, not yet consumed today)
    SELECT COUNT(*) INTO v_total_unseen
    FROM posts p
    WHERE p.is_hidden = FALSE
      AND p.expires_at > now()
      AND EXISTS (
          SELECT 1 FROM follows f
          WHERE f.follower_id = v_viewer_id
            AND f.following_id = p.user_id
            AND f.is_approved = TRUE
      )
      AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker_id = p.user_id AND b.blocked_id = v_viewer_id)
             OR (b.blocker_id = v_viewer_id AND b.blocked_id = p.user_id)
      )
      AND (SELECT u.is_banned FROM users u WHERE u.id = p.user_id) = FALSE;

    RETURN QUERY
    WITH scored_posts AS (
        SELECT
            p.id,
            p.user_id,
            u.username,
            u.profile_photo_url,
            u.display_name,
            p.caption,
            p.location,
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
            ) AS tags,
            -- Feed score: freshness (50%) + relationship (35%) + engagement (15%)
            (
                0.50 * EXP(-0.693 * EXTRACT(EPOCH FROM (now() - p.created_at)) / 21600.0)
              + 0.35 * get_relationship_strength(v_viewer_id, p.user_id)
              + 0.15 * LEAST(1.0, (p.like_count)::REAL / GREATEST(1, 5)::REAL)
            )::REAL AS feed_score
        FROM posts p
        JOIN users u ON u.id = p.user_id
        WHERE p.is_hidden = FALSE
          AND p.expires_at > now()
          AND u.is_banned = FALSE
          -- Only posts from approved follows
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
    )
    SELECT
        sp.id,
        sp.user_id,
        sp.username,
        sp.profile_photo_url,
        sp.image_url,
        sp.image_width,
        sp.image_height,
        sp.like_count,
        sp.view_count,
        sp.is_liked,
        sp.created_at,
        sp.tags,
        sp.feed_score,
        -- caught_up: TRUE when this page has fewer results than requested
        (COUNT(*) OVER() <= v_capped_limit)::BOOLEAN AS is_caught_up,
        -- remaining count: total unseen minus what we've returned so far
        GREATEST(0, v_total_unseen - (ROW_NUMBER() OVER (ORDER BY sp.feed_score DESC, sp.id DESC))::INT)::INT AS friends_remaining,
        sp.display_name,
        sp.caption,
        sp.location
    FROM scored_posts sp
    -- Cursor pagination on (score, id)
    WHERE (p_cursor_score IS NULL OR
           sp.feed_score < p_cursor_score OR
           (sp.feed_score = p_cursor_score AND sp.id < p_cursor_id))
    ORDER BY sp.feed_score DESC, sp.id DESC
    LIMIT v_capped_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;
