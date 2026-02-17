-- ============================================================================
-- COMMENT FUNCTIONS
-- ============================================================================

-- Get comments for a post (paginated, newest first)
CREATE OR REPLACE FUNCTION get_post_comments(
    p_post_id UUID,
    p_cursor TIMESTAMPTZ DEFAULT NULL,
    p_limit INT DEFAULT 30
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_comments JSON;
    v_count INT;
BEGIN
    p_limit := LEAST(GREATEST(p_limit, 1), 100);
    -- Verify the post author has comments enabled
    IF NOT EXISTS (
        SELECT 1 FROM public.posts p
        JOIN public.users u ON u.id = p.user_id
        WHERE p.id = p_post_id AND u.comments_enabled = true
    ) THEN
        RETURN json_build_object('comments', '[]'::json, 'hasMore', false);
    END IF;

    SELECT json_agg(row_to_json(c)), count(*)
    INTO v_comments, v_count
    FROM (
        SELECT
            cm.id,
            cm.post_id AS "postId",
            cm.user_id AS "userId",
            u.username,
            u.profile_photo_url AS "authorPhoto",
            cm.content,
            cm.created_at AS "createdAt"
        FROM public.comments cm
        JOIN public.users u ON u.id = cm.user_id
        WHERE cm.post_id = p_post_id
          AND (p_cursor IS NULL OR cm.created_at < p_cursor)
        ORDER BY cm.created_at DESC
        LIMIT p_limit + 1
    ) c;

    IF v_comments IS NULL THEN
        v_comments := '[]'::json;
    END IF;

    RETURN json_build_object(
        'comments', CASE WHEN v_count > p_limit
            THEN (SELECT json_agg(x) FROM (SELECT * FROM json_array_elements(v_comments) LIMIT p_limit) x)
            ELSE v_comments END,
        'hasMore', v_count > p_limit
    );
END;
$$;

-- Add a comment to a post
CREATE OR REPLACE FUNCTION add_comment(
    p_post_id UUID,
    p_content TEXT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth_uid();
    v_comment_id UUID;
    v_username TEXT;
    v_photo TEXT;
BEGIN
    -- Verify comments are enabled for this post's author
    IF NOT EXISTS (
        SELECT 1 FROM public.posts p
        JOIN public.users u ON u.id = p.user_id
        WHERE p.id = p_post_id AND u.comments_enabled = true
    ) THEN
        RAISE EXCEPTION 'comments_disabled' USING ERRCODE = 'P0001';
    END IF;

    -- Validate content length
    IF char_length(trim(p_content)) < 1 OR char_length(trim(p_content)) > 500 THEN
        RAISE EXCEPTION 'comment_too_long' USING ERRCODE = 'P0001';
    END IF;

    -- Insert comment
    INSERT INTO public.comments (post_id, user_id, content)
    VALUES (p_post_id, v_caller, trim(p_content))
    RETURNING id INTO v_comment_id;

    -- Get caller info
    SELECT username, profile_photo_url INTO v_username, v_photo
    FROM public.users WHERE id = v_caller;

    RETURN json_build_object(
        'id', v_comment_id,
        'postId', p_post_id,
        'userId', v_caller,
        'username', v_username,
        'authorPhoto', v_photo,
        'content', trim(p_content),
        'createdAt', now()
    );
END;
$$;

-- Delete a comment (own comment or post author)
CREATE OR REPLACE FUNCTION delete_comment(
    p_comment_id UUID
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth_uid();
BEGIN
    DELETE FROM public.comments
    WHERE id = p_comment_id
      AND (
          user_id = v_caller
          OR EXISTS (
              SELECT 1 FROM public.posts p
              WHERE p.id = comments.post_id AND p.user_id = v_caller
          )
      );
    IF NOT FOUND THEN
        RAISE EXCEPTION 'comment_not_found';
    END IF;
END;
$$;
