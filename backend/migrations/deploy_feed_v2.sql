-- ============================================================================
-- CURATED FEED V2 — CONSOLIDATED DEPLOYMENT SCRIPT
-- ============================================================================
-- Copy-paste this entire file into the Supabase SQL Editor and run it.
-- Safe to re-run: uses CREATE OR REPLACE and IF NOT EXISTS throughout.
--
-- Order of operations:
--   1. New tables (relationship_strength, daily_feed_state)
--   2. Users table additions
--   3. RLS policies
--   4. Relationship strength functions
--   5. Record consumption function
--   6. Friends feed v2 (ranked + caught-up)
--   7. Discover v2 (daily-capped)
--   8. Updated triggers (like/follow → relationship tracking)
--   9. Cleanup function
-- ============================================================================


-- ============================================================================
-- STEP 1: NEW TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS relationship_strength (
    user_a              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Directional interaction counters
    likes_a_to_b        INT NOT NULL DEFAULT 0,
    likes_b_to_a        INT NOT NULL DEFAULT 0,
    comments_a_to_b     INT NOT NULL DEFAULT 0,
    comments_b_to_a     INT NOT NULL DEFAULT 0,
    profile_views_a_to_b INT NOT NULL DEFAULT 0,
    profile_views_b_to_a INT NOT NULL DEFAULT 0,

    -- Follow metadata
    is_mutual_follow    BOOLEAN NOT NULL DEFAULT FALSE,

    -- Pre-computed composite strength scores [0.0, 1.0]
    strength_a_to_b     REAL NOT NULL DEFAULT 0.0,
    strength_b_to_a     REAL NOT NULL DEFAULT 0.0,

    last_interaction_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_a, user_b),
    CONSTRAINT chk_ordered_pair CHECK (user_a < user_b)
);

CREATE INDEX IF NOT EXISTS idx_rs_user_a ON relationship_strength (user_a);
CREATE INDEX IF NOT EXISTS idx_rs_user_b ON relationship_strength (user_b);
-- Plain B-tree (no partial index) — now() freezes at creation time, making
-- partial indexes with now() useless after the interval elapses.
CREATE INDEX IF NOT EXISTS idx_rs_updated ON relationship_strength (updated_at DESC);

CREATE TABLE IF NOT EXISTS daily_feed_state (
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    state_date           DATE NOT NULL DEFAULT CURRENT_DATE,

    -- Friends feed tracking
    friends_posts_seen   INT NOT NULL DEFAULT 0,

    -- Discovery feed tracking
    discovery_items_seen INT NOT NULL DEFAULT 0,
    discovery_cap        INT NOT NULL DEFAULT 15,

    PRIMARY KEY (user_id, state_date)
);

CREATE INDEX IF NOT EXISTS idx_dfs_user_date ON daily_feed_state (user_id, state_date DESC);


-- ============================================================================
-- STEP 2: USERS TABLE ADDITIONS
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES users(id);


-- ============================================================================
-- STEP 3: RLS POLICIES
-- ============================================================================

ALTER TABLE relationship_strength ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_feed_state ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if re-running (safe idempotent pattern)
DROP POLICY IF EXISTS rs_select_own ON relationship_strength;
DROP POLICY IF EXISTS dfs_select_own ON daily_feed_state;
DROP POLICY IF EXISTS dfs_insert_own ON daily_feed_state;
DROP POLICY IF EXISTS dfs_update_own ON daily_feed_state;

CREATE POLICY rs_select_own ON relationship_strength
    FOR SELECT USING (
        user_a = auth.uid() OR user_b = auth.uid()
    );

CREATE POLICY dfs_select_own ON daily_feed_state
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY dfs_insert_own ON daily_feed_state
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY dfs_update_own ON daily_feed_state
    FOR UPDATE USING (user_id = auth.uid());


-- ============================================================================
-- STEP 4: RELATIONSHIP STRENGTH FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION increment_relationship_signal(
    p_from_user UUID,
    p_to_user UUID,
    p_signal_type TEXT
)
RETURNS VOID AS $$
DECLARE
    v_a UUID;
    v_b UUID;
    v_is_a_to_b BOOLEAN;
BEGIN
    IF p_from_user = p_to_user THEN
        RETURN;
    END IF;

    IF p_from_user < p_to_user THEN
        v_a := p_from_user;
        v_b := p_to_user;
        v_is_a_to_b := TRUE;
    ELSE
        v_a := p_to_user;
        v_b := p_from_user;
        v_is_a_to_b := FALSE;
    END IF;

    INSERT INTO relationship_strength (user_a, user_b)
    VALUES (v_a, v_b)
    ON CONFLICT (user_a, user_b) DO NOTHING;

    IF v_is_a_to_b THEN
        CASE p_signal_type
            WHEN 'like' THEN
                UPDATE relationship_strength
                SET likes_a_to_b = likes_a_to_b + 1,
                    last_interaction_at = now(),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'comment' THEN
                UPDATE relationship_strength
                SET comments_a_to_b = comments_a_to_b + 1,
                    last_interaction_at = now(),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'profile_view' THEN
                UPDATE relationship_strength
                SET profile_views_a_to_b = profile_views_a_to_b + 1,
                    last_interaction_at = now(),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
        END CASE;
    ELSE
        CASE p_signal_type
            WHEN 'like' THEN
                UPDATE relationship_strength
                SET likes_b_to_a = likes_b_to_a + 1,
                    last_interaction_at = now(),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'comment' THEN
                UPDATE relationship_strength
                SET comments_b_to_a = comments_b_to_a + 1,
                    last_interaction_at = now(),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'profile_view' THEN
                UPDATE relationship_strength
                SET profile_views_b_to_a = profile_views_b_to_a + 1,
                    last_interaction_at = now(),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
        END CASE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION decrement_relationship_signal(
    p_from_user UUID,
    p_to_user UUID,
    p_signal_type TEXT
)
RETURNS VOID AS $$
DECLARE
    v_a UUID;
    v_b UUID;
    v_is_a_to_b BOOLEAN;
BEGIN
    IF p_from_user = p_to_user THEN
        RETURN;
    END IF;

    IF p_from_user < p_to_user THEN
        v_a := p_from_user;
        v_b := p_to_user;
        v_is_a_to_b := TRUE;
    ELSE
        v_a := p_to_user;
        v_b := p_from_user;
        v_is_a_to_b := FALSE;
    END IF;

    IF v_is_a_to_b THEN
        CASE p_signal_type
            WHEN 'like' THEN
                UPDATE relationship_strength
                SET likes_a_to_b = GREATEST(0, likes_a_to_b - 1),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'comment' THEN
                UPDATE relationship_strength
                SET comments_a_to_b = GREATEST(0, comments_a_to_b - 1),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'profile_view' THEN
                UPDATE relationship_strength
                SET profile_views_a_to_b = GREATEST(0, profile_views_a_to_b - 1),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            ELSE
                NULL; -- Unknown signal type — ignore silently
        END CASE;
    ELSE
        CASE p_signal_type
            WHEN 'like' THEN
                UPDATE relationship_strength
                SET likes_b_to_a = GREATEST(0, likes_b_to_a - 1),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'comment' THEN
                UPDATE relationship_strength
                SET comments_b_to_a = GREATEST(0, comments_b_to_a - 1),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            WHEN 'profile_view' THEN
                UPDATE relationship_strength
                SET profile_views_b_to_a = GREATEST(0, profile_views_b_to_a - 1),
                    updated_at = now()
                WHERE user_a = v_a AND user_b = v_b;
            ELSE
                NULL; -- Unknown signal type — ignore silently
        END CASE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION update_mutual_follow_status(
    p_user_1 UUID,
    p_user_2 UUID
)
RETURNS VOID AS $$
DECLARE
    v_a UUID;
    v_b UUID;
    v_mutual BOOLEAN;
BEGIN
    IF p_user_1 = p_user_2 THEN
        RETURN;
    END IF;

    IF p_user_1 < p_user_2 THEN
        v_a := p_user_1;
        v_b := p_user_2;
    ELSE
        v_a := p_user_2;
        v_b := p_user_1;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM follows
        WHERE follower_id = v_a AND following_id = v_b AND is_approved = TRUE
    ) AND EXISTS (
        SELECT 1 FROM follows
        WHERE follower_id = v_b AND following_id = v_a AND is_approved = TRUE
    ) INTO v_mutual;

    INSERT INTO relationship_strength (user_a, user_b, is_mutual_follow, updated_at)
    VALUES (v_a, v_b, v_mutual, now())
    ON CONFLICT (user_a, user_b) DO UPDATE
    SET is_mutual_follow = v_mutual,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION compute_relationship_strengths()
RETURNS VOID AS $$
BEGIN
    UPDATE relationship_strength rs SET
        strength_a_to_b = (
            0.30 * LEAST(1.0, rs.likes_a_to_b / 10.0)
          + 0.25 * LEAST(1.0, rs.comments_a_to_b / 5.0)
          + 0.20 * CASE
                WHEN rs.is_mutual_follow THEN 1.0
                WHEN EXISTS (
                    SELECT 1 FROM follows f
                    WHERE f.follower_id = rs.user_a AND f.following_id = rs.user_b
                      AND f.is_approved = TRUE
                ) THEN 0.5
                ELSE 0.0
            END
          + 0.15 * GREATEST(0, 1.0 - EXTRACT(EPOCH FROM (now() - rs.last_interaction_at)) / (30 * 86400))
          + 0.10 * LEAST(1.0, rs.profile_views_a_to_b / 5.0)
        )::REAL,
        strength_b_to_a = (
            0.30 * LEAST(1.0, rs.likes_b_to_a / 10.0)
          + 0.25 * LEAST(1.0, rs.comments_b_to_a / 5.0)
          + 0.20 * CASE
                WHEN rs.is_mutual_follow THEN 1.0
                WHEN EXISTS (
                    SELECT 1 FROM follows f
                    WHERE f.follower_id = rs.user_b AND f.following_id = rs.user_a
                      AND f.is_approved = TRUE
                ) THEN 0.5
                ELSE 0.0
            END
          + 0.15 * GREATEST(0, 1.0 - EXTRACT(EPOCH FROM (now() - rs.last_interaction_at)) / (30 * 86400))
          + 0.10 * LEAST(1.0, rs.profile_views_b_to_a / 5.0)
        )::REAL,
        updated_at = now()
    WHERE rs.updated_at > now() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION get_relationship_strength(
    p_viewer UUID,
    p_author UUID
)
RETURNS REAL AS $$
DECLARE
    v_strength REAL := 0.0;
BEGIN
    IF p_viewer = p_author THEN
        RETURN 1.0;
    END IF;

    IF p_viewer < p_author THEN
        SELECT strength_a_to_b INTO v_strength
        FROM relationship_strength
        WHERE user_a = p_viewer AND user_b = p_author;
    ELSE
        SELECT strength_b_to_a INTO v_strength
        FROM relationship_strength
        WHERE user_a = p_author AND user_b = p_viewer;
    END IF;

    RETURN COALESCE(v_strength, 0.0);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;


-- ============================================================================
-- STEP 5: RECORD CONSUMPTION FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION record_post_consumption(
    p_post_id UUID,
    p_feed_type TEXT
)
RETURNS VOID AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
BEGIN
    IF p_feed_type NOT IN ('friends', 'discovery') THEN
        RETURN;
    END IF;

    INSERT INTO daily_feed_state (user_id, state_date)
    VALUES (v_viewer_id, CURRENT_DATE)
    ON CONFLICT (user_id, state_date) DO NOTHING;

    IF p_feed_type = 'friends' THEN
        UPDATE daily_feed_state
        SET friends_posts_seen = friends_posts_seen + 1
        WHERE user_id = v_viewer_id AND state_date = CURRENT_DATE;
    ELSIF p_feed_type = 'discovery' THEN
        UPDATE daily_feed_state
        SET discovery_items_seen = discovery_items_seen + 1
        WHERE user_id = v_viewer_id AND state_date = CURRENT_DATE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


-- ============================================================================
-- STEP 6: FRIENDS FEED v2 (ranked + caught-up detection)
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
    friends_remaining INT
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
    v_total_unseen INT;
    v_capped_limit INT;
BEGIN
    v_capped_limit := LEAST(GREATEST(p_limit, 1), 20);

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
        (COUNT(*) OVER() <= v_capped_limit)::BOOLEAN AS is_caught_up,
        GREATEST(0, v_total_unseen - (ROW_NUMBER() OVER (ORDER BY sp.feed_score DESC, sp.id DESC))::INT)::INT AS friends_remaining
    FROM scored_posts sp
    WHERE (p_cursor_score IS NULL OR
           sp.feed_score < p_cursor_score OR
           (sp.feed_score = p_cursor_score AND sp.id < p_cursor_id))
    ORDER BY sp.feed_score DESC, sp.id DESC
    LIMIT v_capped_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;


-- ============================================================================
-- STEP 7: DISCOVER v2 (daily-capped + diversity)
-- ============================================================================

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
    items_remaining INT
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
    v_daily_cap INT;
    v_items_seen INT;
    v_budget INT;
    v_capped_limit INT;
BEGIN
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

    v_capped_limit := LEAST(GREATEST(p_limit, 1), v_budget);

    RETURN QUERY
    WITH ranked_posts AS (
        SELECT DISTINCT ON (p.user_id)
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
          AND p.user_id != v_viewer_id
          AND NOT EXISTS (
              SELECT 1 FROM follows f
              WHERE f.follower_id = v_viewer_id AND f.following_id = p.user_id
                AND f.is_approved = TRUE
          )
          AND NOT EXISTS (
              SELECT 1 FROM blocks b
              WHERE (b.blocker_id = p.user_id AND b.blocked_id = v_viewer_id)
                 OR (b.blocker_id = v_viewer_id AND b.blocked_id = p.user_id)
          )
        ORDER BY p.user_id, fs.base_score DESC
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
        (v_budget <= v_capped_limit)::BOOLEAN AS is_exhausted,
        GREATEST(0, v_budget - (ROW_NUMBER() OVER (ORDER BY rp.base_score DESC))::INT)::INT AS items_remaining
    FROM ranked_posts rp
    ORDER BY rp.base_score DESC
    LIMIT v_capped_limit;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp;


-- ============================================================================
-- STEP 8: UPDATED TRIGGERS (like/follow → relationship tracking)
-- ============================================================================
-- These replace the existing trigger functions. The CREATE TRIGGER statements
-- use DROP + CREATE since triggers don't support OR REPLACE.
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_like_count_increment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_author_id UUID;
BEGIN
    UPDATE posts SET like_count = like_count + 1, updated_at = now()
    WHERE id = NEW.post_id;

    SELECT user_id INTO v_author_id FROM posts WHERE id = NEW.post_id;
    UPDATE users SET total_likes = total_likes + 1, updated_at = now()
    WHERE id = v_author_id;

    -- Track relationship strength: liker -> post author
    PERFORM increment_relationship_signal(NEW.user_id, v_author_id, 'like');

    RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION trg_like_count_decrement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_author_id UUID;
BEGIN
    UPDATE posts SET like_count = GREATEST(0, like_count - 1), updated_at = now()
    WHERE id = OLD.post_id;

    SELECT user_id INTO v_author_id FROM posts WHERE id = OLD.post_id;
    UPDATE users SET total_likes = GREATEST(0, total_likes - 1), updated_at = now()
    WHERE id = v_author_id;

    -- Decrement relationship strength: unliker -> post author
    PERFORM decrement_relationship_signal(OLD.user_id, v_author_id, 'like');

    RETURN OLD;
END;
$$;


CREATE OR REPLACE FUNCTION trg_follow_count_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.is_approved = TRUE THEN
        UPDATE users SET following_count = following_count + 1, updated_at = now()
        WHERE id = NEW.follower_id;
        UPDATE users SET follower_count = follower_count + 1, updated_at = now()
        WHERE id = NEW.following_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.is_approved = FALSE AND NEW.is_approved = TRUE THEN
        UPDATE users SET following_count = following_count + 1, updated_at = now()
        WHERE id = NEW.follower_id;
        UPDATE users SET follower_count = follower_count + 1, updated_at = now()
        WHERE id = NEW.following_id;
    ELSIF TG_OP = 'DELETE' AND OLD.is_approved = TRUE THEN
        UPDATE users SET following_count = GREATEST(0, following_count - 1), updated_at = now()
        WHERE id = OLD.follower_id;
        UPDATE users SET follower_count = GREATEST(0, follower_count - 1), updated_at = now()
        WHERE id = OLD.following_id;
    END IF;

    -- Update mutual follow status for relationship strength
    IF TG_OP = 'DELETE' THEN
        PERFORM update_mutual_follow_status(OLD.follower_id, OLD.following_id);
        RETURN OLD;
    ELSE
        PERFORM update_mutual_follow_status(NEW.follower_id, NEW.following_id);
        RETURN NEW;
    END IF;
END;
$$;


-- ============================================================================
-- STEP 9: CLEANUP FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_daily_feed_state()
RETURNS VOID AS $$
BEGIN
    DELETE FROM daily_feed_state
    WHERE state_date < CURRENT_DATE - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


-- ============================================================================
-- DONE! Next step (optional): Set up pg_cron jobs.
-- Run these separately if you're on Supabase Pro (pg_cron requires paid plan):
--
-- SELECT cron.schedule('compute-relationship-strengths', '*/15 * * * *',
--     'SELECT compute_relationship_strengths()');
--
-- SELECT cron.schedule('cleanup-daily-feed-state', '0 3 * * *',
--     'SELECT cleanup_daily_feed_state()');
--
-- To verify cron jobs: SELECT * FROM cron.job;
-- ============================================================================
