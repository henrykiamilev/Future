-- ============================================================================
-- RELATIONSHIP STRENGTH — Increment + Batch Compute
-- ============================================================================
-- Tracks interaction signals between user pairs.
-- Called from triggers on likes, comments, and follows.
-- Batch job recomputes composite strength every 15 minutes.
-- ============================================================================

-- --------------------------------------------------------------------------
-- INCREMENT A SINGLE SIGNAL (called from triggers)
-- --------------------------------------------------------------------------
-- p_signal_type: 'like', 'comment', 'profile_view'
-- Handles pair ordering (user_a < user_b) automatically.
-- --------------------------------------------------------------------------

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
    -- Skip self-interactions
    IF p_from_user = p_to_user THEN
        RETURN;
    END IF;

    -- Normalize ordering: user_a < user_b
    IF p_from_user < p_to_user THEN
        v_a := p_from_user;
        v_b := p_to_user;
        v_is_a_to_b := TRUE;
    ELSE
        v_a := p_to_user;
        v_b := p_from_user;
        v_is_a_to_b := FALSE;
    END IF;

    -- Upsert the pair row
    INSERT INTO relationship_strength (user_a, user_b)
    VALUES (v_a, v_b)
    ON CONFLICT (user_a, user_b) DO NOTHING;

    -- Increment the appropriate directional counter
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

-- --------------------------------------------------------------------------
-- DECREMENT A SIGNAL (called on unlike)
-- --------------------------------------------------------------------------

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

-- --------------------------------------------------------------------------
-- UPDATE MUTUAL FOLLOW STATUS (called from follow triggers)
-- --------------------------------------------------------------------------

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

    -- Check if both directions have approved follows
    SELECT EXISTS (
        SELECT 1 FROM follows
        WHERE follower_id = v_a AND following_id = v_b AND is_approved = TRUE
    ) AND EXISTS (
        SELECT 1 FROM follows
        WHERE follower_id = v_b AND following_id = v_a AND is_approved = TRUE
    ) INTO v_mutual;

    -- Upsert
    INSERT INTO relationship_strength (user_a, user_b, is_mutual_follow, updated_at)
    VALUES (v_a, v_b, v_mutual, now())
    ON CONFLICT (user_a, user_b) DO UPDATE
    SET is_mutual_follow = v_mutual,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- BATCH COMPUTE RELATIONSHIP STRENGTHS (pg_cron every 15 min)
-- --------------------------------------------------------------------------
-- Formula:
--   strength(V -> A) =
--     0.30 * min(1, likes / 10)
--   + 0.25 * min(1, comments / 5)
--   + 0.20 * mutual_follow_bonus (1.0 mutual, 0.5 one-way, 0.0 none)
--   + 0.15 * recency_decay (linear over 30 days)
--   + 0.10 * min(1, profile_views / 5)
-- --------------------------------------------------------------------------

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
    -- Only recompute recently-changed rows for efficiency
    WHERE rs.updated_at > now() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- LOOKUP HELPER: get strength from viewer -> author
-- --------------------------------------------------------------------------
-- Used inline by feed functions. Returns 0.0 if no relationship exists.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_relationship_strength(
    p_viewer UUID,
    p_author UUID
)
RETURNS REAL AS $$
DECLARE
    v_strength REAL := 0.0;
BEGIN
    IF p_viewer = p_author THEN
        RETURN 1.0;  -- self always max
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
