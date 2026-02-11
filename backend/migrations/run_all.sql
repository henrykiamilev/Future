-- ============================================================================
-- MIGRATION RUNNER — Execute in order
-- ============================================================================
-- Run this file against a fresh PostgreSQL 15+ database.
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

\echo '>>> 007: Feed ranking (Main)'
\i ../functions/007_feed_ranking.sql

\echo '>>> 008: Friends feed'
\i ../functions/008_friends_feed.sql

\echo '>>> 009: Post creation'
\i ../functions/009_create_post.sql

\echo '>>> 010: Profile queries'
\i ../functions/010_profile.sql

\echo '>>> All migrations complete.'
