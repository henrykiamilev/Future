-- ============================================================================
-- MIGRATION RUNNER — Execute in order
-- ============================================================================
-- Run this file against a Supabase PostgreSQL database.
-- Supabase provides: auth.uid(), pg_cron, Storage, Edge Functions.
-- ============================================================================

\echo '>>> 001: Core tables, indexes, constraints'
\i ../schema/001_core_tables.sql

\echo '>>> 002: Triggers & enforcement'
\i ../schema/002_triggers.sql

\echo '>>> 003: Row Level Security policies'
\i ../policies/003_rls_policies.sql

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
-- To verify cron jobs are registered:
-- SELECT * FROM cron.job;
-- ============================================================================
