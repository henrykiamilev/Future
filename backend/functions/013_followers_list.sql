-- ============================================================================
-- FOLLOWERS / FOLLOWING LIST FUNCTIONS
-- ============================================================================

-- Get followers for a user
CREATE OR REPLACE FUNCTION get_followers(
    p_user_id UUID,
    p_limit INT DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url
    FROM public.follows f
    JOIN public.users u ON u.id = f.follower_id
    WHERE f.following_id = p_user_id
      AND f.is_approved = TRUE
    ORDER BY f.created_at DESC
    LIMIT p_limit;
END;
$$;

-- Get who a user is following
CREATE OR REPLACE FUNCTION get_following(
    p_user_id UUID,
    p_limit INT DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url
    FROM public.follows f
    JOIN public.users u ON u.id = f.following_id
    WHERE f.follower_id = p_user_id
      AND f.is_approved = TRUE
    ORDER BY f.created_at DESC
    LIMIT p_limit;
END;
$$;

-- Register push token (upsert)
CREATE OR REPLACE FUNCTION register_push_token(
    p_token TEXT,
    p_platform TEXT DEFAULT 'ios'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_caller UUID := auth_uid();
BEGIN
    INSERT INTO public.device_tokens (user_id, token, platform)
    VALUES (v_caller, p_token, p_platform)
    ON CONFLICT (user_id, token) DO UPDATE
    SET created_at = now();
END;
$$;
