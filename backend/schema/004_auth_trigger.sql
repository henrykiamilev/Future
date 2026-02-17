-- ============================================================================
-- AUTH TRIGGER: Atomically create public.users row on signup
-- ============================================================================
-- When Supabase GoTrue creates an auth.users row, this trigger
-- automatically inserts the corresponding public.users row.
-- The username is read from raw_user_meta_data (set during signUp).
-- This is atomic — if the public.users INSERT fails, the auth.users
-- INSERT is rolled back. No orphaned records possible.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, username)
    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data->>'username',
            'user_' || LEFT(NEW.id::TEXT, 8)
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();
