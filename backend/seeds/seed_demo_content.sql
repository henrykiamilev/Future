-- ============================================================
-- SEED SCRIPT — Demo Content for Curated
-- ============================================================
-- INSTRUCTIONS:
--   1. Upload post images to Storage → posts bucket → seed/ folder
--   2. Upload profile photos to Storage → posts bucket → profiles/ folder
--   3. Name the files EXACTLY as listed below (or update the URLs)
--   4. Replace YOUR_PROJECT_REF below with your Supabase project ref
--   5. Paste this entire script into Supabase SQL Editor and run it
-- ============================================================

DO $$
DECLARE
    base TEXT := 'https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/public/posts';

    -- User IDs (fixed so we can reference them)
    sofia_id   UUID := 'a1000000-0000-0000-0000-000000000001';
    ava_id     UUID := 'a1000000-0000-0000-0000-000000000002';
    mia_id     UUID := 'a1000000-0000-0000-0000-000000000003';
    ethan_id   UUID := 'a1000000-0000-0000-0000-000000000005';
    luca_id    UUID := 'a1000000-0000-0000-0000-000000000006';
    nolan_id   UUID := 'a1000000-0000-0000-0000-000000000007';

BEGIN

-- ========================
-- STEP 1: Disable triggers temporarily
-- ========================
ALTER TABLE posts DISABLE TRIGGER ALL;
ALTER TABLE users DISABLE TRIGGER ALL;
ALTER TABLE likes DISABLE TRIGGER ALL;
ALTER TABLE follows DISABLE TRIGGER ALL;

-- ========================
-- STEP 2: Insert 6 demo users
-- ========================
-- PROFILE PHOTOS TO UPLOAD (6 files → profiles/ folder):
--   profiles/sofia.jpg
--   profiles/ava.jpg
--   profiles/mia.jpg
--   profiles/ethan.jpg
--   profiles/luca.jpg
--   profiles/nolan.jpg

INSERT INTO users (id, username, display_name, profile_photo_url, bio, visibility, instagram_handle, follower_count, following_count, total_likes, last_post_at, created_at)
VALUES
-- ── FEMALE ACCOUNTS ──
(sofia_id,
 'sofiareyes',
 'Sofia Reyes',
 base || '/profiles/sofia.jpg',
 'less is more',
 'public', 'sofiareyes', 0, 0, 0,
 now() - interval '2 hours',
 now() - interval '14 days'),

(ava_id,
 'avachen',
 'Ava Chen',
 base || '/profiles/ava.jpg',
 'coffee and clean lines',
 'public', 'avachen', 0, 0, 0,
 now() - interval '4 hours',
 now() - interval '12 days'),

(mia_id,
 'mialaurent',
 'Mia Laurent',
 base || '/profiles/mia.jpg',
 'somewhere between here and paris',
 'public', 'mialaurent', 0, 0, 0,
 now() - interval '6 hours',
 now() - interval '10 days'),

-- ── MALE ACCOUNTS ──
(ethan_id,
 'ethanmercer',
 'Ethan Mercer',
 base || '/profiles/ethan.jpg',
 'details matter',
 'public', 'ethanmercer', 0, 0, 0,
 now() - interval '5 hours',
 now() - interval '13 days'),

(luca_id,
 'lucamoretti',
 'Luca Moretti',
 base || '/profiles/luca.jpg',
 'espresso before everything',
 'public', 'lucamoretti', 0, 0, 0,
 now() - interval '1 hour',
 now() - interval '9 days'),

(nolan_id,
 'nolanhayes',
 'Nolan Hayes',
 base || '/profiles/nolan.jpg',
 'keep it simple',
 'public', 'nolanhayes', 0, 0, 0,
 now() - interval '7 hours',
 now() - interval '15 days');


-- ========================
-- STEP 3: Insert 6 demo posts (1 per user)
-- ========================
-- POST IMAGES TO UPLOAD (6 files → seed/ folder):
--   seed/sofia_1.jpg   — e.g. coffee shop, clean outfit
--   seed/ava_1.jpg     — e.g. minimal look, neutral tones
--   seed/mia_1.jpg     — e.g. elegant European vibe
--   seed/ethan_1.jpg   — e.g. classic menswear, clean
--   seed/luca_1.jpg    — e.g. Italian cafe or tailored casual
--   seed/nolan_1.jpg   — e.g. minimal streetwear or with car

INSERT INTO posts (id, user_id, image_url, image_width, image_height, image_size_bytes, like_count, view_count, is_signature, is_hidden, expires_at, created_at)
VALUES
(uuid_generate_v4(), sofia_id,
 base || '/seed/sofia_1.jpg',
 1080, 1350, 1048576, 0, 0, TRUE, FALSE,
 now() + interval '2 days 22 hours',
 now() - interval '2 hours'),

(uuid_generate_v4(), ava_id,
 base || '/seed/ava_1.jpg',
 1080, 1350, 1150000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 20 hours',
 now() - interval '4 hours'),

(uuid_generate_v4(), mia_id,
 base || '/seed/mia_1.jpg',
 1080, 1350, 1200000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 18 hours',
 now() - interval '6 hours'),

(uuid_generate_v4(), ethan_id,
 base || '/seed/ethan_1.jpg',
 1080, 1350, 1180000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 19 hours',
 now() - interval '5 hours'),

(uuid_generate_v4(), luca_id,
 base || '/seed/luca_1.jpg',
 1080, 1350, 1090000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 23 hours',
 now() - interval '1 hour'),

(uuid_generate_v4(), nolan_id,
 base || '/seed/nolan_1.jpg',
 1080, 1350, 1130000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 17 hours',
 now() - interval '7 hours');


-- ========================
-- STEP 4: Cross-follows
-- ========================
INSERT INTO follows (follower_id, following_id, is_approved)
VALUES
-- Sofia follows
(sofia_id, ava_id, TRUE),
(sofia_id, luca_id, TRUE),
(sofia_id, mia_id, TRUE),

-- Ava follows
(ava_id, sofia_id, TRUE),
(ava_id, ethan_id, TRUE),

-- Mia follows
(mia_id, sofia_id, TRUE),
(mia_id, luca_id, TRUE),
(mia_id, ethan_id, TRUE),

-- Ethan follows
(ethan_id, sofia_id, TRUE),
(ethan_id, mia_id, TRUE),
(ethan_id, nolan_id, TRUE),

-- Luca follows
(luca_id, sofia_id, TRUE),
(luca_id, ethan_id, TRUE),
(luca_id, nolan_id, TRUE),

-- Nolan follows
(nolan_id, ethan_id, TRUE),
(nolan_id, luca_id, TRUE),
(nolan_id, ava_id, TRUE);


-- ========================
-- STEP 5: Cross-likes
-- ========================
INSERT INTO likes (user_id, post_id, created_at)
SELECT liker_id, p.id, now() - (random() * interval '12 hours')
FROM (
    VALUES
    (ava_id,   sofia_id),
    (mia_id,   sofia_id),
    (luca_id,  sofia_id),
    (ethan_id, sofia_id),
    (sofia_id, ava_id),
    (mia_id,   ava_id),
    (nolan_id, ava_id),
    (sofia_id, mia_id),
    (nolan_id, mia_id),
    (ethan_id, mia_id),
    (sofia_id, ethan_id),
    (mia_id,   ethan_id),
    (nolan_id, ethan_id),
    (sofia_id, luca_id),
    (mia_id,   luca_id),
    (ethan_id, luca_id),
    (ethan_id, nolan_id),
    (luca_id,  nolan_id),
    (ava_id,   nolan_id)
) AS v(liker_id, author_id)
JOIN LATERAL (
    SELECT id FROM posts WHERE user_id = v.author_id ORDER BY created_at DESC LIMIT 1
) p ON TRUE;


-- ========================
-- STEP 6: Update denormalized counters
-- ========================
UPDATE posts SET like_count = (
    SELECT count(*) FROM likes WHERE likes.post_id = posts.id
);

UPDATE users SET total_likes = (
    SELECT COALESCE(sum(p.like_count), 0)
    FROM posts p WHERE p.user_id = users.id
);

UPDATE users SET follower_count = (
    SELECT count(*) FROM follows
    WHERE follows.following_id = users.id AND follows.is_approved = TRUE
);

UPDATE users SET following_count = (
    SELECT count(*) FROM follows
    WHERE follows.follower_id = users.id AND follows.is_approved = TRUE
);


-- ========================
-- STEP 7: Re-enable triggers
-- ========================
ALTER TABLE posts ENABLE TRIGGER ALL;
ALTER TABLE users ENABLE TRIGGER ALL;
ALTER TABLE likes ENABLE TRIGGER ALL;
ALTER TABLE follows ENABLE TRIGGER ALL;


-- ========================
-- STEP 8: Seed feed_scores
-- ========================
INSERT INTO feed_scores (post_id, author_id, base_score, scored_at)
SELECT
    p.id,
    p.user_id,
    (0.30 * EXP(-0.05 * EXTRACT(EPOCH FROM (now() - p.created_at)) / 3600))
    + (0.20 * LEAST(p.like_count::float / 10.0, 1.0))
    + (0.15 * 0)
    + (0.25 * 0.5),
    now()
FROM posts p
WHERE p.is_hidden = FALSE
ON CONFLICT (post_id) DO UPDATE SET
    base_score = EXCLUDED.base_score,
    scored_at = EXCLUDED.scored_at;

RAISE NOTICE 'Seed complete! Inserted 6 users, 6 posts, 18 follows, and 19 likes.';

END $$;
