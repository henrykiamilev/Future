-- ============================================================================
-- REACTIONS — Emoji reactions on posts
-- ============================================================================
-- Adds emoji reactions alongside the existing like system.
-- One reaction per user per post (can change emoji, not stack).
-- Reaction counts returned inline with feed queries.
-- ============================================================================

-- ── TABLE ───────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS reactions (
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    emoji       TEXT NOT NULL CHECK (emoji IN ('🔥', '👏', '😍', '💯', '🤯')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_reactions_post ON reactions (post_id);

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY reactions_select ON reactions
    FOR SELECT USING (TRUE);

CREATE POLICY reactions_own ON reactions
    FOR ALL USING (user_id = auth_uid())
    WITH CHECK (user_id = auth_uid());

-- ── REACT TO POST ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION react_to_post(p_post_id UUID, p_emoji TEXT)
RETURNS VOID AS $$
DECLARE
    v_caller UUID := auth_uid();
    v_post RECORD;
BEGIN
    SELECT id, user_id, is_hidden, expires_at, is_signature
    INTO v_post
    FROM posts WHERE id = p_post_id;

    IF v_post IS NULL OR v_post.is_hidden THEN
        RAISE EXCEPTION 'post_not_accessible: Post is not available';
    END IF;

    IF v_post.expires_at <= now() AND NOT v_post.is_signature THEN
        RAISE EXCEPTION 'post_expired: Cannot react to an expired post';
    END IF;

    IF v_post.user_id = v_caller THEN
        RAISE EXCEPTION 'self_react: Cannot react to your own post';
    END IF;

    -- Upsert: change emoji if already reacted
    INSERT INTO reactions (user_id, post_id, emoji)
    VALUES (v_caller, p_post_id, p_emoji)
    ON CONFLICT (user_id, post_id) DO UPDATE
    SET emoji = EXCLUDED.emoji, created_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── REMOVE REACTION ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION remove_reaction(p_post_id UUID)
RETURNS VOID AS $$
BEGIN
    DELETE FROM reactions
    WHERE user_id = auth_uid() AND post_id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── GET REACTIONS FOR POSTS (batch) ────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_post_reactions(p_post_ids UUID[])
RETURNS TABLE (
    post_id UUID,
    emoji TEXT,
    count BIGINT,
    user_reacted BOOLEAN
) AS $$
DECLARE
    v_caller UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        r.post_id,
        r.emoji,
        COUNT(*)::BIGINT AS count,
        BOOL_OR(r.user_id = v_caller) AS user_reacted
    FROM reactions r
    WHERE r.post_id = ANY(p_post_ids)
    GROUP BY r.post_id, r.emoji
    ORDER BY r.post_id, count DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;
