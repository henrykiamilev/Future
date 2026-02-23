-- ============================================================================
-- FEED V2 MIGRATION — Finite Feed, Relationship Strength, Daily Caps
-- ============================================================================
-- Adds: relationship_strength, daily_feed_state tables
-- Modifies: users table (adds invited_by)
-- ============================================================================

-- ============================================================================
-- RELATIONSHIP STRENGTH (bidirectional interaction tracking)
-- ============================================================================
-- Stores one row per user pair (user_a < user_b) to avoid duplicates.
-- Counters are directional (a_to_b vs b_to_a).
-- Composite strength scores are recomputed by batch job every 15 minutes.
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

-- Lookup by either user in the pair
CREATE INDEX idx_rs_user_a ON relationship_strength (user_a);
CREATE INDEX idx_rs_user_b ON relationship_strength (user_b);

-- Batch job only recomputes recently-changed rows.
-- NOTE: Cannot use a partial index with now() — it freezes at creation time.
-- A plain B-tree on updated_at lets the batch query efficiently find recent rows
-- via an index range scan: WHERE updated_at > now() - INTERVAL '1 hour'.
CREATE INDEX IF NOT EXISTS idx_rs_updated ON relationship_strength (updated_at DESC);

-- ============================================================================
-- DAILY FEED STATE (per-user per-day finite feed tracking)
-- ============================================================================
-- Tracks how many friend/discovery posts a user has consumed today.
-- Enables "caught up" detection and discovery daily caps.
-- Rows are lightweight — one per user per active day.
-- Old rows can be pruned after 7 days.
-- ============================================================================

CREATE TABLE IF NOT EXISTS daily_feed_state (
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    state_date           DATE NOT NULL DEFAULT CURRENT_DATE,

    -- Friends feed tracking
    friends_posts_seen   INT NOT NULL DEFAULT 0,

    -- Discovery feed tracking
    discovery_items_seen INT NOT NULL DEFAULT 0,
    discovery_cap        INT NOT NULL DEFAULT 15,   -- per-user daily cap (adjustable)

    PRIMARY KEY (user_id, state_date)
);

-- Fast lookup for current day's state
CREATE INDEX idx_dfs_user_date ON daily_feed_state (user_id, state_date DESC);

-- ============================================================================
-- USERS TABLE ADDITIONS
-- ============================================================================

-- Invite chain tracking (for future implicit cohort clustering)
ALTER TABLE users ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES users(id);

-- ============================================================================
-- RLS POLICIES FOR NEW TABLES
-- ============================================================================

ALTER TABLE relationship_strength ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_feed_state ENABLE ROW LEVEL SECURITY;

-- Relationship strength: users can read their own relationships
-- Write is handled by SECURITY DEFINER functions only
CREATE POLICY rs_select_own ON relationship_strength
    FOR SELECT USING (
        user_a = auth.uid() OR user_b = auth.uid()
    );

-- Daily feed state: users can read/write their own state
CREATE POLICY dfs_select_own ON daily_feed_state
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY dfs_insert_own ON daily_feed_state
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY dfs_update_own ON daily_feed_state
    FOR UPDATE USING (user_id = auth.uid());

-- ============================================================================
-- CLEANUP: prune old daily_feed_state rows (> 7 days)
-- ============================================================================
-- Add to the existing cleanup_expired_data() function or run separately.
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
-- pg_cron SCHEDULES (run manually in Supabase SQL editor)
-- ============================================================================
-- Compute relationship strengths every 15 minutes:
-- SELECT cron.schedule('compute-relationship-strengths', '*/15 * * * *',
--     'SELECT compute_relationship_strengths()');
--
-- Cleanup old daily feed state daily at 3 AM:
-- SELECT cron.schedule('cleanup-daily-feed-state', '0 3 * * *',
--     'SELECT cleanup_daily_feed_state()');
-- ============================================================================
