-- ============================================================================
-- TRIGGERS & ENFORCEMENT
-- ============================================================================

-- --------------------------------------------------------------------------
-- AUTO-SET expires_at TO created_at + 3 days
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_post_expiry()
RETURNS TRIGGER AS $$
BEGIN
    NEW.expires_at := NEW.created_at + INTERVAL '3 days';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_set_expiry
    BEFORE INSERT ON posts
    FOR EACH ROW
    EXECUTE FUNCTION trg_set_post_expiry();

-- --------------------------------------------------------------------------
-- 24-HOUR POSTING RULE (server-side enforcement)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_enforce_24h_posting_rule()
RETURNS TRIGGER AS $$
DECLARE
    v_last_post_at TIMESTAMPTZ;
BEGIN
    SELECT last_post_at INTO v_last_post_at
    FROM users
    WHERE id = NEW.user_id
    FOR UPDATE;  -- lock the user row to prevent race conditions

    IF v_last_post_at IS NOT NULL
       AND v_last_post_at + INTERVAL '24 hours' > now() THEN
        RAISE EXCEPTION 'posting_rate_limit: Must wait 24 hours between posts. Next post allowed at %',
            v_last_post_at + INTERVAL '24 hours';
    END IF;

    -- Update user's last_post_at
    UPDATE users SET last_post_at = now(), updated_at = now()
    WHERE id = NEW.user_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_enforce_24h_rule
    BEFORE INSERT ON posts
    FOR EACH ROW
    EXECUTE FUNCTION trg_enforce_24h_posting_rule();

-- --------------------------------------------------------------------------
-- MAX 3 TAGS PER POST
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_enforce_max_tags()
RETURNS TRIGGER AS $$
DECLARE
    v_tag_count INT;
BEGIN
    SELECT COUNT(*) INTO v_tag_count
    FROM tags
    WHERE post_id = NEW.post_id;

    IF v_tag_count >= 3 THEN
        RAISE EXCEPTION 'tag_limit: Maximum 3 tags per post';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tag_enforce_max
    BEFORE INSERT ON tags
    FOR EACH ROW
    EXECUTE FUNCTION trg_enforce_max_tags();

-- --------------------------------------------------------------------------
-- MAX 3 SIGNATURE POSTS PER USER
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_enforce_max_signatures()
RETURNS TRIGGER AS $$
DECLARE
    v_sig_count INT;
BEGIN
    IF NEW.is_signature = TRUE AND (OLD IS NULL OR OLD.is_signature = FALSE) THEN
        SELECT COUNT(*) INTO v_sig_count
        FROM posts
        WHERE user_id = NEW.user_id AND is_signature = TRUE AND id != NEW.id;

        IF v_sig_count >= 3 THEN
            RAISE EXCEPTION 'signature_limit: Maximum 3 signature posts. Remove one first.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_enforce_max_signatures
    BEFORE INSERT OR UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION trg_enforce_max_signatures();

-- --------------------------------------------------------------------------
-- LIKE COUNT DENORMALIZATION
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_like_count_increment()
RETURNS TRIGGER AS $$
DECLARE
    v_author_id UUID;
BEGIN
    UPDATE posts SET like_count = like_count + 1, updated_at = now()
    WHERE id = NEW.post_id;

    -- Update user's lifetime total_likes
    SELECT user_id INTO v_author_id FROM posts WHERE id = NEW.post_id;
    UPDATE users SET total_likes = total_likes + 1, updated_at = now()
    WHERE id = v_author_id;

    -- Track relationship strength: liker -> post author
    PERFORM increment_relationship_signal(NEW.user_id, v_author_id, 'like');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_like_count_decrement()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER like_after_insert
    AFTER INSERT ON likes
    FOR EACH ROW
    EXECUTE FUNCTION trg_like_count_increment();

CREATE TRIGGER like_after_delete
    AFTER DELETE ON likes
    FOR EACH ROW
    EXECUTE FUNCTION trg_like_count_decrement();

-- --------------------------------------------------------------------------
-- FOLLOWER/FOLLOWING COUNT DENORMALIZATION
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_follow_count_change()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER follow_after_change
    AFTER INSERT OR UPDATE OR DELETE ON follows
    FOR EACH ROW
    EXECUTE FUNCTION trg_follow_count_change();

-- --------------------------------------------------------------------------
-- updated_at AUTO-UPDATE
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_set_updated_at();

CREATE TRIGGER posts_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION trg_set_updated_at();
