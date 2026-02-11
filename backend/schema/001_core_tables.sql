-- ============================================================================
-- CURATED IDENTITY PLATFORM — CORE SCHEMA
-- PostgreSQL 15+
-- ============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE account_visibility AS ENUM ('public', 'private');
CREATE TYPE report_target_type AS ENUM ('post', 'user');
CREATE TYPE report_status AS ENUM ('pending', 'reviewed', 'actioned', 'dismissed');

-- ============================================================================
-- USERS
-- ============================================================================

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username        TEXT NOT NULL,
    display_name    TEXT,
    profile_photo_url TEXT,
    bio             TEXT,
    visibility      account_visibility NOT NULL DEFAULT 'public',
    instagram_handle TEXT,
    snapchat_handle  TEXT,
    total_likes     BIGINT NOT NULL DEFAULT 0,       -- denormalized lifetime counter
    follower_count  BIGINT NOT NULL DEFAULT 0,       -- denormalized
    following_count BIGINT NOT NULL DEFAULT 0,       -- denormalized
    last_post_at    TIMESTAMPTZ,                     -- for 24-hour rule enforcement
    is_banned       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_users_username ON users (lower(username));
CREATE INDEX idx_users_visibility ON users (visibility) WHERE visibility = 'public';
CREATE INDEX idx_users_created_at ON users (created_at);

-- ============================================================================
-- POSTS
-- ============================================================================

CREATE TABLE posts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    image_url       TEXT NOT NULL,
    image_width     INT NOT NULL,
    image_height    INT NOT NULL,
    image_size_bytes INT NOT NULL,
    like_count      BIGINT NOT NULL DEFAULT 0,       -- denormalized
    view_count      BIGINT NOT NULL DEFAULT 0,       -- denormalized
    is_signature    BOOLEAN NOT NULL DEFAULT FALSE,
    is_hidden       BOOLEAN NOT NULL DEFAULT FALSE,   -- moderation auto-hide
    expires_at      TIMESTAMPTZ NOT NULL,             -- created_at + 3 days
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_image_size CHECK (image_size_bytes <= 2621440),  -- 2.5MB hard cap
    CONSTRAINT chk_image_dimensions CHECK (
        image_width <= 2048 AND image_height <= 2048
    )
);

-- Feed queries: active posts by creation time
CREATE INDEX idx_posts_active_feed ON posts (created_at DESC)
    WHERE is_hidden = FALSE AND expires_at > now();

-- User's posts (profile, archive)
CREATE INDEX idx_posts_user_id_created ON posts (user_id, created_at DESC);

-- Signature lookup
CREATE INDEX idx_posts_user_signature ON posts (user_id)
    WHERE is_signature = TRUE;

-- Expiration processing
CREATE INDEX idx_posts_expires_at ON posts (expires_at)
    WHERE is_hidden = FALSE;

-- Ranking support
CREATE INDEX idx_posts_ranking ON posts (created_at DESC, like_count DESC, view_count DESC)
    WHERE is_hidden = FALSE AND expires_at > now();

-- ============================================================================
-- TAGS
-- ============================================================================

CREATE TABLE tags (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id         UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    label           TEXT NOT NULL,
    external_url    TEXT,                              -- optional clickable link
    position_x      REAL,                             -- optional tag position on image
    position_y      REAL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tags_post_id ON tags (post_id);

-- Enforce max 3 tags per post via trigger (below)

-- ============================================================================
-- LIKES
-- ============================================================================

CREATE TABLE likes (
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, post_id)
);

CREATE INDEX idx_likes_post_id ON likes (post_id);
CREATE INDEX idx_likes_user_id ON likes (user_id, created_at DESC);

-- ============================================================================
-- FOLLOWS
-- ============================================================================

CREATE TABLE follows (
    follower_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_approved     BOOLEAN NOT NULL DEFAULT TRUE,     -- FALSE for pending private account requests
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (follower_id, following_id),
    CONSTRAINT chk_no_self_follow CHECK (follower_id != following_id)
);

CREATE INDEX idx_follows_following ON follows (following_id, is_approved);
CREATE INDEX idx_follows_follower ON follows (follower_id, is_approved);

-- ============================================================================
-- FOLLOW REQUESTS (for private accounts)
-- ============================================================================
-- Handled via is_approved = FALSE on the follows table.
-- When accepted, flip is_approved to TRUE.
-- When rejected, delete the row.

-- ============================================================================
-- POST VIEWS (for view velocity tracking)
-- ============================================================================

CREATE TABLE post_views (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    viewer_id   UUID REFERENCES users(id) ON DELETE SET NULL,  -- nullable for anonymous
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_post_views_post_created ON post_views (post_id, created_at DESC);

-- Partitioning hint: partition by created_at monthly at scale

-- ============================================================================
-- POST VIEW HOURLY AGGREGATES (for view velocity without scanning raw views)
-- ============================================================================

CREATE TABLE post_view_hourly (
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    hour_bucket TIMESTAMPTZ NOT NULL,                 -- truncated to hour
    view_count  INT NOT NULL DEFAULT 0,

    PRIMARY KEY (post_id, hour_bucket)
);

-- ============================================================================
-- REPORTS
-- ============================================================================

CREATE TABLE reports (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type     report_target_type NOT NULL,
    target_id       UUID NOT NULL,                     -- post_id or user_id
    reason          TEXT NOT NULL,
    status          report_status NOT NULL DEFAULT 'pending',
    admin_notes     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at     TIMESTAMPTZ
);

CREATE INDEX idx_reports_status ON reports (status, created_at DESC);
CREATE INDEX idx_reports_target ON reports (target_type, target_id);

-- ============================================================================
-- BLOCKED USERS
-- ============================================================================

CREATE TABLE blocks (
    blocker_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT chk_no_self_block CHECK (blocker_id != blocked_id)
);

CREATE INDEX idx_blocks_blocked ON blocks (blocked_id);

-- ============================================================================
-- FEED EXPOSURE TRACKING (per-author caps in Main feed)
-- ============================================================================

CREATE TABLE feed_exposures (
    viewer_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    author_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    feed_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    exposure_count INT NOT NULL DEFAULT 1,

    PRIMARY KEY (viewer_id, author_id, feed_date)
);
