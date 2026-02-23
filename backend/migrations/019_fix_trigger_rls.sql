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
-- Use LEFT JOIN so users with zero approved followers/following are also reset.
UPDATE users u SET
    follower_count = COALESCE(sub.cnt, 0)
FROM (
    SELECT u2.id AS uid, COUNT(f.following_id) AS cnt
    FROM users u2
    LEFT JOIN follows f ON f.following_id = u2.id AND f.is_approved = TRUE
    GROUP BY u2.id
) sub
WHERE u.id = sub.uid;

UPDATE users u SET
    following_count = COALESCE(sub.cnt, 0)
FROM (
    SELECT u2.id AS uid, COUNT(f.follower_id) AS cnt
    FROM users u2
    LEFT JOIN follows f ON f.follower_id = u2.id AND f.is_approved = TRUE
    GROUP BY u2.id
) sub
WHERE u.id = sub.uid;

-- --------------------------------------------------------------------------
-- 4. RECOUNT EXISTING LIKES (fix stale zeros)
-- --------------------------------------------------------------------------
-- Use LEFT JOIN so posts/users with zero likes are also reset.
UPDATE posts p SET
    like_count = COALESCE(sub.cnt, 0)
FROM (
    SELECT p2.id AS post_id, COUNT(l.post_id) AS cnt
    FROM posts p2
    LEFT JOIN likes l ON l.post_id = p2.id
    GROUP BY p2.id
) sub
WHERE p.id = sub.post_id;

UPDATE users u SET
    total_likes = COALESCE(sub.cnt, 0)
FROM (
    SELECT u2.id AS uid, COUNT(l.post_id) AS cnt
    FROM users u2
    LEFT JOIN posts p ON p.user_id = u2.id
    LEFT JOIN likes l ON l.post_id = p.id
    GROUP BY u2.id
) sub
WHERE u.id = sub.uid;

COMMIT;
