-- ============================================================================
-- SIGNATURE SYSTEM
-- ============================================================================
-- Max 3 Signature posts per user.
-- Signature posts remain publicly visible even after the 3-day window.
-- Signature posts continue to accumulate likes.
-- Must remove one to add another (enforced by trigger in 002_triggers.sql).
-- ============================================================================

-- --------------------------------------------------------------------------
-- ADD POST TO SIGNATURE
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION add_to_signature(p_post_id UUID)
RETURNS void AS $$
DECLARE
    v_post RECORD;
    v_sig_count INT;
BEGIN
    -- Verify ownership
    SELECT id, user_id, is_signature, is_hidden
    INTO v_post
    FROM posts
    WHERE id = p_post_id
    FOR UPDATE;

    IF v_post IS NULL THEN
        RAISE EXCEPTION 'post_not_found: Post does not exist';
    END IF;

    IF v_post.user_id != auth_uid() THEN
        RAISE EXCEPTION 'unauthorized: You can only signature your own posts';
    END IF;

    IF v_post.is_hidden THEN
        RAISE EXCEPTION 'post_hidden: Cannot signature a hidden post';
    END IF;

    IF v_post.is_signature THEN
        RAISE EXCEPTION 'already_signature: Post is already in your signature';
    END IF;

    -- Count current signatures (trigger also enforces, but give a clear error)
    SELECT COUNT(*) INTO v_sig_count
    FROM posts
    WHERE user_id = auth_uid() AND is_signature = TRUE
    FOR UPDATE;

    IF v_sig_count >= 3 THEN
        RAISE EXCEPTION 'signature_limit: You already have 3 signature posts. Remove one first.';
    END IF;

    -- Promote to signature
    UPDATE posts
    SET is_signature = TRUE
    WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- REMOVE POST FROM SIGNATURE
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION remove_from_signature(p_post_id UUID)
RETURNS void AS $$
DECLARE
    v_post RECORD;
BEGIN
    SELECT id, user_id, is_signature
    INTO v_post
    FROM posts
    WHERE id = p_post_id
    FOR UPDATE;

    IF v_post IS NULL THEN
        RAISE EXCEPTION 'post_not_found: Post does not exist';
    END IF;

    IF v_post.user_id != auth_uid() THEN
        RAISE EXCEPTION 'unauthorized: You can only modify your own signature';
    END IF;

    IF NOT v_post.is_signature THEN
        RAISE EXCEPTION 'not_signature: Post is not in your signature';
    END IF;

    UPDATE posts
    SET is_signature = FALSE
    WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- REPLACE SIGNATURE POST (atomic swap)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION replace_signature(
    p_remove_post_id UUID,
    p_add_post_id UUID
)
RETURNS void AS $$
BEGIN
    -- Remove the old one first (frees a slot)
    PERFORM remove_from_signature(p_remove_post_id);
    -- Add the new one
    PERFORM add_to_signature(p_add_post_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- --------------------------------------------------------------------------
-- GET USER SIGNATURE POSTS
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_signature_posts(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    image_url TEXT,
    like_count BIGINT,
    view_count BIGINT,
    created_at TIMESTAMPTZ,
    tags JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.image_url,
        p.like_count,
        p.view_count,
        p.created_at,
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'label', t.label,
                    'external_url', t.external_url
                )
            ) FILTER (WHERE t.id IS NOT NULL),
            '[]'::JSONB
        ) AS tags
    FROM posts p
    LEFT JOIN tags t ON t.post_id = p.id
    WHERE p.user_id = p_user_id
      AND p.is_signature = TRUE
      AND p.is_hidden = FALSE
    GROUP BY p.id, p.image_url, p.like_count, p.view_count, p.created_at
    ORDER BY p.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;
