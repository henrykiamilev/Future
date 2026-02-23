-- ============================================================================
-- NOTIFICATIONS — In-app notification system
-- ============================================================================
-- Stores like, follow, and comment notifications.
-- Trigger functions auto-insert rows when events happen.
-- The client polls get_notifications() for the activity feed.
-- ============================================================================

-- ── ENUM ────────────────────────────────────────────────────────────────────

DO $$ BEGIN
    CREATE TYPE notification_type AS ENUM ('like', 'follow', 'comment');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- ── TABLE ───────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- recipient
    actor_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- who did the action
    type        notification_type NOT NULL,
    post_id     UUID REFERENCES posts(id) ON DELETE CASCADE,            -- NULL for follow notifs
    comment_id  UUID REFERENCES comments(id) ON DELETE CASCADE,         -- only for comment notifs
    is_read     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_no_self_notify CHECK (user_id != actor_id)
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON notifications (user_id, created_at DESC)
    WHERE is_read = FALSE;

CREATE INDEX IF NOT EXISTS idx_notifications_user_all
    ON notifications (user_id, created_at DESC);

-- Prevent duplicate notifications for the same event
CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unique_like
    ON notifications (user_id, actor_id, type, post_id)
    WHERE type = 'like';

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unique_follow
    ON notifications (user_id, actor_id, type)
    WHERE type = 'follow' AND post_id IS NULL;

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY notifications_select_own ON notifications
    FOR SELECT USING (user_id = auth_uid());

CREATE POLICY notifications_update_own ON notifications
    FOR UPDATE USING (user_id = auth_uid())
    WITH CHECK (user_id = auth_uid());

-- Only triggers (SECURITY DEFINER) insert notifications, not users directly
-- No INSERT policy needed for regular users

-- ── GET NOTIFICATIONS (paginated) ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_notifications(
    p_cursor TIMESTAMPTZ DEFAULT NULL,
    p_limit INT DEFAULT 30
)
RETURNS TABLE (
    id UUID,
    type TEXT,
    actor_id UUID,
    actor_username TEXT,
    actor_photo TEXT,
    post_id UUID,
    post_image_url TEXT,
    comment_preview TEXT,
    is_read BOOLEAN,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    v_user_id UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        n.id,
        n.type::TEXT,
        n.actor_id,
        u.username AS actor_username,
        u.profile_photo_url AS actor_photo,
        n.post_id,
        p.image_url AS post_image_url,
        LEFT(c.content, 100) AS comment_preview,
        n.is_read,
        n.created_at
    FROM notifications n
    JOIN users u ON u.id = n.actor_id
    LEFT JOIN posts p ON p.id = n.post_id
    LEFT JOIN comments c ON c.id = n.comment_id
    WHERE n.user_id = v_user_id
      AND (p_cursor IS NULL OR n.created_at < p_cursor)
    ORDER BY n.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── MARK ALL AS READ ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION mark_notifications_read()
RETURNS VOID AS $$
BEGIN
    UPDATE notifications
    SET is_read = TRUE
    WHERE user_id = auth_uid()
      AND is_read = FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── UNREAD COUNT ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_unread_notification_count()
RETURNS BIGINT AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM notifications
        WHERE user_id = auth_uid()
          AND is_read = FALSE
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── TRIGGER: Create notification on LIKE ───────────────────────────────────

CREATE OR REPLACE FUNCTION notify_on_like()
RETURNS TRIGGER AS $$
DECLARE
    v_post_owner UUID;
BEGIN
    SELECT user_id INTO v_post_owner FROM posts WHERE id = NEW.post_id;

    -- Don't notify if liking own post
    IF v_post_owner IS NOT NULL AND v_post_owner != NEW.user_id THEN
        INSERT INTO notifications (user_id, actor_id, type, post_id)
        VALUES (v_post_owner, NEW.user_id, 'like', NEW.post_id)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_notify_on_like ON likes;
CREATE TRIGGER trg_notify_on_like
    AFTER INSERT ON likes
    FOR EACH ROW EXECUTE FUNCTION notify_on_like();

-- ── TRIGGER: Create notification on FOLLOW ─────────────────────────────────

CREATE OR REPLACE FUNCTION notify_on_follow()
RETURNS TRIGGER AS $$
BEGIN
    -- Only notify on approved follows (not pending requests)
    IF NEW.is_approved = TRUE THEN
        INSERT INTO notifications (user_id, actor_id, type)
        VALUES (NEW.following_id, NEW.follower_id, 'follow')
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_notify_on_follow ON follows;
CREATE TRIGGER trg_notify_on_follow
    AFTER INSERT ON follows
    FOR EACH ROW EXECUTE FUNCTION notify_on_follow();

-- ── TRIGGER: Create notification on COMMENT ────────────────────────────────

CREATE OR REPLACE FUNCTION notify_on_comment()
RETURNS TRIGGER AS $$
DECLARE
    v_post_owner UUID;
BEGIN
    SELECT user_id INTO v_post_owner FROM posts WHERE id = NEW.post_id;

    -- Don't notify if commenting on own post
    IF v_post_owner IS NOT NULL AND v_post_owner != NEW.user_id THEN
        INSERT INTO notifications (user_id, actor_id, type, post_id, comment_id)
        VALUES (v_post_owner, NEW.user_id, 'comment', NEW.post_id, NEW.id)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_notify_on_comment ON comments;
CREATE TRIGGER trg_notify_on_comment
    AFTER INSERT ON comments
    FOR EACH ROW EXECUTE FUNCTION notify_on_comment();
