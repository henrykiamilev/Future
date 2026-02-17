-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================
-- Supabase automatically sets auth.uid() from the JWT in every request.
-- All policies use auth.uid() directly — no manual session variable needed.
--
-- For SECURITY DEFINER functions that bypass RLS, we use auth.uid() inside
-- the function body to identify the caller.
-- ============================================================================

-- Helper: alias for Supabase's built-in auth.uid()
-- This wrapper exists so non-Supabase environments can override it.
CREATE OR REPLACE FUNCTION auth_uid() RETURNS UUID AS $$
    SELECT auth.uid();
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- USERS
-- ============================================================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Anyone can read public profiles
CREATE POLICY users_select_public ON users
    FOR SELECT
    USING (
        visibility = 'public'
        OR id = auth_uid()
        OR EXISTS (
            SELECT 1 FROM follows
            WHERE follower_id = auth_uid()
              AND following_id = users.id
              AND is_approved = TRUE
        )
    );

-- Users can insert their own row (auth trigger is SECURITY DEFINER so bypasses
-- RLS, but this policy exists as defense-in-depth for any direct insert path)
CREATE POLICY users_insert_own ON users
    FOR INSERT
    WITH CHECK (id = auth_uid());

-- Users can only update their own profile
CREATE POLICY users_update_own ON users
    FOR UPDATE
    USING (id = auth_uid())
    WITH CHECK (id = auth_uid());

-- Users can delete their own account
CREATE POLICY users_delete_own ON users
    FOR DELETE
    USING (id = auth_uid());

-- ============================================================================
-- POSTS
-- ============================================================================
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

-- Public posts: visible if author is public AND post is active (not expired or hidden)
-- Private posts: visible only to approved followers
-- Expired posts: visible only to the owner (archive)
CREATE POLICY posts_select ON posts
    FOR SELECT
    USING (
        -- Owner can always see their own posts (archive access)
        user_id = auth_uid()
        OR (
            -- Post must not be hidden
            is_hidden = FALSE
            AND (
                -- Active posts (not expired) OR signature posts (never expire from public view)
                expires_at > now() OR is_signature = TRUE
            )
            AND (
                -- Public author
                EXISTS (
                    SELECT 1 FROM users
                    WHERE id = posts.user_id AND visibility = 'public' AND is_banned = FALSE
                )
                OR
                -- Private author but viewer is approved follower
                EXISTS (
                    SELECT 1 FROM follows
                    WHERE follower_id = auth_uid()
                      AND following_id = posts.user_id
                      AND is_approved = TRUE
                )
            )
            -- Block check: neither direction
            AND NOT EXISTS (
                SELECT 1 FROM blocks
                WHERE (blocker_id = posts.user_id AND blocked_id = auth_uid())
                   OR (blocker_id = auth_uid() AND blocked_id = posts.user_id)
            )
        )
    );

-- Users can only insert their own posts
CREATE POLICY posts_insert ON posts
    FOR INSERT
    WITH CHECK (user_id = auth_uid());

-- Users can only update their own posts (e.g., toggle signature)
CREATE POLICY posts_update_own ON posts
    FOR UPDATE
    USING (user_id = auth_uid())
    WITH CHECK (user_id = auth_uid());

-- ============================================================================
-- TAGS
-- ============================================================================
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;

-- Tags readable if the post is readable (delegated to posts RLS)
CREATE POLICY tags_select ON tags
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM posts WHERE id = tags.post_id
        )
    );

-- Only post owner can insert tags
CREATE POLICY tags_insert ON tags
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM posts
            WHERE id = tags.post_id AND user_id = auth_uid()
        )
    );

-- Only post owner can delete tags
CREATE POLICY tags_delete ON tags
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM posts
            WHERE id = tags.post_id AND user_id = auth_uid()
        )
    );

-- ============================================================================
-- LIKES
-- ============================================================================
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;

-- Likes are readable on readable posts
CREATE POLICY likes_select ON likes
    FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM posts WHERE id = likes.post_id)
    );

-- Users can only insert their own likes
CREATE POLICY likes_insert ON likes
    FOR INSERT
    WITH CHECK (user_id = auth_uid());

-- Users can only delete their own likes (unlike)
CREATE POLICY likes_delete ON likes
    FOR DELETE
    USING (user_id = auth_uid());

-- ============================================================================
-- FOLLOWS
-- ============================================================================
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;

-- Users can see their own follows and followers
CREATE POLICY follows_select ON follows
    FOR SELECT
    USING (
        follower_id = auth_uid()
        OR following_id = auth_uid()
        -- Public follower lists
        OR EXISTS (
            SELECT 1 FROM users
            WHERE id = follows.following_id AND visibility = 'public'
        )
    );

-- Users can only create follows as themselves
CREATE POLICY follows_insert ON follows
    FOR INSERT
    WITH CHECK (follower_id = auth_uid());

-- Users can delete follows they initiated, or reject follows to them
CREATE POLICY follows_delete ON follows
    FOR DELETE
    USING (
        follower_id = auth_uid()
        OR following_id = auth_uid()
    );

-- Target user can approve pending follow requests
-- REMOVED: Direct UPDATE policy replaced with approve_follow_request() RPC
-- to prevent column manipulation (e.g., changing follower_id).
-- CREATE POLICY follows_update ON follows
--     FOR UPDATE
--     USING (following_id = auth_uid())
--     WITH CHECK (following_id = auth_uid());

-- ============================================================================
-- BLOCKS
-- ============================================================================
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY blocks_select ON blocks
    FOR SELECT USING (blocker_id = auth_uid());

CREATE POLICY blocks_insert ON blocks
    FOR INSERT WITH CHECK (blocker_id = auth_uid());

CREATE POLICY blocks_delete ON blocks
    FOR DELETE USING (blocker_id = auth_uid());

-- ============================================================================
-- REPORTS
-- ============================================================================
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

-- Users can see their own reports
CREATE POLICY reports_select_own ON reports
    FOR SELECT USING (reporter_id = auth_uid());

-- Users can insert reports as themselves
CREATE POLICY reports_insert ON reports
    FOR INSERT WITH CHECK (reporter_id = auth_uid());

-- ============================================================================
-- POST_VIEW_HOURLY (direct increment via record_post_view function)
-- ============================================================================
-- No direct client access — views are recorded via SECURITY DEFINER function.
-- RLS is enabled but no policies needed (function bypasses RLS).
ALTER TABLE post_view_hourly ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- FEED_SCORES (read-only for authenticated users)
-- ============================================================================
ALTER TABLE feed_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY feed_scores_select ON feed_scores
    FOR SELECT USING (auth_uid() IS NOT NULL);

-- ============================================================================
-- FEED_EXPOSURES
-- ============================================================================
ALTER TABLE feed_exposures ENABLE ROW LEVEL SECURITY;

CREATE POLICY feed_exposures_insert ON feed_exposures
    FOR INSERT WITH CHECK (viewer_id = auth_uid());

CREATE POLICY feed_exposures_select ON feed_exposures
    FOR SELECT USING (viewer_id = auth_uid());

CREATE POLICY feed_exposures_update ON feed_exposures
    FOR UPDATE
    USING (viewer_id = auth_uid())
    WITH CHECK (viewer_id = auth_uid());

-- ============================================================================
-- APPROVE FOLLOW REQUEST (replaces permissive follows_update policy)
-- ============================================================================
-- Only allows toggling is_approved on follow requests targeting the caller.
-- Prevents column manipulation (e.g., changing follower_id).
CREATE OR REPLACE FUNCTION approve_follow_request(p_follower_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE follows SET is_approved = TRUE
    WHERE follower_id = p_follower_id
      AND following_id = auth_uid()
      AND is_approved = FALSE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'request_not_found';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
