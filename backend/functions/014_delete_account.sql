-- ============================================================================
-- DELETE OWN ACCOUNT — Removes both public.users and auth.users
-- ============================================================================
-- SECURITY DEFINER runs as postgres role, which has access to auth schema.
-- Deleting public.users cascades to posts, follows, likes, comments, etc.
-- Deleting auth.users prevents re-authentication.
-- ============================================================================

CREATE OR REPLACE FUNCTION delete_own_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'not_authenticated';
    END IF;

    -- Delete from public.users (cascades to posts, follows, likes, etc.)
    DELETE FROM public.users WHERE id = v_user_id;

    -- Delete from auth.users to prevent re-authentication
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;
