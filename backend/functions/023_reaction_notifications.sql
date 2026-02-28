-- ============================================================================
-- MIGRATION: Add reaction notifications + swap 👏 → 😮‍💨
-- ============================================================================
-- Run this in Supabase SQL Editor to apply changes to the live database.
-- ============================================================================

-- ── 1. Add 'reaction' to notification_type enum ──────────────────────────

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'reaction';

-- ── 2. Add emoji column to notifications table ───────────────────────────

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS emoji TEXT;

-- ── 3. Unique index for reaction dedup (one per actor per post) ──────────

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unique_reaction
    ON notifications (user_id, actor_id, type, post_id)
    WHERE type = 'reaction';

-- ── 4. Update get_notifications() to return emoji ────────────────────────

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
    emoji TEXT,
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
        n.emoji,
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

-- ── 5. Trigger: Create notification on REACTION ──────────────────────────

CREATE OR REPLACE FUNCTION notify_on_reaction()
RETURNS TRIGGER AS $$
DECLARE
    v_post_owner UUID;
BEGIN
    SELECT user_id INTO v_post_owner FROM posts WHERE id = NEW.post_id;

    -- Don't notify if reacting to own post
    IF v_post_owner IS NOT NULL AND v_post_owner != NEW.user_id THEN
        INSERT INTO notifications (user_id, actor_id, type, post_id, emoji)
        VALUES (v_post_owner, NEW.user_id, 'reaction', NEW.post_id, NEW.emoji)
        ON CONFLICT (user_id, actor_id, type, post_id)
            WHERE type = 'reaction'
            DO UPDATE SET emoji = EXCLUDED.emoji, created_at = now(), is_read = FALSE;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_notify_on_reaction ON reactions;
CREATE TRIGGER trg_notify_on_reaction
    AFTER INSERT OR UPDATE ON reactions
    FOR EACH ROW EXECUTE FUNCTION notify_on_reaction();

-- ── 6. Swap 👏 → 😮‍💨 in reactions emoji constraint ─────────────────────

-- Drop old constraint and add new one
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_emoji_check;
ALTER TABLE reactions ADD CONSTRAINT reactions_emoji_check
    CHECK (emoji IN ('🔥', '😮‍💨', '😍', '💯', '🤯'));

-- Update any existing 👏 reactions to 😮‍💨
UPDATE reactions SET emoji = '😮‍💨' WHERE emoji = '👏';
