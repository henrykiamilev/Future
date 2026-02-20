-- ============================================================================
-- RECORD POST CONSUMPTION — Tracks what users have seen per day
-- ============================================================================
-- Called fire-and-forget by the iOS client when a post enters the viewport.
-- Updates daily_feed_state counters for caught-up detection and discovery caps.
-- ============================================================================

CREATE OR REPLACE FUNCTION record_post_consumption(
    p_post_id UUID,
    p_feed_type TEXT  -- 'friends' or 'discovery'
)
RETURNS VOID AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
BEGIN
    -- Validate feed type
    IF p_feed_type NOT IN ('friends', 'discovery') THEN
        RETURN;
    END IF;

    -- Upsert daily state row for today
    INSERT INTO daily_feed_state (user_id, state_date)
    VALUES (v_viewer_id, CURRENT_DATE)
    ON CONFLICT (user_id, state_date) DO NOTHING;

    -- Increment the appropriate counter
    IF p_feed_type = 'friends' THEN
        UPDATE daily_feed_state
        SET friends_posts_seen = friends_posts_seen + 1
        WHERE user_id = v_viewer_id AND state_date = CURRENT_DATE;
    ELSIF p_feed_type = 'discovery' THEN
        UPDATE daily_feed_state
        SET discovery_items_seen = discovery_items_seen + 1
        WHERE user_id = v_viewer_id AND state_date = CURRENT_DATE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
