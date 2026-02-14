-- ============================================================================
-- FEED RANKING — PRE-SCORED TABLE + LIGHTWEIGHT READ
-- ============================================================================
--
-- ARCHITECTURE:
--   1. pg_cron runs refresh_feed_scores() every 5 minutes
--   2. That function pre-computes base_score for all active posts using
--      rolling p95 normalization (stable across traffic spikes)
--   3. get_main_feed() reads pre-scored table, adds personalization at
--      read time, applies exposure cap, and returns render-ready rows
--
-- SCORING FORMULA:
--   base_score = 0.30 * normalized_likes
--              + 0.25 * normalized_velocity
--              + 0.30 * freshness
--
--   final_score = base_score + 0.15 * is_following
--
-- NORMALIZATION (rolling p95 — stable):
--   normalized_likes    = ln(1 + like_count) / ln(1 + p95_likes)
--   normalized_velocity = velocity_1h / GREATEST(1, p95_velocity)
--   freshness           = EXP(-0.05 * hours_since_creation)
--
-- Exposure cap: max 2 posts per author per viewer per rolling 24h window
-- ============================================================================

-- --------------------------------------------------------------------------
-- RECORD A POST VIEW (replaces the old post_views table INSERT)
-- --------------------------------------------------------------------------
-- Call this from the client when a post enters the viewport.
-- Directly increments the hourly bucket and the denormalized counter.
-- No raw row storage — O(1) per view instead of O(N).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION record_post_view(p_post_id UUID)
RETURNS void AS $$
BEGIN
    -- Increment denormalized counter on posts
    UPDATE posts SET view_count = view_count + 1
    WHERE id = p_post_id;

    -- Upsert into hourly bucket (for velocity calculation)
    INSERT INTO post_view_hourly (post_id, hour_bucket, view_count)
    VALUES (p_post_id, date_trunc('hour', now()), 1)
    ON CONFLICT (post_id, hour_bucket)
    DO UPDATE SET view_count = post_view_hourly.view_count + 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- REFRESH FEED SCORES (pg_cron job — runs every 5 minutes)
-- --------------------------------------------------------------------------
-- Pre-computes base_score for all active posts. Uses rolling p95 stats
-- from the last 24 hours for stable normalization.
-- Cost: one sequential scan of active posts (~1M DAU → ~3M active posts)
-- but only runs every 5 minutes, not per-request.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_feed_scores()
RETURNS void AS $$
DECLARE
    v_p95_likes    DOUBLE PRECISION;
    v_p95_velocity DOUBLE PRECISION;
    v_like_w       DOUBLE PRECISION := 0.30;
    v_velocity_w   DOUBLE PRECISION := 0.25;
    v_freshness_w  DOUBLE PRECISION := 0.30;
    v_decay_rate   DOUBLE PRECISION := 0.05;  -- half-life ~14 hours
BEGIN
    -- ──────────────────────────────────────────────────
    -- Step 1: Compute rolling p95 stats from active posts
    -- ──────────────────────────────────────────────────
    SELECT
        GREATEST(1, percentile_cont(0.95) WITHIN GROUP (ORDER BY p.like_count)),
        GREATEST(1, percentile_cont(0.95) WITHIN GROUP (ORDER BY COALESCE(v.velocity, 0)))
    INTO v_p95_likes, v_p95_velocity
    FROM posts p
    LEFT JOIN LATERAL (
        SELECT SUM(pvh.view_count) AS velocity
        FROM post_view_hourly pvh
        WHERE pvh.post_id = p.id
          AND pvh.hour_bucket >= date_trunc('hour', now()) - INTERVAL '1 hour'
    ) v ON TRUE
    WHERE p.is_hidden = FALSE
      AND p.expires_at > now();

    -- ──────────────────────────────────────────────────
    -- Step 2: Upsert scores for all active posts
    -- ──────────────────────────────────────────────────
    INSERT INTO feed_scores (post_id, author_id, base_score, scored_at)
    SELECT
        p.id,
        p.user_id,
        (
            v_like_w * (ln(1 + p.like_count) / ln(1 + v_p95_likes))
          + v_velocity_w * (COALESCE(v.velocity, 0)::DOUBLE PRECISION / v_p95_velocity)
          + v_freshness_w * EXP(-v_decay_rate * EXTRACT(EPOCH FROM (now() - p.created_at)) / 3600.0)
        ),
        now()
    FROM posts p
    LEFT JOIN LATERAL (
        SELECT SUM(pvh.view_count) AS velocity
        FROM post_view_hourly pvh
        WHERE pvh.post_id = p.id
          AND pvh.hour_bucket >= date_trunc('hour', now()) - INTERVAL '1 hour'
    ) v ON TRUE
    WHERE p.is_hidden = FALSE
      AND p.expires_at > now()
    ON CONFLICT (post_id)
    DO UPDATE SET
        base_score = EXCLUDED.base_score,
        scored_at = EXCLUDED.scored_at;

    -- ──────────────────────────────────────────────────
    -- Step 3: Remove scores for expired/hidden posts
    -- ──────────────────────────────────────────────────
    DELETE FROM feed_scores
    WHERE post_id NOT IN (
        SELECT id FROM posts
        WHERE is_hidden = FALSE AND expires_at > now()
    );
END;
$$ LANGUAGE plpgsql;

-- Schedule via Supabase pg_cron:
-- SELECT cron.schedule('refresh-feed-scores', '*/5 * * * *', 'SELECT refresh_feed_scores()');

-- --------------------------------------------------------------------------
-- MAIN FEED (Discovery — ranked, reads pre-scored table)
-- --------------------------------------------------------------------------
-- Cost per request: index scan on feed_scores + small JOINs.
-- No more 3M-row sequential scan. No correlated subqueries.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_main_feed(
    p_cursor_score DOUBLE PRECISION DEFAULT NULL,
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
    score DOUBLE PRECISION,
    tags JSONB
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
    v_personal_w DOUBLE PRECISION := 0.15;
    v_max_author_exposure INT := 2;
BEGIN
    RETURN QUERY
    WITH viewer_follows AS (
        -- Pre-fetch viewer's follow list (typically small set)
        SELECT f.following_id
        FROM follows f
        WHERE f.follower_id = v_viewer_id
          AND f.is_approved = TRUE
    ),
    viewer_blocks AS (
        -- Pre-fetch viewer's block list
        SELECT b.blocked_id AS uid FROM blocks b WHERE b.blocker_id = v_viewer_id
        UNION ALL
        SELECT b.blocker_id AS uid FROM blocks b WHERE b.blocked_id = v_viewer_id
    ),
    scored_feed AS (
        SELECT
            fs.post_id,
            fs.author_id,
            fs.base_score + (CASE WHEN vf.following_id IS NOT NULL THEN v_personal_w ELSE 0.0 END) AS final_score,
            -- Exposure cap: count from rolling 24h window
            COALESCE(fe.exposure_count, 0) AS author_exposure,
            -- Reset exposure counter if window expired
            CASE WHEN fe.window_start IS NOT NULL AND fe.window_start > now() - INTERVAL '24 hours'
                THEN COALESCE(fe.exposure_count, 0) ELSE 0 END AS active_exposure
        FROM feed_scores fs
        LEFT JOIN viewer_follows vf ON vf.following_id = fs.author_id
        LEFT JOIN feed_exposures fe ON fe.viewer_id = v_viewer_id AND fe.author_id = fs.author_id
        WHERE fs.author_id NOT IN (SELECT uid FROM viewer_blocks)
    ),
    filtered AS (
        SELECT sf.*
        FROM scored_feed sf
        WHERE sf.active_exposure < v_max_author_exposure
          -- Cursor-based pagination: score DESC, then id DESC for tie-breaking
          AND (
              p_cursor_score IS NULL
              OR sf.final_score < p_cursor_score
              OR (sf.final_score = p_cursor_score AND sf.post_id < p_cursor_id)
          )
        ORDER BY sf.final_score DESC, sf.post_id DESC
        LIMIT p_limit
    )
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
        f.final_score,
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
    FROM filtered f
    JOIN posts p ON p.id = f.post_id
    JOIN users u ON u.id = p.user_id
    WHERE u.visibility = 'public'
      AND u.is_banned = FALSE
      AND p.is_hidden = FALSE
      AND p.expires_at > now()
    ORDER BY f.final_score DESC, f.post_id DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- RECORD FEED EXPOSURE (rolling 24h window)
-- --------------------------------------------------------------------------
-- Called after serving feed results. Uses rolling window instead of calendar day.
-- If the window has expired (>24h), resets the counter to 1.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION record_feed_exposures(p_author_ids UUID[])
RETURNS void AS $$
BEGIN
    INSERT INTO feed_exposures (viewer_id, author_id, exposure_count, window_start)
    SELECT auth_uid(), aid, 1, now()
    FROM unnest(p_author_ids) AS aid
    ON CONFLICT (viewer_id, author_id)
    DO UPDATE SET
        exposure_count = CASE
            WHEN feed_exposures.window_start > now() - INTERVAL '24 hours'
            THEN feed_exposures.exposure_count + 1
            ELSE 1
        END,
        window_start = CASE
            WHEN feed_exposures.window_start > now() - INTERVAL '24 hours'
            THEN feed_exposures.window_start
            ELSE now()
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
