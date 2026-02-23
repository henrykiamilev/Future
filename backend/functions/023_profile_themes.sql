-- ============================================================================
-- PROFILE THEMES — User-selectable profile color themes
-- ============================================================================
-- Adds a theme column to users. Themes are identified by slug.
-- The client maps slugs to color palettes locally.
-- ============================================================================

-- Add theme column (default is the standard app theme)
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_theme TEXT NOT NULL DEFAULT 'default'
    CONSTRAINT chk_profile_theme CHECK (profile_theme IN (
        'default', 'midnight', 'ocean', 'sunset', 'forest', 'lavender', 'slate'
    ));
