-- ============================================================================
-- LIKE SYSTEM — UNIQUENESS ENFORCED
-- ============================================================================
-- One like per user per post (PK constraint on likes table).
-- Denormalized counters updated via triggers (002_triggers.sql).
-- Lifetime total on users.total_likes updated via triggers.
-- ============================================================================

-- --------------------------------------------------------------------------
-- LIKE A POST
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION like_post(p_post_id UUID)
RETURNS TABLE (new_like_count BIGINT) AS $$
DECLARE
    v_post RECORD;
BEGIN
    -- Verify post exists and is visible
    SELECT p.id, p.user_id, p.is_hidden, p.expires_at, p.is_signature
    INTO v_post
    FROM posts p
    WHERE p.id = p_post_id;

    IF v_post IS NULL OR v_post.is_hidden THEN
        RAISE EXCEPTION 'post_not_accessible: Post is not available';
    END IF;

    -- Allow liking expired posts ONLY if they are signature posts
    IF v_post.expires_at <= now() AND NOT v_post.is_signature THEN
        RAISE EXCEPTION 'post_expired: Cannot like an expired post';
    END IF;

    -- Cannot like your own post
    IF v_post.user_id = auth_uid() THEN
        RAISE EXCEPTION 'self_like: Cannot like your own post';
    END IF;

    -- Insert like (PK constraint enforces uniqueness — will raise on duplicate)
    BEGIN
        INSERT INTO likes (user_id, post_id)
        VALUES (auth_uid(), p_post_id);
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'already_liked: You have already liked this post';
    END;

    -- Return updated count
    RETURN QUERY
    SELECT p.like_count FROM posts p WHERE p.id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- UNLIKE A POST
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION unlike_post(p_post_id UUID)
RETURNS TABLE (new_like_count BIGINT) AS $$
DECLARE
    v_deleted BOOLEAN;
BEGIN
    DELETE FROM likes
    WHERE user_id = auth_uid() AND post_id = p_post_id
    RETURNING TRUE INTO v_deleted;

    IF v_deleted IS NULL THEN
        RAISE EXCEPTION 'not_liked: You have not liked this post';
    END IF;

    RETURN QUERY
    SELECT p.like_count FROM posts p WHERE p.id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- CHECK IF CURRENT USER LIKED POSTS (batch — avoids N+1)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_liked_posts(p_post_ids UUID[])
RETURNS TABLE (post_id UUID, is_liked BOOLEAN) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pid,
        EXISTS (
            SELECT 1 FROM likes l
            WHERE l.post_id = pid AND l.user_id = auth_uid()
        ) AS is_liked
    FROM unnest(p_post_ids) AS pid;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;
