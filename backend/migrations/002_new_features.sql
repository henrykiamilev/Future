-- ============================================================================
-- MIGRATION 002: NEW FEATURES
-- Comments, Search, Push Tokens, and Followers List Functions
-- ============================================================================
--
-- NOTE: This migration must be run in the Supabase SQL Editor.
--
-- This script combines the following source files into a single migration:
--   1. schema/003_comments_and_search.sql   (tables, indexes, RLS policies)
--   2. functions/011_search_users.sql        (fuzzy username search)
--   3. functions/012_comments.sql            (comment CRUD functions)
--   4. functions/013_followers_list.sql       (followers/following + push tokens)
--
-- The order matters: schema objects must exist before functions that reference
-- them (e.g. the comments table must exist before comment functions).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1) SCHEMA: COMMENTS TABLE + SEARCH + PUSH TOKENS
--    Source: backend/schema/003_comments_and_search.sql
-- ============================================================================

-- Comments on posts (only if post author has comments_enabled = true)
CREATE TABLE IF NOT EXISTS public.comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_comments_post_created
    ON public.comments(post_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_comments_user
    ON public.comments(user_id);

-- Add comments_enabled to users (default false)
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS comments_enabled BOOLEAN NOT NULL DEFAULT false;

-- Device push tokens
CREATE TABLE IF NOT EXISTS public.device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, token)
);

-- Username search index (trigram for partial matching)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_users_username_trgm
    ON public.users USING gin (username gin_trgm_ops);

-- RLS POLICIES FOR COMMENTS

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

-- Anyone can read comments on posts where the author has comments enabled
CREATE POLICY comments_select ON public.comments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.posts p
            JOIN public.users u ON u.id = p.user_id
            WHERE p.id = comments.post_id
              AND u.comments_enabled = true
        )
    );

-- Authenticated users can insert comments on posts where author has comments enabled
CREATE POLICY comments_insert ON public.comments
    FOR INSERT WITH CHECK (
        user_id = auth_uid()
        AND EXISTS (
            SELECT 1 FROM public.posts p
            JOIN public.users u ON u.id = p.user_id
            WHERE p.id = comments.post_id
              AND u.comments_enabled = true
        )
    );

-- Users can delete their own comments, post authors can delete any comment on their posts
CREATE POLICY comments_delete ON public.comments
    FOR DELETE USING (
        user_id = auth_uid()
        OR EXISTS (
            SELECT 1 FROM public.posts p
            WHERE p.id = comments.post_id AND p.user_id = auth_uid()
        )
    );

-- RLS for device_tokens
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY device_tokens_own ON public.device_tokens
    FOR ALL USING (user_id = auth_uid())
    WITH CHECK (user_id = auth_uid());

-- ============================================================================
-- 2) FUNCTION: SEARCH USERS
--    Source: backend/functions/011_search_users.sql
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
AS $$
DECLARE
    v_caller UUID := auth_uid();
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url
    FROM public.users u
    WHERE u.username ILIKE '%' || p_query || '%'
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

-- ============================================================================
-- 3) FUNCTIONS: COMMENTS (get, add, delete)
--    Source: backend/functions/012_comments.sql
-- ============================================================================

-- Get comments for a post (paginated, newest first)
CREATE OR REPLACE FUNCTION get_post_comments(
    p_post_id UUID,
    p_cursor TIMESTAMPTZ DEFAULT NULL,
    p_limit INT DEFAULT 30
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_comments JSON;
    v_count INT;
BEGIN
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
END;
$$;

-- ============================================================================
-- 4) FUNCTIONS: FOLLOWERS / FOLLOWING LIST + PUSH TOKEN REGISTRATION
--    Source: backend/functions/013_followers_list.sql
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

COMMIT;
