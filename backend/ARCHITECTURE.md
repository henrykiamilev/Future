# Backend Architecture — Curated Identity Platform

## Overview

Production-ready PostgreSQL backend for a curated daily identity network. Designed for millions of users with server-side enforcement of all business rules.

## Directory Structure

```
backend/
├── schema/
│   ├── 001_core_tables.sql    — Tables, indexes, constraints, enums
│   └── 002_triggers.sql       — All triggers (24h rule, denorm, expiry, limits)
├── policies/
│   └── 003_rls_policies.sql   — Row Level Security for all tables
├── functions/
│   ├── 004_expiration.sql     — 3-day visibility, cleanup, archive
│   ├── 005_signature_system.sql — Add/remove/replace/query signatures
│   ├── 006_like_system.sql    — Like/unlike with uniqueness, batch check
│   ├── 007_feed_ranking.sql   — Main feed with scoring formula + exposure caps
│   ├── 008_friends_feed.sql   — Reverse-chrono friends feed
│   ├── 009_create_post.sql    — Post creation with full validation
│   └── 010_profile.sql       — Render-ready profile with sig + live posts
└── migrations/
    └── run_all.sql            — Ordered migration runner
```

## Scoring Formula (Main Feed)

```
score = 0.20 × normalized_likes
      + 0.25 × view_velocity
      + 0.45 × freshness_decay
      + 0.10 × personalization

Where:
  normalized_likes = ln(1 + like_count) / ln(1 + max_likes_in_batch)
  view_velocity    = recent_views_1h / max_velocity_in_batch
  freshness_decay  = e^(-0.05 × hours_since_creation)   // ~14h half-life
  personalization  = 1.0 if following author, else 0.0
```

Exposure cap: max 2 posts per author per viewer per day.

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Denormalized counters on users/posts | Avoid COUNT(*) on millions of rows |
| Composite PK on likes (user_id, post_id) | Uniqueness enforcement at DB level |
| Trigger-based 24h rule with FOR UPDATE | Prevents race conditions on concurrent posts |
| expires_at column (not computed) | Indexable, immutable, no runtime computation |
| post_view_hourly aggregates | View velocity without scanning raw view rows |
| Single-query profile function | Signature + live + stats in one round trip |
| Batch is_liked check | Pass array of post IDs, avoid N+1 |
| RLS with app.current_user_id setting | Works with Supabase, Lambda, or any middleware |

## Cursor Pagination

- **Friends Feed**: `created_at` cursor (reverse chronological)
- **Main Feed**: `(score, id)` composite cursor (score DESC, id DESC for tie-breaking)
- **Archive**: `created_at` cursor (reverse chronological)

## Server-Side Enforcement

All business rules are enforced at the database level:

1. **24-hour posting rule** — Trigger + function with row-level lock
2. **3-day visibility** — `expires_at` column checked in every query + RLS
3. **Like uniqueness** — Composite primary key constraint
4. **Max 3 tags** — Trigger on tags table
5. **Max 3 signatures** — Trigger on posts table
6. **Image size/dimension limits** — CHECK constraints + function validation
7. **Block enforcement** — Checked in feed queries + RLS
8. **Exposure caps** — Tracked in feed_exposures, filtered in ranking

## Deployment

### Supabase (MVP)
```sql
-- Run via Supabase SQL Editor or CLI:
-- Execute each file in order from run_all.sql
```

### AWS (Production)
```sql
-- Run against RDS PostgreSQL 15+:
psql -h your-rds-host -U your-user -d your-db -f migrations/run_all.sql
```

Set `app.current_user_id` in your API middleware:
```sql
SET LOCAL "app.current_user_id" = 'user-uuid-from-jwt';
```
