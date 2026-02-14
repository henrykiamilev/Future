-- ============================================================================
-- SEARCH USERS
-- ============================================================================
-- Fuzzy search by username using trigram similarity.
-- Returns users sorted by relevance, excludes blocked users.

CREATE OR REPLACE FUNCTION search_users(
    p_query TEXT,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth_uid();
BEGIN
    p_limit := LEAST(GREATEST(p_limit, 1), 100);
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url
    FROM public.users u
    WHERE u.username ILIKE '%' || REPLACE(REPLACE(REPLACE(p_query, '\', '\\'), '%', '\%'), '_', '\_') || '%' ESCAPE '\'
      AND u.id != v_caller
      -- Exclude blocked users (bidirectional)
      AND NOT EXISTS (
          SELECT 1 FROM public.blocks b
          WHERE (b.blocker_id = v_caller AND b.blocked_id = u.id)
             OR (b.blocker_id = u.id AND b.blocked_id = v_caller)
      )
    ORDER BY similarity(u.username, p_query) DESC
    LIMIT p_limit;
END;
$$;
