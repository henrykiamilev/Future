-- ============================================================================
-- SHUFFLE MODE — Card-swipe people discovery
-- ============================================================================
-- Tables: shuffle_seen (daily swipe tracking), saved_users (bookmarks)
-- Functions: get_shuffle_deck, record_shuffle_action, get_saved_users
-- ============================================================================

-- Track which users have been seen in shuffle today
CREATE TABLE IF NOT EXISTS shuffle_seen (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    seen_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    seen_date DATE NOT NULL DEFAULT CURRENT_DATE,
    action TEXT NOT NULL CHECK (action IN ('followed', 'skipped', 'saved')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, seen_user_id, seen_date)
);

CREATE INDEX IF NOT EXISTS idx_shuffle_seen_date ON shuffle_seen (user_id, seen_date);

-- Saved users (bookmarks from shuffle "save for later")
CREATE TABLE IF NOT EXISTS saved_users (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    saved_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, saved_user_id),
    CONSTRAINT chk_no_self_save CHECK (user_id != saved_user_id)
);

-- RLS policies
ALTER TABLE shuffle_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own shuffle_seen"
    ON shuffle_seen FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Users can insert own shuffle_seen"
    ON shuffle_seen FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can read own saved_users"
    ON saved_users FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Users can insert own saved_users"
    ON saved_users FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own saved_users"
    ON saved_users FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================================
-- get_shuffle_deck: Returns a deck of profile cards for shuffle mode
-- ============================================================================
CREATE OR REPLACE FUNCTION get_shuffle_deck(p_limit INT DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_limit INT := LEAST(p_limit, 30);  -- cap at 30
    v_daily_cap INT := 20;
    v_seen_today INT;
    v_result JSONB;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Count how many shuffle cards seen today
    SELECT COUNT(*)
    INTO v_seen_today
    FROM shuffle_seen
    WHERE user_id = v_uid AND seen_date = CURRENT_DATE;

    -- If exhausted, return empty with metadata
    IF v_seen_today >= v_daily_cap THEN
        RETURN jsonb_build_object(
            'cards', '[]'::jsonb,
            'isExhausted', true,
            'itemsRemaining', 0
        );
    END IF;

    -- Clamp limit to remaining
    v_limit := LEAST(v_limit, v_daily_cap - v_seen_today);

    -- Build deck: public, non-banned users with content
    WITH candidate_users AS (
        SELECT
            u.id,
            u.username,
            u.display_name,
            u.profile_photo_url,
            u.bio,
            u.follower_count,
            u.following_count,
            u.total_likes,
            u.created_at AS user_created_at,
            u.last_post_at
        FROM users u
        WHERE u.id != v_uid
          AND u.visibility = 'public'
          AND u.is_banned = false
          -- Not already following
          AND NOT EXISTS (
              SELECT 1 FROM follows f
              WHERE f.follower_id = v_uid AND f.following_id = u.id
          )
          -- Not blocked in either direction
          AND NOT EXISTS (
              SELECT 1 FROM blocks b
              WHERE (b.blocker_id = v_uid AND b.blocked_id = u.id)
                 OR (b.blocker_id = u.id AND b.blocked_id = v_uid)
          )
          -- Not already seen today
          AND NOT EXISTS (
              SELECT 1 FROM shuffle_seen ss
              WHERE ss.user_id = v_uid
                AND ss.seen_user_id = u.id
                AND ss.seen_date = CURRENT_DATE
          )
        ORDER BY u.follower_count DESC, u.created_at DESC
        LIMIT v_limit
    ),
    -- Get signature posts (is_signature = true) for each user, max 1
    sig_posts AS (
        SELECT DISTINCT ON (p.user_id)
            p.user_id,
            jsonb_build_object(
                'id', p.id,
                'imageUrl', p.image_url,
                'imageWidth', p.image_width,
                'imageHeight', p.image_height,
                'likeCount', p.like_count,
                'createdAt', p.created_at,
                'tags', COALESCE(
                    (SELECT jsonb_agg(jsonb_build_object(
                        'id', t.id, 'label', t.label,
                        'externalUrl', t.external_url,
                        'positionX', t.position_x, 'positionY', t.position_y
                    )) FROM tags t WHERE t.post_id = p.id),
                    '[]'::jsonb
                )
            ) AS post_json
        FROM posts p
        WHERE p.user_id IN (SELECT id FROM candidate_users)
          AND p.is_signature = true
          AND p.is_hidden = false
        ORDER BY p.user_id, p.like_count DESC
    ),
    -- Count posts per candidate user
    post_counts AS (
        SELECT user_id, COUNT(*) AS post_count
        FROM posts
        WHERE user_id IN (SELECT id FROM candidate_users)
          AND is_hidden = false
        GROUP BY user_id
    ),
    -- Get up to 4 recent posts per user (non-signature, for mosaic)
    recent_posts AS (
        SELECT
            rp.user_id,
            jsonb_agg(rp.post_json ORDER BY rp.created_at DESC) AS posts_json
        FROM (
            SELECT
                p.user_id,
                p.created_at,
                jsonb_build_object(
                    'id', p.id,
                    'imageUrl', p.image_url,
                    'imageWidth', p.image_width,
                    'imageHeight', p.image_height,
                    'likeCount', p.like_count,
                    'createdAt', p.created_at,
                    'tags', '[]'::jsonb
                ) AS post_json
            FROM posts p
            WHERE p.user_id IN (SELECT id FROM candidate_users)
              AND p.is_hidden = false
              AND p.is_signature = false
            ORDER BY p.user_id, p.created_at DESC
        ) rp
        WHERE rp.user_id IN (
            SELECT user_id FROM (
                SELECT user_id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) rn
                FROM posts
                WHERE user_id IN (SELECT id FROM candidate_users)
                  AND is_hidden = false AND is_signature = false
            ) numbered WHERE rn <= 4
        )
        GROUP BY rp.user_id
    )
    SELECT jsonb_build_object(
        'cards', COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', cu.id,
                'username', cu.username,
                'displayName', cu.display_name,
                'profilePhotoUrl', cu.profile_photo_url,
                'bio', cu.bio,
                'followerCount', cu.follower_count,
                'followingCount', cu.following_count,
                'totalLikes', cu.total_likes,
                'postCount', COALESCE(pc.post_count, 0),
                'createdAt', cu.user_created_at,
                'lastPostAt', cu.last_post_at,
                'signaturePost', sp.post_json,
                'recentPosts', COALESCE(rp.posts_json, '[]'::jsonb)
            )
        ), '[]'::jsonb),
        'isExhausted', (v_seen_today + v_limit) >= v_daily_cap,
        'itemsRemaining', GREATEST(0, v_daily_cap - v_seen_today - v_limit)
    )
    INTO v_result
    FROM candidate_users cu
    LEFT JOIN sig_posts sp ON sp.user_id = cu.id
    LEFT JOIN recent_posts rp ON rp.user_id = cu.id
    LEFT JOIN post_counts pc ON pc.user_id = cu.id;

    RETURN COALESCE(v_result, jsonb_build_object(
        'cards', '[]'::jsonb,
        'isExhausted', false,
        'itemsRemaining', v_daily_cap - v_seen_today
    ));
END;
$$;

-- ============================================================================
-- record_shuffle_action: Record swipe + execute side effects
-- ============================================================================
CREATE OR REPLACE FUNCTION record_shuffle_action(
    p_target_user_id TEXT,
    p_action TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_target UUID := p_target_user_id::UUID;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_action NOT IN ('followed', 'skipped', 'saved') THEN
        RAISE EXCEPTION 'Invalid action: %', p_action;
    END IF;

    -- Record the seen action
    INSERT INTO shuffle_seen (user_id, seen_user_id, seen_date, action)
    VALUES (v_uid, v_target, CURRENT_DATE, p_action)
    ON CONFLICT (user_id, seen_user_id, seen_date) DO UPDATE
    SET action = EXCLUDED.action, created_at = now();

    -- Side effects
    IF p_action = 'followed' THEN
        INSERT INTO follows (follower_id, following_id)
        VALUES (v_uid, v_target)
        ON CONFLICT DO NOTHING;
    ELSIF p_action = 'saved' THEN
        INSERT INTO saved_users (user_id, saved_user_id)
        VALUES (v_uid, v_target)
        ON CONFLICT DO NOTHING;
    END IF;
END;
$$;

-- ============================================================================
-- get_saved_users: Return all saved users for the current user
-- ============================================================================
CREATE OR REPLACE FUNCTION get_saved_users(p_limit INT DEFAULT 50)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_result JSONB;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', u.id,
            'username', u.username,
            'displayName', u.display_name,
            'profilePhotoUrl', u.profile_photo_url,
            'followerCount', u.follower_count
        )
        ORDER BY su.created_at DESC
    ), '[]'::jsonb)
    INTO v_result
    FROM saved_users su
    JOIN users u ON u.id = su.saved_user_id
    WHERE su.user_id = v_uid
      AND u.is_banned = false
    LIMIT p_limit;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- unsave_user: Remove a saved user
-- ============================================================================
CREATE OR REPLACE FUNCTION unsave_user(p_target_user_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM saved_users
    WHERE user_id = auth.uid()
      AND saved_user_id = p_target_user_id::UUID;
END;
$$;
