-- ============================================================================
-- COMMENTS TABLE + SEARCH + PUSH TOKENS
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

-- ============================================================================
-- RLS POLICIES FOR COMMENTS
-- ============================================================================

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
