-- ============================================================================
-- CURATED PAGE — Personal identity page for each user
-- ============================================================================
-- A resume-inspired personal page with:
--   • 4 personality images (uploaded or from posts)
--   • 4 Q&A prompts (selected from a pool, with free-text answers)
-- Social handles (instagram, snapchat) are already on the users table.
-- ============================================================================

-- ── TABLE ───────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS curated_pages (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

    -- Personality images (up to 4 URLs)
    image_1         TEXT,
    image_2         TEXT,
    image_3         TEXT,
    image_4         TEXT,

    -- Q&A slots (question slug + free-text answer, up to 4)
    q1_prompt       TEXT,
    q1_answer       TEXT,
    q2_prompt       TEXT,
    q2_answer       TEXT,
    q3_prompt       TEXT,
    q3_answer       TEXT,
    q4_prompt       TEXT,
    q4_answer       TEXT,

    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE curated_pages ENABLE ROW LEVEL SECURITY;

-- Anyone can view curated pages
CREATE POLICY curated_pages_select ON curated_pages
    FOR SELECT USING (true);

-- Only the owner can update their own page
CREATE POLICY curated_pages_update ON curated_pages
    FOR UPDATE USING (user_id = auth_uid());

-- Only the owner can insert their own page
CREATE POLICY curated_pages_insert ON curated_pages
    FOR INSERT WITH CHECK (user_id = auth_uid());

-- ── GET CURATED PAGE ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_curated_page(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_photo_url TEXT,
    instagram_handle TEXT,
    snapchat_handle TEXT,
    image_1 TEXT,
    image_2 TEXT,
    image_3 TEXT,
    image_4 TEXT,
    q1_prompt TEXT,
    q1_answer TEXT,
    q2_prompt TEXT,
    q2_answer TEXT,
    q3_prompt TEXT,
    q3_answer TEXT,
    q4_prompt TEXT,
    q4_answer TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.display_name,
        u.profile_photo_url,
        u.instagram_handle,
        u.snapchat_handle,
        cp.image_1,
        cp.image_2,
        cp.image_3,
        cp.image_4,
        cp.q1_prompt,
        cp.q1_answer,
        cp.q2_prompt,
        cp.q2_answer,
        cp.q3_prompt,
        cp.q3_answer,
        cp.q4_prompt,
        cp.q4_answer
    FROM users u
    LEFT JOIN curated_pages cp ON cp.user_id = u.id
    WHERE u.id = p_user_id
      AND u.is_banned = FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp;

-- ── UPSERT CURATED PAGE ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION upsert_curated_page(
    p_image_1 TEXT DEFAULT NULL,
    p_image_2 TEXT DEFAULT NULL,
    p_image_3 TEXT DEFAULT NULL,
    p_image_4 TEXT DEFAULT NULL,
    p_q1_prompt TEXT DEFAULT NULL,
    p_q1_answer TEXT DEFAULT NULL,
    p_q2_prompt TEXT DEFAULT NULL,
    p_q2_answer TEXT DEFAULT NULL,
    p_q3_prompt TEXT DEFAULT NULL,
    p_q3_answer TEXT DEFAULT NULL,
    p_q4_prompt TEXT DEFAULT NULL,
    p_q4_answer TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID := auth_uid();
BEGIN
    INSERT INTO curated_pages (
        user_id,
        image_1, image_2, image_3, image_4,
        q1_prompt, q1_answer,
        q2_prompt, q2_answer,
        q3_prompt, q3_answer,
        q4_prompt, q4_answer,
        updated_at
    ) VALUES (
        v_user_id,
        p_image_1, p_image_2, p_image_3, p_image_4,
        p_q1_prompt, p_q1_answer,
        p_q2_prompt, p_q2_answer,
        p_q3_prompt, p_q3_answer,
        p_q4_prompt, p_q4_answer,
        now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        image_1 = EXCLUDED.image_1,
        image_2 = EXCLUDED.image_2,
        image_3 = EXCLUDED.image_3,
        image_4 = EXCLUDED.image_4,
        q1_prompt = EXCLUDED.q1_prompt,
        q1_answer = EXCLUDED.q1_answer,
        q2_prompt = EXCLUDED.q2_prompt,
        q2_answer = EXCLUDED.q2_answer,
        q3_prompt = EXCLUDED.q3_prompt,
        q3_answer = EXCLUDED.q3_answer,
        q4_prompt = EXCLUDED.q4_prompt,
        q4_answer = EXCLUDED.q4_answer,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
