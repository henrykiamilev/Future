-- ============================================================================
-- DISCOVER v2 — DAILY-CAPPED EXPLORE + SUGGESTED USERS
-- ============================================================================
-- Discovery is important but must NOT become an addiction engine.
-- Daily cap: 15 items/day (configurable per user).
-- Returns is_exhausted + items_remaining so the client can show end states.
-- Max 1 post per author per day in discovery for diversity.
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
    LIMIT LEAST(GREATEST(p_limit, 1), 50);
$$ LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- EXPLORE POSTS v2 (daily-capped, diversity-constrained)
-- --------------------------------------------------------------------------
-- Daily cap of 15 items. Client calls this with p_limit = 10 (page size).
-- Server clamps page size to remaining budget.
-- Returns is_exhausted = TRUE and items_remaining = 0 when cap reached.
-- DISTINCT ON (user_id) ensures max 1 post per author for diversity.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_explore_posts(p_limit INT DEFAULT 10)
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
    score DOUBLE PRECISION,
    feed_score REAL,
    is_caught_up BOOLEAN,
    friends_remaining INT,
    is_exhausted BOOLEAN,
    items_remaining INT,
    display_name TEXT,
    caption TEXT,
    location TEXT
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
    v_daily_cap INT;
    v_items_seen INT;
    v_budget INT;
    v_capped_limit INT;
BEGIN
    -- Get or create today's daily feed state
    INSERT INTO daily_feed_state (user_id, state_date)
    VALUES (v_viewer_id, CURRENT_DATE)
    ON CONFLICT (user_id, state_date) DO NOTHING;

    SELECT dfs.discovery_items_seen, dfs.discovery_cap
    INTO v_items_seen, v_daily_cap
    FROM daily_feed_state dfs
    WHERE dfs.user_id = v_viewer_id AND dfs.state_date = CURRENT_DATE;

    v_budget := GREATEST(0, v_daily_cap - v_items_seen);

    -- If daily cap reached, return empty result (client detects via empty posts array)
    IF v_budget <= 0 THEN
        RETURN;
    END IF;

    -- Clamp page size to remaining budget
    v_capped_limit := LEAST(GREATEST(p_limit, 1), v_budget);

    RETURN QUERY
    WITH ranked_posts AS (
        SELECT DISTINCT ON (p.user_id)  -- Max 1 post per author (diversity)
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
            p.created_at,
            fs.base_score
        FROM feed_scores fs
        JOIN posts p ON p.id = fs.post_id
        JOIN users u ON u.id = p.user_id
        WHERE u.visibility = 'public'
          AND u.is_banned = FALSE
          AND p.is_hidden = FALSE
          AND p.expires_at > now()
          -- Exclude own posts
          AND p.user_id != v_viewer_id
          -- Exclude posts from people the viewer already follows
          AND NOT EXISTS (
              SELECT 1 FROM follows f
              WHERE f.follower_id = v_viewer_id AND f.following_id = p.user_id
                AND f.is_approved = TRUE
          )
          -- Block check
          AND NOT EXISTS (
              SELECT 1 FROM blocks b
              WHERE (b.blocker_id = p.user_id AND b.blocked_id = v_viewer_id)
                 OR (b.blocker_id = v_viewer_id AND b.blocked_id = p.user_id)
          )
        ORDER BY p.user_id, fs.base_score DESC  -- best post per author
    )
    SELECT
        rp.id,
        rp.user_id,
        rp.username,
        rp.profile_photo_url AS author_photo,
        rp.image_url,
        rp.image_width,
        rp.image_height,
        rp.like_count,
        0::BIGINT AS view_count,
        FALSE AS is_liked,
        rp.created_at,
        '[]'::JSONB AS tags,
        rp.base_score AS score,
        NULL::REAL AS feed_score,
        NULL::BOOLEAN AS is_caught_up,
        NULL::INT AS friends_remaining,
        -- is_exhausted: TRUE if this page fills the remaining budget
        (v_budget <= v_capped_limit)::BOOLEAN AS is_exhausted,
        -- items_remaining: how many more after this page
        GREATEST(0, v_budget - (ROW_NUMBER() OVER (ORDER BY rp.base_score DESC))::INT)::INT AS items_remaining,
        rp.display_name,
        rp.caption,
        rp.location
    FROM ranked_posts rp
    ORDER BY rp.base_score DESC
    LIMIT v_capped_limit;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp;
