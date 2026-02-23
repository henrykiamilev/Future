-- ============================================================================
-- STREAKS — Connection chain tracking between mutual followers
-- ============================================================================
-- Tracks consecutive days of mutual interaction between two users.
-- A "streak day" is counted when BOTH users interact with each other's
-- content (like or comment) within a rolling 48-hour window.
-- ============================================================================

-- ── TABLE ───────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS streaks (
    user_a      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    current_streak  INT NOT NULL DEFAULT 0,
    longest_streak  INT NOT NULL DEFAULT 0,
    last_a_to_b     TIMESTAMPTZ,   -- last time user_a interacted with user_b's content
    last_b_to_a     TIMESTAMPTZ,   -- last time user_b interacted with user_a's content
    streak_updated_at TIMESTAMPTZ, -- when the streak count last incremented
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_a, user_b),
    CONSTRAINT chk_streak_order CHECK (user_a < user_b)  -- canonical ordering
);

CREATE INDEX IF NOT EXISTS idx_streaks_user_a ON streaks (user_a);
CREATE INDEX IF NOT EXISTS idx_streaks_user_b ON streaks (user_b);

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;

CREATE POLICY streaks_select_own ON streaks
    FOR SELECT USING (user_a = auth_uid() OR user_b = auth_uid());

-- Only triggers (SECURITY DEFINER) modify streaks, not users directly

-- ── HELPER: Record an interaction and update streak ─────────────────────────

CREATE OR REPLACE FUNCTION record_streak_interaction(
    p_actor_id UUID,
    p_target_owner_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_a UUID;
    v_b UUID;
    v_row streaks%ROWTYPE;
    v_now TIMESTAMPTZ := now();
    v_48h_ago TIMESTAMPTZ := v_now - INTERVAL '48 hours';
BEGIN
    -- Skip self-interaction
    IF p_actor_id = p_target_owner_id THEN RETURN; END IF;

    -- Canonical ordering (smaller UUID first)
    IF p_actor_id < p_target_owner_id THEN
        v_a := p_actor_id;
        v_b := p_target_owner_id;
    ELSE
        v_a := p_target_owner_id;
        v_b := p_actor_id;
    END IF;

    -- Upsert the streak row
    INSERT INTO streaks (user_a, user_b, current_streak, longest_streak)
    VALUES (v_a, v_b, 0, 0)
    ON CONFLICT (user_a, user_b) DO NOTHING;

    -- Lock and fetch
    SELECT * INTO v_row FROM streaks WHERE user_a = v_a AND user_b = v_b FOR UPDATE;

    -- Update the directional timestamp
    IF p_actor_id = v_a THEN
        UPDATE streaks SET last_a_to_b = v_now WHERE user_a = v_a AND user_b = v_b;
        v_row.last_a_to_b := v_now;
    ELSE
        UPDATE streaks SET last_b_to_a = v_now WHERE user_a = v_a AND user_b = v_b;
        v_row.last_b_to_a := v_now;
    END IF;

    -- Check if both sides interacted within 48h window → increment streak
    IF v_row.last_a_to_b IS NOT NULL
       AND v_row.last_b_to_a IS NOT NULL
       AND v_row.last_a_to_b > v_48h_ago
       AND v_row.last_b_to_a > v_48h_ago
       AND (v_row.streak_updated_at IS NULL OR v_row.streak_updated_at < v_now - INTERVAL '20 hours')
    THEN
        UPDATE streaks
        SET current_streak = current_streak + 1,
            longest_streak = GREATEST(longest_streak, current_streak + 1),
            streak_updated_at = v_now
        WHERE user_a = v_a AND user_b = v_b;
    END IF;

    -- Reset streak if either side hasn't interacted in 48h
    IF v_row.streak_updated_at IS NOT NULL
       AND v_row.streak_updated_at < v_48h_ago
       AND v_row.current_streak > 0
    THEN
        UPDATE streaks
        SET current_streak = 0
        WHERE user_a = v_a AND user_b = v_b;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── TRIGGERS: Hook into likes and comments ──────────────────────────────────

CREATE OR REPLACE FUNCTION streak_on_like()
RETURNS TRIGGER AS $$
DECLARE
    v_post_owner UUID;
BEGIN
    SELECT user_id INTO v_post_owner FROM posts WHERE id = NEW.post_id;
    IF v_post_owner IS NOT NULL THEN
        PERFORM record_streak_interaction(NEW.user_id, v_post_owner);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_streak_on_like ON likes;
CREATE TRIGGER trg_streak_on_like
    AFTER INSERT ON likes
    FOR EACH ROW EXECUTE FUNCTION streak_on_like();

CREATE OR REPLACE FUNCTION streak_on_comment()
RETURNS TRIGGER AS $$
DECLARE
    v_post_owner UUID;
BEGIN
    SELECT user_id INTO v_post_owner FROM posts WHERE id = NEW.post_id;
    IF v_post_owner IS NOT NULL THEN
        PERFORM record_streak_interaction(NEW.user_id, v_post_owner);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_streak_on_comment ON comments;
CREATE TRIGGER trg_streak_on_comment
    AFTER INSERT ON comments
    FOR EACH ROW EXECUTE FUNCTION streak_on_comment();

-- ── GET STREAKS FOR USER ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_my_streaks(
    p_min_streak INT DEFAULT 1
)
RETURNS TABLE (
    partner_id UUID,
    partner_username TEXT,
    partner_photo TEXT,
    current_streak INT,
    longest_streak INT
) AS $$
DECLARE
    v_user_id UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        CASE WHEN s.user_a = v_user_id THEN s.user_b ELSE s.user_a END AS partner_id,
        u.username AS partner_username,
        u.profile_photo_url AS partner_photo,
        s.current_streak,
        s.longest_streak
    FROM streaks s
    JOIN users u ON u.id = CASE WHEN s.user_a = v_user_id THEN s.user_b ELSE s.user_a END
    WHERE (s.user_a = v_user_id OR s.user_b = v_user_id)
      AND s.current_streak >= p_min_streak
    ORDER BY s.current_streak DESC, s.longest_streak DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── GET STREAK BETWEEN TWO USERS ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_streak_with_user(p_other_user_id UUID)
RETURNS TABLE (
    current_streak INT,
    longest_streak INT
) AS $$
DECLARE
    v_user_id UUID := auth_uid();
    v_a UUID;
    v_b UUID;
BEGIN
    IF v_user_id < p_other_user_id THEN
        v_a := v_user_id;
        v_b := p_other_user_id;
    ELSE
        v_a := p_other_user_id;
        v_b := v_user_id;
    END IF;

    RETURN QUERY
    SELECT s.current_streak, s.longest_streak
    FROM streaks s
    WHERE s.user_a = v_a AND s.user_b = v_b;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── CRON: Reset stale streaks (run daily) ───────────────────────────────────
-- Schedule: SELECT cron.schedule('reset-stale-streaks', '0 4 * * *', 'SELECT reset_stale_streaks()');

CREATE OR REPLACE FUNCTION reset_stale_streaks()
RETURNS VOID AS $$
BEGIN
    UPDATE streaks
    SET current_streak = 0
    WHERE current_streak > 0
      AND streak_updated_at < now() - INTERVAL '48 hours';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
