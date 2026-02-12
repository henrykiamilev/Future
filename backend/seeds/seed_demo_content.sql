-- ============================================================
-- SEED SCRIPT — Demo Content for Curated
-- ============================================================
-- INSTRUCTIONS:
--   1. Upload images to your Supabase Storage → posts bucket → seed/ folder
--   2. Name the files EXACTLY as listed below (or update the URLs)
--   3. Upload profile photos to a profiles/ folder in posts bucket
--   4. Replace YOUR_PROJECT_REF below with your Supabase project ref
--   5. Paste this entire script into Supabase SQL Editor and run it
-- ============================================================

-- ========================
-- STEP 0: Set your project URL
-- ========================
-- Find your project ref at: Supabase Dashboard → Settings → General
-- It looks like: abcdefghijklmnop

\set base_url 'https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/public/posts'

-- NOTE: Since \set may not work in Supabase SQL Editor, we use a DO block instead:

DO $$
DECLARE
    base TEXT := 'https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/public/posts';

    -- User IDs (fixed so we can reference them)
    sofia_id   UUID := 'a1000000-0000-0000-0000-000000000001';
    ava_id     UUID := 'a1000000-0000-0000-0000-000000000002';
    mia_id     UUID := 'a1000000-0000-0000-0000-000000000003';
    ella_id    UUID := 'a1000000-0000-0000-0000-000000000004';
    ethan_id   UUID := 'a1000000-0000-0000-0000-000000000005';
    luca_id    UUID := 'a1000000-0000-0000-0000-000000000006';
    nolan_id   UUID := 'a1000000-0000-0000-0000-000000000007';
    kai_id     UUID := 'a1000000-0000-0000-0000-000000000008';

BEGIN

-- ========================
-- STEP 1: Disable triggers temporarily
-- ========================
-- (Bypasses 24-hour posting rule and auto-expiration so we can bulk insert)
ALTER TABLE posts DISABLE TRIGGER ALL;
ALTER TABLE users DISABLE TRIGGER ALL;
ALTER TABLE likes DISABLE TRIGGER ALL;
ALTER TABLE follows DISABLE TRIGGER ALL;

-- ========================
-- STEP 2: Insert demo users
-- ========================
-- IMAGE NAMING: Upload profile photos as  profiles/sofia.jpg, profiles/ava.jpg, etc.
-- IMAGE NAMING: Upload post images as     seed/sofia_1.jpg, seed/sofia_2.jpg, etc.

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

(ella_id,
 'ellabrooks',
 'Ella Brooks',
 base || '/profiles/ella.jpg',
 'golden hour chaser',
 'public', 'ellabrooks', 0, 0, 0,
 now() - interval '3 hours',
 now() - interval '11 days'),

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
 now() - interval '15 days'),

(kai_id,
 'kainakamura',
 'Kai Nakamura',
 base || '/profiles/kai.jpg',
 'design everything',
 'public', 'kainakamura', 0, 0, 0,
 now() - interval '8 hours',
 now() - interval '8 days');


-- ========================
-- STEP 3: Insert demo posts
-- ========================
-- Each user gets 2 posts. Posts expire in 3 days from created_at.
-- We set created_at to recent times so they show up as fresh in the feed.
--
-- IMAGE FILES TO UPLOAD (16 total):
--   seed/sofia_1.jpg   — e.g. Sofia at a coffee shop
--   seed/sofia_2.jpg   — e.g. Sofia in a clean outfit, street style
--   seed/ava_1.jpg     — e.g. Ava minimal look, neutral tones
--   seed/ava_2.jpg     — e.g. Ava reading at a café
--   seed/mia_1.jpg     — e.g. Mia elegant European vibe
--   seed/mia_2.jpg     — e.g. Mia trench coat or simple chic
--   seed/ella_1.jpg    — e.g. Ella golden hour, casual luxury
--   seed/ella_2.jpg    — e.g. Ella with car or outdoor setting
--   seed/ethan_1.jpg   — e.g. Ethan classic menswear, clean
--   seed/ethan_2.jpg   — e.g. Ethan coffee shop or workspace
--   seed/luca_1.jpg    — e.g. Luca Italian cafe or espresso moment
--   seed/luca_2.jpg    — e.g. Luca tailored casual fit
--   seed/nolan_1.jpg   — e.g. Nolan minimal streetwear
--   seed/nolan_2.jpg   — e.g. Nolan with car
--   seed/kai_1.jpg     — e.g. Kai clean modern fit
--   seed/kai_2.jpg     — e.g. Kai aesthetic architecture backdrop

INSERT INTO posts (id, user_id, image_url, image_width, image_height, image_size_bytes, like_count, view_count, is_signature, is_hidden, expires_at, created_at)
VALUES
-- Sofia's posts
(uuid_generate_v4(), sofia_id,
 base || '/seed/sofia_1.jpg',
 1080, 1350, 1048576, 0, 0, TRUE, FALSE,
 now() + interval '2 days 22 hours',
 now() - interval '2 hours'),

(uuid_generate_v4(), sofia_id,
 base || '/seed/sofia_2.jpg',
 1080, 1350, 983040, 0, 0, FALSE, FALSE,
 now() + interval '1 day 20 hours',
 now() - interval '28 hours'),

-- Ava's posts
(uuid_generate_v4(), ava_id,
 base || '/seed/ava_1.jpg',
 1080, 1350, 1150000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 20 hours',
 now() - interval '4 hours'),

(uuid_generate_v4(), ava_id,
 base || '/seed/ava_2.jpg',
 1080, 1080, 890000, 0, 0, FALSE, FALSE,
 now() + interval '1 day 12 hours',
 now() - interval '36 hours'),

-- Mia's posts
(uuid_generate_v4(), mia_id,
 base || '/seed/mia_1.jpg',
 1080, 1350, 1200000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 18 hours',
 now() - interval '6 hours'),

(uuid_generate_v4(), mia_id,
 base || '/seed/mia_2.jpg',
 1080, 1350, 1050000, 0, 0, FALSE, FALSE,
 now() + interval '1 day 6 hours',
 now() - interval '42 hours'),

-- Ella's posts
(uuid_generate_v4(), ella_id,
 base || '/seed/ella_1.jpg',
 1080, 1350, 1100000, 0, 0, FALSE, FALSE,
 now() + interval '2 days 21 hours',
 now() - interval '3 hours'),

(uuid_generate_v4(), ella_id,
 base || '/seed/ella_2.jpg',
 1080, 1080, 950000, 0, 0, TRUE, FALSE,
 now() + interval '1 day 18 hours',
 now() - interval '30 hours'),

-- Ethan's posts
(uuid_generate_v4(), ethan_id,
 base || '/seed/ethan_1.jpg',
 1080, 1350, 1180000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 19 hours',
 now() - interval '5 hours'),

(uuid_generate_v4(), ethan_id,
 base || '/seed/ethan_2.jpg',
 1080, 1350, 1020000, 0, 0, FALSE, FALSE,
 now() + interval '1 day 14 hours',
 now() - interval '34 hours'),

-- Luca's posts
(uuid_generate_v4(), luca_id,
 base || '/seed/luca_1.jpg',
 1080, 1350, 1090000, 0, 0, FALSE, FALSE,
 now() + interval '2 days 23 hours',
 now() - interval '1 hour'),

(uuid_generate_v4(), luca_id,
 base || '/seed/luca_2.jpg',
 1080, 1350, 970000, 0, 0, TRUE, FALSE,
 now() + interval '1 day 16 hours',
 now() - interval '32 hours'),

-- Nolan's posts
(uuid_generate_v4(), nolan_id,
 base || '/seed/nolan_1.jpg',
 1080, 1350, 1130000, 0, 0, TRUE, FALSE,
 now() + interval '2 days 17 hours',
 now() - interval '7 hours'),

(uuid_generate_v4(), nolan_id,
 base || '/seed/nolan_2.jpg',
 1080, 1080, 880000, 0, 0, FALSE, FALSE,
 now() + interval '1 day 10 hours',
 now() - interval '38 hours'),

-- Kai's posts
(uuid_generate_v4(), kai_id,
 base || '/seed/kai_1.jpg',
 1080, 1350, 1060000, 0, 0, FALSE, FALSE,
 now() + interval '2 days 16 hours',
 now() - interval '8 hours'),

(uuid_generate_v4(), kai_id,
 base || '/seed/kai_2.jpg',
 1080, 1350, 990000, 0, 0, TRUE, FALSE,
 now() + interval '1 day 8 hours',
 now() - interval '40 hours');


-- ========================
-- STEP 4: Cross-follows (everyone follows a few others)
-- ========================
-- Creates a realistic social graph — not everyone follows everyone

INSERT INTO follows (follower_id, following_id, is_approved)
VALUES
-- Sofia follows
(sofia_id, ava_id, TRUE),
(sofia_id, luca_id, TRUE),
(sofia_id, mia_id, TRUE),

-- Ava follows
(ava_id, sofia_id, TRUE),
(ava_id, kai_id, TRUE),
(ava_id, ella_id, TRUE),

-- Mia follows
(mia_id, sofia_id, TRUE),
(mia_id, luca_id, TRUE),
(mia_id, ethan_id, TRUE),
(mia_id, nolan_id, TRUE),

-- Ella follows
(ella_id, ava_id, TRUE),
(ella_id, mia_id, TRUE),
(ella_id, ethan_id, TRUE),

-- Ethan follows
(ethan_id, sofia_id, TRUE),
(ethan_id, mia_id, TRUE),
(ethan_id, nolan_id, TRUE),
(ethan_id, kai_id, TRUE),

-- Luca follows
(luca_id, sofia_id, TRUE),
(luca_id, ella_id, TRUE),
(luca_id, ethan_id, TRUE),

-- Nolan follows
(nolan_id, ethan_id, TRUE),
(nolan_id, luca_id, TRUE),
(nolan_id, kai_id, TRUE),
(nolan_id, ava_id, TRUE),

-- Kai follows
(kai_id, nolan_id, TRUE),
(kai_id, luca_id, TRUE),
(kai_id, mia_id, TRUE);


-- ========================
-- STEP 5: Cross-likes (some posts get liked)
-- ========================
-- We reference posts by user — grab the most recent post per user to like

INSERT INTO likes (user_id, post_id, created_at)
SELECT liker_id, p.id, now() - (random() * interval '12 hours')
FROM (
    VALUES
    -- Who likes whose post (liker → post author)
    (ava_id,   sofia_id),
    (mia_id,   sofia_id),
    (luca_id,  sofia_id),
    (ethan_id, sofia_id),
    (sofia_id, ava_id),
    (ella_id,  ava_id),
    (kai_id,   ava_id),
    (sofia_id, mia_id),
    (nolan_id, mia_id),
    (ethan_id, mia_id),
    (ava_id,   ella_id),
    (mia_id,   ella_id),
    (luca_id,  ella_id),
    (sofia_id, ethan_id),
    (mia_id,   ethan_id),
    (nolan_id, ethan_id),
    (kai_id,   ethan_id),
    (sofia_id, luca_id),
    (mia_id,   luca_id),
    (ella_id,  luca_id),
    (ethan_id, nolan_id),
    (luca_id,  nolan_id),
    (kai_id,   nolan_id),
    (ava_id,   kai_id),
    (nolan_id, kai_id),
    (ethan_id, kai_id)
) AS v(liker_id, author_id)
JOIN LATERAL (
    SELECT id FROM posts WHERE user_id = v.author_id ORDER BY created_at DESC LIMIT 1
) p ON TRUE;


-- ========================
-- STEP 6: Update denormalized counters
-- ========================
-- Since we bypassed triggers, manually sync all counters

-- Update post like counts
UPDATE posts SET like_count = (
    SELECT count(*) FROM likes WHERE likes.post_id = posts.id
);

-- Update user total likes
UPDATE users SET total_likes = (
    SELECT COALESCE(sum(p.like_count), 0)
    FROM posts p WHERE p.user_id = users.id
);

-- Update follower counts
UPDATE users SET follower_count = (
    SELECT count(*) FROM follows
    WHERE follows.following_id = users.id AND follows.is_approved = TRUE
);

-- Update following counts
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
-- STEP 8: Seed feed_scores so posts appear in the feed
-- ========================
INSERT INTO feed_scores (post_id, author_id, base_score, scored_at)
SELECT
    p.id,
    p.user_id,
    -- Simple score: newer + more likes = higher
    (0.30 * EXP(-0.05 * EXTRACT(EPOCH FROM (now() - p.created_at)) / 3600))
    + (0.20 * LEAST(p.like_count::float / 10.0, 1.0))
    + (0.15 * 0)  -- is_following is viewer-specific, set to 0 for base
    + (0.25 * 0.5), -- baseline velocity
    now()
FROM posts p
WHERE p.is_hidden = FALSE
ON CONFLICT (post_id) DO UPDATE SET
    base_score = EXCLUDED.base_score,
    scored_at = EXCLUDED.scored_at;

RAISE NOTICE 'Seed complete! Inserted 8 users, 16 posts, follows, and likes.';

END $$;
