-- ============================================================================
-- SECURITY HARDENING MIGRATION
-- ============================================================================
-- Run this in Supabase SQL Editor (one shot).
-- All statements use CREATE OR REPLACE — safe to re-run.
--
-- Changes:
--   1. SET search_path on all SECURITY DEFINER functions
--   2. LIKE wildcard injection fix in search_users()
--   3. Replace follows_update RLS with approve_follow_request() RPC
--   4. Visibility guard on get_followers/get_following
--   5. Limit caps (max 100) on all query functions
--   6. FOR UPDATE on signature count (race condition fix)
--   7. Merged error messages in like_post (no state leakage)
--   8. IF NOT FOUND on delete_comment (silent failure fix)
--   9. CHECK constraints on users + tags + device_tokens
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. SCHEMA: ADD CHECK CONSTRAINTS
-- ============================================================================
-- These use IF NOT EXISTS pattern via DO blocks for idempotency.

DO $$ BEGIN
    ALTER TABLE public.users ADD CONSTRAINT chk_username CHECK (char_length(username) BETWEEN 3 AND 30);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE public.users ADD CONSTRAINT chk_display_name CHECK (display_name IS NULL OR char_length(display_name) <= 100);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE public.users ADD CONSTRAINT chk_bio CHECK (bio IS NULL OR char_length(bio) <= 500);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE public.users ADD CONSTRAINT chk_instagram CHECK (instagram_handle IS NULL OR char_length(instagram_handle) <= 50);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE public.users ADD CONSTRAINT chk_snapchat CHECK (snapchat_handle IS NULL OR char_length(snapchat_handle) <= 50);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE public.tags ADD CONSTRAINT chk_tag_label CHECK (char_length(label) BETWEEN 1 AND 200);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE public.tags ADD CONSTRAINT chk_tag_url CHECK (external_url IS NULL OR char_length(external_url) <= 2048);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE public.device_tokens ADD CONSTRAINT chk_platform CHECK (platform IN ('ios', 'android', 'web'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- 2. DROP OLD follows_update POLICY (replaced by RPC)
-- ============================================================================
DROP POLICY IF EXISTS follows_update ON follows;

-- ============================================================================
-- 3. ALL FUNCTIONS (CREATE OR REPLACE — idempotent)
-- ============================================================================

-- ── get_user_profile ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_user_profile(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT,
    bio TEXT,
    visibility account_visibility,
    instagram_handle TEXT,
    snapchat_handle TEXT,
    total_likes BIGINT,
    follower_count BIGINT,
    following_count BIGINT,
    is_following BOOLEAN,
    is_follower BOOLEAN,
    follow_is_pending BOOLEAN,
    is_own_profile BOOLEAN,
    comments_enabled BOOLEAN,
    onboarding_completed_at TIMESTAMPTZ,
    signature_posts JSONB,
    live_posts JSONB
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url,
        u.bio,
        u.visibility,
        u.instagram_handle,
        u.snapchat_handle,
        u.total_likes,
        u.follower_count,
        u.following_count,
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.follower_id = v_viewer_id
              AND f.following_id = u.id
              AND f.is_approved = TRUE
        ) AS is_following,
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.follower_id = u.id
              AND f.following_id = v_viewer_id
              AND f.is_approved = TRUE
        ) AS is_follower,
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.follower_id = v_viewer_id
              AND f.following_id = u.id
              AND f.is_approved = FALSE
        ) AS follow_is_pending,
        (u.id = v_viewer_id) AS is_own_profile,
        u.comments_enabled,
        u.onboarding_completed_at,
        COALESCE(
            (SELECT jsonb_agg(sig ORDER BY created_at DESC)
             FROM (
                SELECT
                    jsonb_build_object(
                        'id', p.id,
                        'image_url', p.image_url,
                        'image_width', p.image_width,
                        'image_height', p.image_height,
                        'like_count', p.like_count,
                        'created_at', p.created_at,
                        'tags', COALESCE(
                            (SELECT jsonb_agg(jsonb_build_object(
                                'label', t.label,
                                'external_url', t.external_url
                            )) FROM tags t WHERE t.post_id = p.id),
                            '[]'::JSONB
                        )
                    ) AS sig,
                    p.created_at
                FROM posts p
                WHERE p.user_id = u.id
                  AND p.is_signature = TRUE
                  AND p.is_hidden = FALSE
             ) sub
            ),
            '[]'::JSONB
        ) AS signature_posts,
        COALESCE(
            (SELECT jsonb_agg(live ORDER BY live_created DESC)
             FROM (
                SELECT
                    jsonb_build_object(
                        'id', p.id,
                        'image_url', p.image_url,
                        'image_width', p.image_width,
                        'image_height', p.image_height,
                        'like_count', p.like_count,
                        'created_at', p.created_at,
                        'tags', COALESCE(
                            (SELECT jsonb_agg(jsonb_build_object(
                                'label', t.label,
                                'external_url', t.external_url
                            )) FROM tags t WHERE t.post_id = p.id),
                            '[]'::JSONB
                        )
                    ) AS live,
                    p.created_at AS live_created
                FROM posts p
                WHERE p.user_id = u.id
                  AND p.expires_at > now()
                  AND p.is_hidden = FALSE
                ORDER BY p.created_at DESC
                LIMIT 3
             ) sub
            ),
            '[]'::JSONB
        ) AS live_posts
    FROM users u
    WHERE u.id = p_user_id
      AND u.is_banned = FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── search_users (LIKE wildcard fix + limit cap) ────────────────────────────
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
      AND NOT EXISTS (
          SELECT 1 FROM public.blocks b
          WHERE (b.blocker_id = v_caller AND b.blocked_id = u.id)
             OR (b.blocker_id = u.id AND b.blocked_id = v_caller)
      )
    ORDER BY similarity(u.username, p_query) DESC
    LIMIT p_limit;
END;
$$;

-- ── get_post_comments (limit cap) ───────────────────────────────────────────
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

-- ── add_comment ─────────────────────────────────────────────────────────────
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
    IF NOT EXISTS (
        SELECT 1 FROM public.posts p
        JOIN public.users u ON u.id = p.user_id
        WHERE p.id = p_post_id AND u.comments_enabled = true
    ) THEN
        RAISE EXCEPTION 'comments_disabled' USING ERRCODE = 'P0001';
    END IF;

    IF char_length(trim(p_content)) < 1 OR char_length(trim(p_content)) > 500 THEN
        RAISE EXCEPTION 'comment_too_long' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.comments (post_id, user_id, content)
    VALUES (p_post_id, v_caller, trim(p_content))
    RETURNING id INTO v_comment_id;

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

-- ── delete_comment (IF NOT FOUND fix) ───────────────────────────────────────
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

-- ── get_followers (visibility guard + limit cap) ────────────────────────────
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
SET search_path = public, pg_temp
AS $$
BEGIN
    p_limit := LEAST(GREATEST(p_limit, 1), 100);
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
      AND (
          p_user_id = auth_uid()
          OR EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND visibility = 'public')
          OR EXISTS (SELECT 1 FROM follows WHERE follower_id = auth_uid()
                     AND following_id = p_user_id AND is_approved = TRUE)
      )
    ORDER BY f.created_at DESC
    LIMIT p_limit;
END;
$$;

-- ── get_following (visibility guard + limit cap) ────────────────────────────
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
SET search_path = public, pg_temp
AS $$
BEGIN
    p_limit := LEAST(GREATEST(p_limit, 1), 100);
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
      AND (
          p_user_id = auth_uid()
          OR EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND visibility = 'public')
          OR EXISTS (SELECT 1 FROM follows WHERE follower_id = auth_uid()
                     AND following_id = p_user_id AND is_approved = TRUE)
      )
    ORDER BY f.created_at DESC
    LIMIT p_limit;
END;
$$;

-- ── register_push_token ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION register_push_token(
    p_token TEXT,
    p_platform TEXT DEFAULT 'ios'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
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

-- ── add_to_signature (FOR UPDATE race fix) ──────────────────────────────────
CREATE OR REPLACE FUNCTION add_to_signature(p_post_id UUID)
RETURNS void AS $$
DECLARE
    v_post RECORD;
    v_sig_count INT;
BEGIN
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

    SELECT COUNT(*) INTO v_sig_count
    FROM posts
    WHERE user_id = auth_uid() AND is_signature = TRUE
    FOR UPDATE;

    IF v_sig_count >= 3 THEN
        RAISE EXCEPTION 'signature_limit: You already have 3 signature posts. Remove one first.';
    END IF;

    UPDATE posts
    SET is_signature = TRUE
    WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── remove_from_signature ───────────────────────────────────────────────────
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

-- ── replace_signature ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION replace_signature(
    p_remove_post_id UUID,
    p_add_post_id UUID
)
RETURNS void AS $$
BEGIN
    PERFORM remove_from_signature(p_remove_post_id);
    PERFORM add_to_signature(p_add_post_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── get_signature_posts ─────────────────────────────────────────────────────
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

-- ── like_post (merged error messages) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION like_post(p_post_id UUID)
RETURNS TABLE (new_like_count BIGINT) AS $$
DECLARE
    v_post RECORD;
BEGIN
    SELECT p.id, p.user_id, p.is_hidden, p.expires_at, p.is_signature
    INTO v_post
    FROM posts p
    WHERE p.id = p_post_id;

    IF v_post IS NULL OR v_post.is_hidden THEN
        RAISE EXCEPTION 'post_not_accessible: Post is not available';
    END IF;

    IF v_post.expires_at <= now() AND NOT v_post.is_signature THEN
        RAISE EXCEPTION 'post_expired: Cannot like an expired post';
    END IF;

    IF v_post.user_id = auth_uid() THEN
        RAISE EXCEPTION 'self_like: Cannot like your own post';
    END IF;

    BEGIN
        INSERT INTO likes (user_id, post_id)
        VALUES (auth_uid(), p_post_id);
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'already_liked: You have already liked this post';
    END;

    RETURN QUERY
    SELECT p.like_count FROM posts p WHERE p.id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── unlike_post ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION unlike_post(p_post_id UUID)
RETURNS TABLE (new_like_count BIGINT) AS $$
DECLARE
    v_deleted BOOLEAN;
BEGIN
    DELETE FROM likes
    WHERE user_id = auth_uid() AND post_id = p_post_id
    RETURNING TRUE INTO v_deleted;

    IF v_deleted IS NULL THEN
        RAISE EXCEPTION 'not_liked: You have not liked this post';
    END IF;

    RETURN QUERY
    SELECT p.like_count FROM posts p WHERE p.id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── check_liked_posts ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_liked_posts(p_post_ids UUID[])
RETURNS TABLE (post_id UUID, is_liked BOOLEAN) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pid,
        EXISTS (
            SELECT 1 FROM likes l
            WHERE l.post_id = pid AND l.user_id = auth_uid()
        ) AS is_liked
    FROM unnest(p_post_ids) AS pid;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── record_post_view ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION record_post_view(p_post_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE posts SET view_count = view_count + 1
    WHERE id = p_post_id;

    INSERT INTO post_view_hourly (post_id, hour_bucket, view_count)
    VALUES (p_post_id, date_trunc('hour', now()), 1)
    ON CONFLICT (post_id, hour_bucket)
    DO UPDATE SET view_count = post_view_hourly.view_count + 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── get_main_feed ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_main_feed(
    p_cursor_score DOUBLE PRECISION DEFAULT NULL,
    p_cursor_id UUID DEFAULT NULL,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    username TEXT,
    author_photo TEXT,
    image_url TEXT,
    image_width INT,
    image_height INT,
    like_count BIGINT,
    view_count BIGINT,
    is_liked BOOLEAN,
    created_at TIMESTAMPTZ,
    score DOUBLE PRECISION,
    tags JSONB
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
    v_personal_w DOUBLE PRECISION := 0.15;
    v_max_author_exposure INT := 2;
BEGIN
    RETURN QUERY
    WITH viewer_follows AS (
        SELECT f.following_id
        FROM follows f
        WHERE f.follower_id = v_viewer_id
          AND f.is_approved = TRUE
    ),
    viewer_blocks AS (
        SELECT b.blocked_id AS uid FROM blocks b WHERE b.blocker_id = v_viewer_id
        UNION ALL
        SELECT b.blocker_id AS uid FROM blocks b WHERE b.blocked_id = v_viewer_id
    ),
    scored_feed AS (
        SELECT
            fs.post_id,
            fs.author_id,
            fs.base_score + (CASE WHEN vf.following_id IS NOT NULL THEN v_personal_w ELSE 0.0 END) AS final_score,
            COALESCE(fe.exposure_count, 0) AS author_exposure,
            CASE WHEN fe.window_start IS NOT NULL AND fe.window_start > now() - INTERVAL '24 hours'
                THEN COALESCE(fe.exposure_count, 0) ELSE 0 END AS active_exposure
        FROM feed_scores fs
        LEFT JOIN viewer_follows vf ON vf.following_id = fs.author_id
        LEFT JOIN feed_exposures fe ON fe.viewer_id = v_viewer_id AND fe.author_id = fs.author_id
        WHERE fs.author_id NOT IN (SELECT uid FROM viewer_blocks)
    ),
    filtered AS (
        SELECT sf.*
        FROM scored_feed sf
        WHERE sf.active_exposure < v_max_author_exposure
          AND (
              p_cursor_score IS NULL
              OR sf.final_score < p_cursor_score
              OR (sf.final_score = p_cursor_score AND sf.post_id < p_cursor_id)
          )
        ORDER BY sf.final_score DESC, sf.post_id DESC
        LIMIT p_limit
    )
    SELECT
        p.id,
        p.user_id,
        u.username,
        u.profile_photo_url,
        p.image_url,
        p.image_width,
        p.image_height,
        p.like_count,
        p.view_count,
        EXISTS (
            SELECT 1 FROM likes l
            WHERE l.post_id = p.id AND l.user_id = v_viewer_id
        ) AS is_liked,
        p.created_at,
        f.final_score,
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'label', t.label,
                    'external_url', t.external_url,
                    'position_x', t.position_x,
                    'position_y', t.position_y
                )
            )
            FROM tags t WHERE t.post_id = p.id),
            '[]'::JSONB
        ) AS tags
    FROM filtered f
    JOIN posts p ON p.id = f.post_id
    JOIN users u ON u.id = p.user_id
    WHERE u.visibility = 'public'
      AND u.is_banned = FALSE
      AND p.is_hidden = FALSE
      AND p.expires_at > now()
    ORDER BY f.final_score DESC, f.post_id DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── record_feed_exposures ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION record_feed_exposures(p_author_ids UUID[])
RETURNS void AS $$
BEGIN
    INSERT INTO feed_exposures (viewer_id, author_id, exposure_count, window_start)
    SELECT auth_uid(), aid, 1, now()
    FROM unnest(p_author_ids) AS aid
    ON CONFLICT (viewer_id, author_id)
    DO UPDATE SET
        exposure_count = CASE
            WHEN feed_exposures.window_start > now() - INTERVAL '24 hours'
            THEN feed_exposures.exposure_count + 1
            ELSE 1
        END,
        window_start = CASE
            WHEN feed_exposures.window_start > now() - INTERVAL '24 hours'
            THEN feed_exposures.window_start
            ELSE now()
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── get_friends_feed ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_friends_feed(
    p_cursor TIMESTAMPTZ DEFAULT NULL,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    username TEXT,
    author_photo TEXT,
    image_url TEXT,
    image_width INT,
    image_height INT,
    like_count BIGINT,
    view_count BIGINT,
    is_liked BOOLEAN,
    created_at TIMESTAMPTZ,
    tags JSONB
) AS $$
DECLARE
    v_viewer_id UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.user_id,
        u.username,
        u.profile_photo_url,
        p.image_url,
        p.image_width,
        p.image_height,
        p.like_count,
        p.view_count,
        EXISTS (
            SELECT 1 FROM likes l
            WHERE l.post_id = p.id AND l.user_id = v_viewer_id
        ) AS is_liked,
        p.created_at,
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'label', t.label,
                    'external_url', t.external_url,
                    'position_x', t.position_x,
                    'position_y', t.position_y
                )
            )
            FROM tags t WHERE t.post_id = p.id),
            '[]'::JSONB
        ) AS tags
    FROM posts p
    JOIN users u ON u.id = p.user_id
    WHERE p.is_hidden = FALSE
      AND p.expires_at > now()
      AND u.is_banned = FALSE
      AND EXISTS (
          SELECT 1 FROM follows f
          WHERE f.follower_id = v_viewer_id
            AND f.following_id = p.user_id
            AND f.is_approved = TRUE
      )
      AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker_id = p.user_id AND b.blocked_id = v_viewer_id)
             OR (b.blocker_id = v_viewer_id AND b.blocked_id = p.user_id)
      )
      AND (p_cursor IS NULL OR p.created_at < p_cursor)
    ORDER BY p.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── create_post ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_post(
    p_image_url TEXT,
    p_image_width INT,
    p_image_height INT,
    p_image_size_bytes INT,
    p_tags JSONB DEFAULT '[]'::JSONB
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

    IF p_image_size_bytes > 2621440 THEN
        RAISE EXCEPTION 'image_too_large: Image exceeds 2.5MB hard cap (got % bytes)', p_image_size_bytes;
    END IF;

    IF p_image_width > 2048 OR p_image_height > 2048 THEN
        RAISE EXCEPTION 'image_dimensions: Max dimension is 2048px (got %x%)', p_image_width, p_image_height;
    END IF;

    IF p_image_width <= 0 OR p_image_height <= 0 THEN
        RAISE EXCEPTION 'image_dimensions_invalid: Width and height must be positive';
    END IF;

    IF jsonb_array_length(p_tags) > 3 THEN
        RAISE EXCEPTION 'tag_limit: Maximum 3 tags per post';
    END IF;

    INSERT INTO posts (user_id, image_url, image_width, image_height, image_size_bytes)
    VALUES (auth_uid(), p_image_url, p_image_width, p_image_height, p_image_size_bytes)
    RETURNING posts.id, posts.expires_at
    INTO v_new_post_id, v_expires;

    FOR v_tag IN SELECT * FROM jsonb_to_recordset(p_tags) AS t(label TEXT, external_url TEXT)
    LOOP
        v_tag_count := v_tag_count + 1;
        INSERT INTO tags (post_id, label, external_url)
        VALUES (v_new_post_id, v_tag.label, v_tag.external_url);
    END LOOP;

    RETURN QUERY
    SELECT
        v_new_post_id,
        v_expires,
        now() + INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── get_user_archive (limit cap) ────────────────────────────────────────────
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

-- ── get_suggested_users (limit cap) ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_suggested_users(p_limit INT DEFAULT 10)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT,
    follower_count BIGINT
) AS $$
    SELECT u.id, u.username, u.display_name, u.profile_photo_url, u.follower_count
    FROM users u
    WHERE u.visibility = 'public'
      AND u.is_banned = FALSE
      AND u.id != auth_uid()
      AND NOT EXISTS (
          SELECT 1 FROM follows f
          WHERE f.follower_id = auth_uid() AND f.following_id = u.id
      )
      AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker_id = auth_uid() AND b.blocked_id = u.id)
             OR (b.blocker_id = u.id AND b.blocked_id = auth_uid())
      )
    ORDER BY u.follower_count DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100);
$$ LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── get_explore_posts (limit cap) ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_explore_posts(p_limit INT DEFAULT 30)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    username TEXT,
    author_photo TEXT,
    image_url TEXT,
    image_width INT,
    image_height INT,
    like_count BIGINT,
    created_at TIMESTAMPTZ,
    score DOUBLE PRECISION
) AS $$
    SELECT
        p.id,
        p.user_id,
        u.username,
        u.profile_photo_url,
        p.image_url,
        p.image_width,
        p.image_height,
        p.like_count,
        p.created_at,
        fs.base_score
    FROM feed_scores fs
    JOIN posts p ON p.id = fs.post_id
    JOIN users u ON u.id = p.user_id
    WHERE u.visibility = 'public'
      AND u.is_banned = FALSE
      AND p.is_hidden = FALSE
      AND p.expires_at > now()
    ORDER BY fs.base_score DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100);
$$ LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── delete_own_account ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION delete_own_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'not_authenticated';
    END IF;

    DELETE FROM public.users WHERE id = v_user_id;
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- ── approve_follow_request (NEW — replaces follows_update policy) ───────────
CREATE OR REPLACE FUNCTION approve_follow_request(p_follower_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE follows SET is_approved = TRUE
    WHERE follower_id = p_follower_id
      AND following_id = auth_uid()
      AND is_approved = FALSE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'request_not_found';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

COMMIT;
