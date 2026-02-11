-- ============================================================================
-- FEED RANKING — SERVER-SIDE SCORING
-- ============================================================================
--
-- SCORING FORMULA (Main Feed):
--
--   score = (like_weight * normalized_likes)
--         + (velocity_weight * normalized_velocity)
--         + (freshness_weight * freshness_factor)
--         + (personalization_weight * is_following)
--
-- Where:
--   normalized_likes    = ln(1 + like_count) / ln(1 + max_likes_in_batch)
--   normalized_velocity = recent_views_1h / GREATEST(1, max_velocity_in_batch)
--   freshness_factor    = EXP(-decay_rate * hours_since_creation)
--   is_following         = 1.0 if viewer follows author, else 0.0
--
-- Weights (tunable):
--   like_weight          = 0.20  (weighted but not dominant)
--   velocity_weight      = 0.25
--   freshness_weight     = 0.45  (strong weight as per PRD)
--   personalization_weight = 0.10 (light personalization)
--   decay_rate           = 0.05  (half-life ~14 hours)
--
-- Exposure cap: max 2 posts per author per viewer per day
-- ============================================================================

-- --------------------------------------------------------------------------
-- MAIN FEED (Discovery — ranked)
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
    v_like_w DOUBLE PRECISION := 0.20;
    v_velocity_w DOUBLE PRECISION := 0.25;
    v_freshness_w DOUBLE PRECISION := 0.45;
    v_personal_w DOUBLE PRECISION := 0.10;
    v_decay_rate DOUBLE PRECISION := 0.05;
    v_max_author_exposure INT := 2;
BEGIN
    RETURN QUERY
    WITH candidate_posts AS (
        -- Gather active, public, non-hidden, non-blocked posts
        SELECT
            p.id AS post_id,
            p.user_id AS post_user_id,
            p.image_url AS post_image_url,
            p.image_width AS post_image_width,
            p.image_height AS post_image_height,
            p.like_count AS post_like_count,
            p.view_count AS post_view_count,
            p.created_at AS post_created_at,
            u.username AS post_username,
            u.profile_photo_url AS post_author_photo
        FROM posts p
        JOIN users u ON u.id = p.user_id
        WHERE p.is_hidden = FALSE
          AND p.expires_at > now()
          AND u.visibility = 'public'
          AND u.is_banned = FALSE
          -- Exclude blocked users (both directions)
          AND NOT EXISTS (
              SELECT 1 FROM blocks b
              WHERE (b.blocker_id = p.user_id AND b.blocked_id = v_viewer_id)
                 OR (b.blocker_id = v_viewer_id AND b.blocked_id = p.user_id)
          )
    ),
    batch_stats AS (
        SELECT
            GREATEST(1, MAX(post_like_count)) AS max_likes,
            GREATEST(1, MAX(
                COALESCE((
                    SELECT SUM(pvh.view_count)
                    FROM post_view_hourly pvh
                    WHERE pvh.post_id = cp.post_id
                      AND pvh.hour_bucket >= date_trunc('hour', now()) - INTERVAL '1 hour'
                ), 0)
            )) AS max_velocity
        FROM candidate_posts cp
    ),
    scored AS (
        SELECT
            cp.*,
            -- View velocity: views in last hour
            COALESCE((
                SELECT SUM(pvh.view_count)
                FROM post_view_hourly pvh
                WHERE pvh.post_id = cp.post_id
                  AND pvh.hour_bucket >= date_trunc('hour', now()) - INTERVAL '1 hour'
            ), 0) AS recent_views,
            -- Is viewer following this author
            EXISTS (
                SELECT 1 FROM follows f
                WHERE f.follower_id = v_viewer_id
                  AND f.following_id = cp.post_user_id
                  AND f.is_approved = TRUE
            ) AS viewer_follows,
            -- Hours since creation
            EXTRACT(EPOCH FROM (now() - cp.post_created_at)) / 3600.0 AS hours_age
        FROM candidate_posts cp
    ),
    ranked AS (
        SELECT
            s.post_id,
            s.post_user_id,
            s.post_username,
            s.post_author_photo,
            s.post_image_url,
            s.post_image_width,
            s.post_image_height,
            s.post_like_count,
            s.post_view_count,
            s.post_created_at,
            -- Compute score
            (
                v_like_w * (ln(1 + s.post_like_count) / ln(1 + bs.max_likes))
              + v_velocity_w * (s.recent_views::DOUBLE PRECISION / bs.max_velocity)
              + v_freshness_w * EXP(-v_decay_rate * s.hours_age)
              + v_personal_w * (CASE WHEN s.viewer_follows THEN 1.0 ELSE 0.0 END)
            ) AS computed_score,
            -- Exposure cap: count how many posts from this author viewer has seen today
            COALESCE((
                SELECT fe.exposure_count
                FROM feed_exposures fe
                WHERE fe.viewer_id = v_viewer_id
                  AND fe.author_id = s.post_user_id
                  AND fe.feed_date = CURRENT_DATE
            ), 0) AS author_exposure_today
        FROM scored s
        CROSS JOIN batch_stats bs
    ),
    filtered AS (
        SELECT r.*
        FROM ranked r
        WHERE r.author_exposure_today < v_max_author_exposure
          -- Cursor-based pagination: score DESC, then id DESC for tie-breaking
          AND (
              p_cursor_score IS NULL
              OR r.computed_score < p_cursor_score
              OR (r.computed_score = p_cursor_score AND r.post_id < p_cursor_id)
          )
        ORDER BY r.computed_score DESC, r.post_id DESC
        LIMIT p_limit
    )
    SELECT
        f.post_id,
        f.post_user_id,
        f.post_username,
        f.post_author_photo,
        f.post_image_url,
        f.post_image_width,
        f.post_image_height,
        f.post_like_count,
        f.post_view_count,
        EXISTS (
            SELECT 1 FROM likes l
            WHERE l.post_id = f.post_id AND l.user_id = v_viewer_id
        ) AS is_liked,
        f.post_created_at,
        f.computed_score,
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'label', t.label,
                    'external_url', t.external_url,
                    'position_x', t.position_x,
                    'position_y', t.position_y
                )
            )
            FROM tags t WHERE t.post_id = f.post_id),
            '[]'::JSONB
        ) AS tags
    FROM filtered f
    ORDER BY f.computed_score DESC, f.post_id DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- --------------------------------------------------------------------------
-- RECORD FEED EXPOSURE (called after serving feed results)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION record_feed_exposures(p_author_ids UUID[])
RETURNS void AS $$
BEGIN
    INSERT INTO feed_exposures (viewer_id, author_id, feed_date, exposure_count)
    SELECT auth_uid(), aid, CURRENT_DATE, 1
    FROM unnest(p_author_ids) AS aid
    ON CONFLICT (viewer_id, author_id, feed_date)
    DO UPDATE SET exposure_count = feed_exposures.exposure_count + 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
