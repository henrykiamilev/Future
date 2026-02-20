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

\echo '>>> 015: Discover'
\i ../functions/015_discover.sql

\echo '>>> 016: Relationship strength'
\i ../functions/016_relationship_strength.sql

\echo '>>> 017: Feed v2 migration (tables + RLS)'
\i ../migrations/017_feed_v2.sql

\echo '>>> 017b: Record consumption'
\i ../functions/017_record_consumption.sql

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
