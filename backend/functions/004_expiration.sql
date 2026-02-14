-- ============================================================================
-- POST EXPIRATION LOGIC — 3-DAY VISIBILITY ENFORCEMENT
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. INLINE ENFORCEMENT (built into every query)
--    The expires_at column + RLS policies ensure expired posts are invisible
--    to non-owners. Signature posts are exempt from expiration.
-- --------------------------------------------------------------------------

-- View: Active (non-expired) posts for feed queries
CREATE OR REPLACE VIEW active_posts AS
SELECT p.*,
       u.username,
       u.profile_photo_url AS author_photo,
       u.visibility AS author_visibility,
       u.is_banned AS author_banned
FROM posts p
JOIN users u ON u.id = p.user_id
WHERE p.is_hidden = FALSE
  AND p.expires_at > now()
  AND u.is_banned = FALSE;

-- --------------------------------------------------------------------------
-- 2. BATCH CLEANUP (optional periodic job for archival bookkeeping)
--    This does NOT control visibility — that's handled by expires_at checks.
--    This is for cleanup of old view data, expired exposure records, etc.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cleanup_expired_data()
RETURNS void AS $$
BEGIN
    -- Remove hourly aggregates older than 4 days (posts expire at 3 days,
    -- keep 1 extra day for safety)
    DELETE FROM post_view_hourly
    WHERE hour_bucket < now() - INTERVAL '4 days';

    -- Remove feed exposure records with windows older than 48h
    DELETE FROM feed_exposures
    WHERE window_start < now() - INTERVAL '48 hours';

    -- Remove pre-scored entries for expired posts
    DELETE FROM feed_scores
    WHERE post_id IN (
        SELECT id FROM posts WHERE expires_at <= now() AND is_signature = FALSE
    );

    RAISE NOTICE 'Expired data cleanup completed at %', now();
END;
$$ LANGUAGE plpgsql;

-- Schedule via pg_cron (Supabase has pg_cron built-in):
-- SELECT cron.schedule('cleanup-expired', '0 */4 * * *', 'SELECT cleanup_expired_data()');

-- --------------------------------------------------------------------------
-- 3. ARCHIVE QUERY (owner only — enforced by RLS)
-- --------------------------------------------------------------------------
-- Returns all posts for the current user, including expired ones.
-- RLS on posts already allows user_id = auth_uid() to see all their posts.

CREATE OR REPLACE FUNCTION get_user_archive(
    p_cursor TIMESTAMPTZ DEFAULT NULL,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    image_url TEXT,
    like_count BIGINT,
    is_signature BOOLEAN,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ
) AS $$
BEGIN
    p_limit := LEAST(GREATEST(p_limit, 1), 100);
    RETURN QUERY
    SELECT
        p.id,
        p.image_url,
        p.like_count,
        p.is_signature,
        (p.expires_at > now()) AS is_active,
        p.created_at,
        p.expires_at
    FROM posts p
    WHERE p.user_id = auth_uid()
      AND (p_cursor IS NULL OR p.created_at < p_cursor)
    ORDER BY p.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;
