-- ============================================================================
-- 019: FIX TRIGGER FUNCTIONS — ADD SECURITY DEFINER
-- ============================================================================
-- Problem: follow & like count triggers update OTHER users' rows, but the
-- users_update_own RLS policy (id = auth_uid()) silently blocks cross-user
-- UPDATEs. Follower/following/like counts never increment.
--
-- Fix: make the trigger functions SECURITY DEFINER so they bypass RLS.
-- Also recount existing follows to fix any stale zeros.
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. FOLLOW COUNT TRIGGER — SECURITY DEFINER
-- --------------------------------------------------------------------------
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

    IF TG_OP = 'DELETE' THEN
        PERFORM update_mutual_follow_status(OLD.follower_id, OLD.following_id);
        RETURN OLD;
    ELSE
        PERFORM update_mutual_follow_status(NEW.follower_id, NEW.following_id);
        RETURN NEW;
    END IF;
END;
$$;

-- --------------------------------------------------------------------------
-- 2. LIKE COUNT TRIGGERS — SECURITY DEFINER
-- --------------------------------------------------------------------------
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

    PERFORM decrement_relationship_signal(OLD.user_id, v_author_id, 'like');
    RETURN OLD;
END;
$$;

-- --------------------------------------------------------------------------
-- 3. RECOUNT EXISTING FOLLOWS (fix stale zeros)
-- --------------------------------------------------------------------------
UPDATE users u SET
    follower_count = COALESCE(sub.cnt, 0)
FROM (
    SELECT following_id AS uid, COUNT(*) AS cnt
    FROM follows WHERE is_approved = TRUE
    GROUP BY following_id
) sub
WHERE u.id = sub.uid;

UPDATE users u SET
    following_count = COALESCE(sub.cnt, 0)
FROM (
    SELECT follower_id AS uid, COUNT(*) AS cnt
    FROM follows WHERE is_approved = TRUE
    GROUP BY follower_id
) sub
WHERE u.id = sub.uid;

-- --------------------------------------------------------------------------
-- 4. RECOUNT EXISTING LIKES (fix stale zeros)
-- --------------------------------------------------------------------------
UPDATE posts p SET
    like_count = COALESCE(sub.cnt, 0)
FROM (
    SELECT post_id, COUNT(*) AS cnt
    FROM likes GROUP BY post_id
) sub
WHERE p.id = sub.post_id;

UPDATE users u SET
    total_likes = COALESCE(sub.cnt, 0)
FROM (
    SELECT p.user_id AS uid, COUNT(*) AS cnt
    FROM likes l JOIN posts p ON p.id = l.post_id
    GROUP BY p.user_id
) sub
WHERE u.id = sub.uid;

COMMIT;
