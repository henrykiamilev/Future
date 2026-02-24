-- ============================================================================
-- MIGRATION 026: Add caption and location to posts
-- ============================================================================
-- Adds per-post caption (short tagline) and location (city/state) columns.
-- Both are optional — existing posts will have NULL values.
-- ============================================================================

-- Caption: short saying/tagline per post (max 100 characters)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS caption TEXT;
ALTER TABLE posts DROP CONSTRAINT IF EXISTS chk_caption;
ALTER TABLE posts ADD CONSTRAINT chk_caption
    CHECK (caption IS NULL OR char_length(caption) <= 100);

-- Location: city/state text (max 200 characters)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS location TEXT;
ALTER TABLE posts DROP CONSTRAINT IF EXISTS chk_location;
ALTER TABLE posts ADD CONSTRAINT chk_location
    CHECK (location IS NULL OR char_length(location) <= 200);
