-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================
-- Assumes: app.current_user_id is set via SET LOCAL at the start of each
-- request (e.g., from JWT claims in Edge Function / Lambda / middleware).
--
-- SET LOCAL "app.current_user_id" = 'uuid-here';
-- ============================================================================

-- Helper: get current authenticated user ID
CREATE OR REPLACE FUNCTION auth_uid() RETURNS UUID AS $$
    SELECT NULLIF(current_setting('app.current_user_id', TRUE), '')::UUID;
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

-- Users can only update their own profile
CREATE POLICY users_update_own ON users
    FOR UPDATE
    USING (id = auth_uid())
    WITH CHECK (id = auth_uid());

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
CREATE POLICY follows_update ON follows
    FOR UPDATE
    USING (following_id = auth_uid())
    WITH CHECK (following_id = auth_uid());

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
-- POST_VIEWS
-- ============================================================================
ALTER TABLE post_views ENABLE ROW LEVEL SECURITY;

-- Insert only (tracking)
CREATE POLICY post_views_insert ON post_views
    FOR INSERT WITH CHECK (viewer_id = auth_uid() OR viewer_id IS NULL);

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
