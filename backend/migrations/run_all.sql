-- ============================================================================
-- MIGRATION RUNNER — Execute in order
-- ============================================================================
-- Run this file against a Supabase PostgreSQL database.
-- Supabase provides: auth.uid(), pg_cron, Storage, Edge Functions.
--
-- DEPENDENCY ORDER:
--   schema → policies → core functions → tables (feed_v2) → functions that
--   depend on those tables (015_discover, 016_relationship, 017_record)
--   → security migrations → trigger RLS fix
-- ============================================================================

-- ── SCHEMA ───────────────────────────────────────────────────────────────────

\echo '>>> 001: Core tables, indexes, constraints'
\i ../schema/001_core_tables.sql

\echo '>>> 002: Triggers & enforcement'
\i ../schema/002_triggers.sql

\echo '>>> 003: Comments & search schema'
\i ../schema/003_comments_and_search.sql

\echo '>>> 004: Auth trigger (handle_new_user)'
\i ../schema/004_auth_trigger.sql

-- ── POLICIES ─────────────────────────────────────────────────────────────────

\echo '>>> 003p: Row Level Security policies'
\i ../policies/003_rls_policies.sql

-- ── CORE FUNCTIONS (no cross-dependencies) ──────────────────────────────────

\echo '>>> 004: Expiration logic'
\i ../functions/004_expiration.sql

\echo '>>> 005: Signature system'
\i ../functions/005_signature_system.sql

\echo '>>> 006: Like system'
\i ../functions/006_like_system.sql

\echo '>>> 007: Feed ranking (Main) + record_post_view + refresh_feed_scores'
\i ../functions/007_feed_ranking.sql

\echo '>>> 008: Friends feed'
\i ../functions/008_friends_feed.sql

\echo '>>> 009: Post creation'
\i ../functions/009_create_post.sql

\echo '>>> 010: Profile queries'
\i ../functions/010_profile.sql

\echo '>>> 011: Search users'
\i ../functions/011_search_users.sql

\echo '>>> 012: Comments'
\i ../functions/012_comments.sql

\echo '>>> 013: Followers list'
\i ../functions/013_followers_list.sql

\echo '>>> 014: Delete account'
\i ../functions/014_delete_account.sql

-- ── FEED V2 TABLES (must come BEFORE 015/016 which reference these tables) ──

\echo '>>> 017: Feed v2 migration (tables + RLS for relationship_strength, daily_feed_state)'
\i ../migrations/017_feed_v2.sql

-- ── FUNCTIONS THAT DEPEND ON FEED V2 TABLES ─────────────────────────────────

\echo '>>> 015: Discover (depends on feed_scores from 007)'
\i ../functions/015_discover.sql

\echo '>>> 016: Relationship strength (depends on relationship_strength from 017)'
\i ../functions/016_relationship_strength.sql

\echo '>>> 017b: Record consumption (depends on daily_feed_state from 017)'
\i ../functions/017_record_consumption.sql

-- ── SECURITY & STORAGE MIGRATIONS ───────────────────────────────────────────

\echo '>>> 016m: Security hardening'
\i ../migrations/016_security_hardening.sql

\echo '>>> 018: Private storage policies'
\i ../migrations/018_private_storage.sql

\echo '>>> 019: Fix trigger RLS (SECURITY DEFINER + recount)'
\i ../migrations/019_fix_trigger_rls.sql

\echo '>>> 020: Report content RPC'
\i ../functions/020_report_content.sql

\echo '>>> 021: Notifications (table, triggers, RPCs)'
\i ../functions/021_notifications.sql

\echo '>>> 022: Reactions (emoji reactions on posts)'
\i ../functions/022_reactions.sql

\echo '>>> 023: Profile themes (user-selectable color themes)'
\i ../functions/023_profile_themes.sql

\echo '>>> All migrations complete.'

-- ============================================================================
-- pg_cron SCHEDULES (Supabase has pg_cron built-in on paid plans)
-- ============================================================================
-- Run these manually in the Supabase SQL editor after migration:
--
-- Refresh feed scores every 5 minutes:
-- SELECT cron.schedule('refresh-feed-scores', '*/5 * * * *', 'SELECT refresh_feed_scores()');
--
-- Cleanup expired data every 4 hours:
-- SELECT cron.schedule('cleanup-expired', '0 */4 * * *', 'SELECT cleanup_expired_data()');
--
-- Compute relationship strengths every 15 minutes:
-- SELECT cron.schedule('compute-relationship-strengths', '*/15 * * * *',
--     'SELECT compute_relationship_strengths()');
--
-- Cleanup old daily feed state daily at 3 AM:
-- SELECT cron.schedule('cleanup-daily-feed-state', '0 3 * * *',
--     'SELECT cleanup_daily_feed_state()');
--
-- To verify cron jobs are registered:
-- SELECT * FROM cron.job;
-- ============================================================================
