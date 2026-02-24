-- ============================================================================
-- POST CREATION — SERVER-SIDE ENFORCEMENT
-- ============================================================================
-- Validates: 24-hour rule, image constraints, tag limits, caption/location.
-- 24-hour rule is double-enforced: here AND via trigger.
-- ============================================================================

CREATE OR REPLACE FUNCTION create_post(
    p_image_url TEXT,
    p_image_width INT,
    p_image_height INT,
    p_image_size_bytes INT,
    p_tags JSONB DEFAULT '[]'::JSONB,   -- array of {label, external_url}
    p_caption TEXT DEFAULT NULL,
    p_location TEXT DEFAULT NULL
)
RETURNS TABLE (
    post_id UUID,
    expires_at TIMESTAMPTZ,
    next_post_allowed_at TIMESTAMPTZ
) AS $$
DECLARE
    v_user RECORD;
    v_new_post_id UUID;
    v_expires TIMESTAMPTZ;
    v_tag RECORD;
    v_tag_count INT := 0;
BEGIN
    -- ----------------------------------------------------------------
    -- 1. VALIDATE USER & 24-HOUR RULE
    -- ----------------------------------------------------------------
    SELECT id, last_post_at, is_banned
    INTO v_user
    FROM users
    WHERE id = auth_uid()
    FOR UPDATE;

    IF v_user IS NULL THEN
        RAISE EXCEPTION 'user_not_found: Authenticated user does not exist';
    END IF;

    IF v_user.is_banned THEN
        RAISE EXCEPTION 'user_banned: Your account has been suspended';
    END IF;

    IF v_user.last_post_at IS NOT NULL
       AND v_user.last_post_at + INTERVAL '24 hours' > now() THEN
        RAISE EXCEPTION 'posting_rate_limit: Must wait 24 hours between posts. Next allowed: %',
            v_user.last_post_at + INTERVAL '24 hours';
    END IF;

    -- ----------------------------------------------------------------
    -- 2. VALIDATE IMAGE CONSTRAINTS
    -- ----------------------------------------------------------------
    IF p_image_size_bytes > 2621440 THEN
        RAISE EXCEPTION 'image_too_large: Image exceeds 2.5MB hard cap (got % bytes)', p_image_size_bytes;
    END IF;

    IF p_image_width > 2048 OR p_image_height > 2048 THEN
        RAISE EXCEPTION 'image_dimensions: Max dimension is 2048px (got %x%)', p_image_width, p_image_height;
    END IF;

    IF p_image_width <= 0 OR p_image_height <= 0 THEN
        RAISE EXCEPTION 'image_dimensions_invalid: Width and height must be positive';
    END IF;

    -- ----------------------------------------------------------------
    -- 3. VALIDATE TAGS
    -- ----------------------------------------------------------------
    IF jsonb_array_length(p_tags) > 3 THEN
        RAISE EXCEPTION 'tag_limit: Maximum 3 tags per post';
    END IF;

    -- ----------------------------------------------------------------
    -- 3b. VALIDATE CAPTION & LOCATION
    -- ----------------------------------------------------------------
    IF p_caption IS NOT NULL AND char_length(p_caption) > 100 THEN
        RAISE EXCEPTION 'caption_too_long: Caption must be 100 characters or fewer';
    END IF;

    IF p_location IS NOT NULL AND char_length(p_location) > 200 THEN
        RAISE EXCEPTION 'location_too_long: Location must be 200 characters or fewer';
    END IF;

    -- ----------------------------------------------------------------
    -- 4. INSERT POST
    --    (Trigger auto-sets expires_at and enforces 24h rule as double-check)
    -- ----------------------------------------------------------------
    INSERT INTO posts (user_id, image_url, image_width, image_height, image_size_bytes, caption, location)
    VALUES (auth_uid(), p_image_url, p_image_width, p_image_height, p_image_size_bytes, p_caption, p_location)
    RETURNING posts.id, posts.expires_at
    INTO v_new_post_id, v_expires;

    -- ----------------------------------------------------------------
    -- 5. INSERT TAGS
    -- ----------------------------------------------------------------
    FOR v_tag IN SELECT * FROM jsonb_to_recordset(p_tags) AS t(label TEXT, external_url TEXT)
    LOOP
        v_tag_count := v_tag_count + 1;
        INSERT INTO tags (post_id, label, external_url)
        VALUES (v_new_post_id, v_tag.label, v_tag.external_url);
    END LOOP;

    -- ----------------------------------------------------------------
    -- 6. RETURN RESULT
    -- ----------------------------------------------------------------
    RETURN QUERY
    SELECT
        v_new_post_id,
        v_expires,
        now() + INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
