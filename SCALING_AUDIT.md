# Production Scaling Audit — 1M DAU Target

**Assessment: NOT production-ready.** Functional architecture with serious bottlenecks that will fail under load. This document identifies every issue, in order of severity.

---

## 1. DATABASE BOTTLENECKS

### 1.1 — `get_main_feed()` scans the entire active post pool

**Severity: CRITICAL**

The `candidate_posts` CTE has no row limit. With 1M DAU posting once/day, the 3-day window contains ~3M active posts. Every feed request materializes all ~3M rows before scoring 20.

```sql
-- Current: scans ALL active posts, then scores, then limits
WITH candidate_posts AS (
    SELECT ... FROM posts p JOIN users u ON u.id = p.user_id
    WHERE p.is_hidden = FALSE AND p.expires_at > now() ...
)
-- This CTE materializes ~3M rows before any filtering
```

**Impact:** At 1M DAU × ~10 feed loads/day = 10M feed queries/day. Each scanning 3M rows. This is ~30 trillion row-reads/day on the posts table alone.

**Fix:** Pre-compute scores in a materialized view or background job. The feed function should read from a pre-ranked table, not score on every request.

```sql
-- Proposed: background worker scores every 60 seconds
CREATE TABLE feed_scored (
    post_id UUID PRIMARY KEY,
    base_score DOUBLE PRECISION,    -- likes + velocity + freshness (no personalization)
    author_id UUID,
    expires_at TIMESTAMPTZ,
    scored_at TIMESTAMPTZ
);
CREATE INDEX idx_feed_scored ON feed_scored (base_score DESC) WHERE expires_at > now();

-- Feed query becomes a simple index scan + 0.10 personalization overlay
```

### 1.2 — Velocity subquery is correlated and runs per-row

**Severity: CRITICAL**

The `batch_stats` CTE runs a correlated subquery on `post_view_hourly` for every candidate post to find `max_velocity`. Then the `scored` CTE runs the same subquery again for every row.

```sql
-- This runs TWICE per candidate post (once in batch_stats, once in scored)
COALESCE((
    SELECT SUM(pvh.view_count)
    FROM post_view_hourly pvh
    WHERE pvh.post_id = cp.post_id
      AND pvh.hour_bucket >= date_trunc('hour', now()) - INTERVAL '1 hour'
), 0)
```

**Impact:** 3M candidates × 2 subqueries = 6M index lookups on `post_view_hourly` per feed request.

**Fix:** Single `LEFT JOIN LATERAL` or pre-join in the candidate CTE:

```sql
WITH velocity AS (
    SELECT post_id, SUM(view_count) AS views_1h
    FROM post_view_hourly
    WHERE hour_bucket >= date_trunc('hour', now()) - INTERVAL '1 hour'
    GROUP BY post_id
)
-- Then JOIN velocity v ON v.post_id = cp.post_id
```

### 1.3 — `post_views` table grows unbounded

**Severity: HIGH**

Every feed impression inserts a row into `post_views`. At 1M DAU × 100 posts viewed/day = 100M rows/day. That's 3B rows/month.

The cleanup function only runs daily and deletes rows >7 days old — so the table will peak at ~700M rows before cleanup.

**Fix:**
- Drop `post_views` entirely. It's redundant with `post_view_hourly`.
- Increment `post_view_hourly` directly from the API layer, not via trigger on a raw events table.
- If raw events are needed for analytics, write to a separate analytics store (Kinesis → S3 → Athena), not Postgres.

### 1.4 — Like/follow/view triggers update multiple rows synchronously

**Severity: HIGH**

Every like triggers two synchronous UPDATEs (posts.like_count + users.total_likes). Every follow triggers two UPDATEs (follower.following_count + following.follower_count). Every view triggers an UPDATE + UPSERT.

At 1M DAU with heavy engagement, these triggers create write amplification and row-lock contention on hot user rows.

**Fix:** Batch counter updates via a background worker:

```sql
-- Instead of trigger-based immediate updates:
-- 1. INSERT into a "counter_events" queue table (append-only, no locks)
-- 2. Background worker aggregates every 5 seconds:
UPDATE posts SET like_count = like_count + delta WHERE id = ?;
```

### 1.5 — `idx_posts_active_feed` partial index is useless

**Severity: MEDIUM**

```sql
CREATE INDEX idx_posts_active_feed ON posts (created_at DESC)
    WHERE is_hidden = FALSE AND expires_at > now();
```

`expires_at > now()` is not a compile-time constant. Postgres cannot use this partial index condition at plan time. The index includes ALL non-hidden posts regardless of expiration. The `FEED_RANKING_REFERENCE.sql` acknowledges this problem and proposes a covering index, but it's only in a comment — not actually deployed.

**Fix:** Use a plain partial index on `is_hidden = FALSE` (static), and filter `expires_at > now()` as a recheck:

```sql
CREATE INDEX idx_posts_active ON posts (created_at DESC)
    INCLUDE (user_id, expires_at, like_count, view_count, image_url, image_width, image_height)
    WHERE is_hidden = FALSE;
```

### 1.6 — `FOR UPDATE` lock on users table during post creation

**Severity: MEDIUM**

The 24-hour rule trigger acquires `FOR UPDATE` on the user row:

```sql
SELECT last_post_at INTO v_last_post_at FROM users WHERE id = NEW.user_id FOR UPDATE;
```

This locks the user row for the entire transaction. If the image validation or tag insertion is slow, other operations on this user (profile loads, follow counts) will block.

**Fix:** Use an advisory lock instead of a row lock:

```sql
PERFORM pg_advisory_xact_lock(hashtext(NEW.user_id::TEXT));
```

---

## 2. INDEX IMPROVEMENTS REQUIRED

| Index | Current | Problem | Recommended |
|---|---|---|---|
| `idx_posts_active_feed` | `(created_at DESC) WHERE is_hidden=FALSE AND expires_at > now()` | `now()` is not static; Postgres can't use it | `(created_at DESC) INCLUDE (user_id, expires_at, like_count, view_count) WHERE is_hidden = FALSE` |
| `idx_posts_ranking` | `(created_at DESC, like_count DESC, view_count DESC)` | Not actually used by ranking query (CTE-based scoring) | Drop. Use the pre-scored materialized view instead |
| Missing | — | No index for exposure cap lookups in bulk | `CREATE INDEX idx_feed_exposures_viewer_date ON feed_exposures (viewer_id, feed_date) INCLUDE (author_id, exposure_count)` |
| Missing | — | Friends feed needs follow→post join | `CREATE INDEX idx_posts_user_active ON posts (user_id, created_at DESC) WHERE is_hidden = FALSE AND expires_at > now()` (same `now()` issue — use static partial) |
| `blocks` | PK `(blocker_id, blocked_id)` + `idx_blocks_blocked(blocked_id)` | Feed queries check both directions with OR, forcing BitmapOr | Add `CREATE INDEX idx_blocks_reverse ON blocks (blocked_id, blocker_id)` for direct lookup in both directions |
| `post_view_hourly` | PK `(post_id, hour_bucket)` | Only 2 rows per post per lookup — fine for point queries but not for batch aggregation across 3M posts | Pre-aggregate into `feed_scored` table |

---

## 3. QUERY OPTIMIZATION OPPORTUNITIES

### 3.1 — Profile query does 6 correlated subqueries

`get_user_profile()` builds signature_posts and live_posts as JSONB via nested subqueries with inner tag aggregations. Each section runs a correlated subquery per post for tags.

**Fix:** Use a single `LEFT JOIN` with `jsonb_agg` and `GROUP BY`, or fetch posts and tags in two parallel queries from the API layer.

### 3.2 — `check_liked_posts()` uses `EXISTS` per element

```sql
SELECT pid, EXISTS (SELECT 1 FROM likes l WHERE l.post_id = pid AND l.user_id = auth_uid())
FROM unnest(p_post_ids) AS pid;
```

For 20 posts, this runs 20 separate `EXISTS` subqueries. At scale, use a single `LEFT JOIN`:

```sql
SELECT pid, (l.user_id IS NOT NULL) AS is_liked
FROM unnest(p_post_ids) AS pid
LEFT JOIN likes l ON l.post_id = pid AND l.user_id = auth_uid();
```

### 3.3 — RLS policies add overhead on every query

The `posts_select` RLS policy contains 3 `EXISTS` subqueries (author visibility, follower check, block check). These run on every row for every query, including feed queries that already filter for these conditions.

**Fix:** For the feed functions (which are `SECURITY DEFINER` and already filter manually), RLS is bypassed. Verify this is actually the case — if RLS still applies inside `SECURITY DEFINER`, consider using a service role that bypasses RLS, and do authorization in the function logic.

---

## 4. CACHING STRATEGIES

### 4.1 — Redis layer (required, not optional)

| Cache | Key Pattern | TTL | Purpose |
|---|---|---|---|
| Feed page cache | `feed:main:{viewer_id}:{cursor_hash}` | 60s | Avoid re-scoring identical feed requests on rapid scroll |
| Friends feed | `feed:friends:{viewer_id}:{cursor_hash}` | 30s | Reverse-chrono is stable for short periods |
| Profile cache | `profile:{user_id}` | 120s | Profile pages are read-heavy, write-rare |
| User metadata | `user:{user_id}:meta` | 300s | Username, photo, visibility — read on every post card |
| Like state | `liked:{viewer_id}:{post_id}` | 600s | Prevent DB hit on every heart icon render |
| 24h posting rule | `post:cooldown:{user_id}` | 86400s | Client-side gate before hitting server |
| Exposure counts | `exposure:{viewer_id}:{author_id}:{date}` | 86400s | Reduce DB writes for exposure tracking |
| Post counters | `post:{post_id}:likes` | 30s | Buffer like increments, flush to DB in batch |

**Estimated Redis memory at 1M DAU:**
- Feed cache: ~1M users × 2 feeds × 20KB avg = ~40GB (too large — cache only active users in last 5 min → ~2GB)
- Profile cache: ~500K profiles × 5KB = ~2.5GB
- Like state: ~5M recent like checks × 100B = ~500MB
- **Total: ~5–8GB Redis, single r6g.xlarge instance**

### 4.2 — Application-level caching

The iOS client has zero caching. Every feed load, every profile view, every like check hits the network.

**Required:**
- `URLCache` with 50MB disk cache for API responses
- In-memory LRU for decoded feed pages (last 3 pages per segment)
- `NSCache` for `UIImage` thumbnails on profile tiles
- Persist `nextPostAllowedAt` to disk so client can gate before upload

---

## 5. CDN CONFIGURATION

### 5.1 — Image delivery

| Setting | Value | Rationale |
|---|---|---|
| Provider | CloudFront (AWS) or Supabase CDN | Must sit in front of S3/Storage |
| Cache TTL | 365 days | Images are immutable (never modified after upload) |
| Cache key | Full S3 path (includes UUID) | Unique per image, no invalidation needed |
| Compression | Disabled | Images are already compressed (HEIC/JPEG) |
| HTTP/2 | Enabled | Multiplexed connections for feed image loading |
| Origin shield | Enabled | Reduce origin fetches for viral posts |
| Edge locations | US + EU initially | Expand based on user geography |
| Signed URLs | Optional | Not needed if bucket is public-read after upload |

### 5.2 — API caching at CDN edge (optional, phase 2)

Feed responses for the Main feed (same for all viewers except personalization) could be partially cached:

- Cache the base ranking (without personalization) at edge for 60s
- Apply the 0.10 personalization weight at the API layer
- This offloads 90% of feed traffic from the database

### 5.3 — Missing: Client image caching

The iOS app uses SwiftUI `AsyncImage` which has basic in-memory caching but no disk persistence. When the user scrolls back up, images reload from network.

**Fix:** Replace `AsyncImage` with a library like Kingfisher/Nuke, or implement a custom `URLCache`-backed image loader with 200MB disk cache.

---

## 6. IMAGE STORAGE COSTS

### 6.1 — Storage math

```
Posts per day:     1M DAU × 1 post/day × ~60% actually post = 600K images/day
Average size:      1MB (target range 500KB–1.5MB)
Daily storage:     600K × 1MB = 600GB/day
Monthly storage:   600GB × 30 = 18TB/month
Annual storage:    18TB × 12 = 216TB/year
```

### 6.2 — S3 costs (us-east-1)

| Component | Monthly Cost |
|---|---|
| S3 Standard storage (18TB, growing) | $414/mo at $0.023/GB |
| S3 PUT requests (600K/day = 18M/mo) | $90/mo at $0.005/1K |
| S3 GET requests (via CloudFront origin) | Minimal (origin shield reduces) |
| CloudFront transfer (assume 50TB/mo outbound) | $4,250/mo at ~$0.085/GB |
| **Total image infra at 1M DAU** | **~$4,750/mo** |

### 6.3 — Cost optimization

- **S3 Intelligent Tiering**: Expired posts (>3 days, not signature) are rarely accessed. Auto-tier to Infrequent Access after 30 days → saves ~40% on storage.
- **Archive images**: Posts >90 days old and not in signature should move to S3 Glacier Instant Retrieval ($0.004/GB) → saves ~80% on cold storage.
- **Image deduplication**: Not an issue since each post is unique.
- **WebP/AVIF conversion**: Serve WebP to clients that support it → ~30% bandwidth savings on CloudFront.

---

## 7. INFRASTRUCTURE COST ESTIMATES (1M DAU)

### 7.1 — Compute

| Service | Spec | Monthly Cost |
|---|---|---|
| API servers (ECS Fargate) | 4 × 2vCPU/4GB, auto-scale to 8 | $600 |
| RDS PostgreSQL | db.r6g.2xlarge (8vCPU/64GB), Multi-AZ | $2,800 |
| RDS read replicas | 2 × db.r6g.xlarge for feed reads | $1,800 |
| ElastiCache Redis | r6g.xlarge (26GB), single node | $430 |
| Lambda (background jobs) | Scoring, cleanup, counter flush | $100 |
| ALB / API Gateway | Load balancer | $150 |

### 7.2 — Storage & transfer

| Service | Monthly Cost |
|---|---|
| S3 (images) | $500 |
| CloudFront (50TB transfer) | $4,250 |
| RDS storage (500GB SSD) | $115 |

### 7.3 — Operations

| Service | Monthly Cost |
|---|---|
| CloudWatch / monitoring | $200 |
| WAF | $100 |
| Secrets Manager | $20 |
| Certificate Manager | Free |

### 7.4 — Total

| Category | Monthly |
|---|---|
| Compute | $5,880 |
| Storage & transfer | $4,865 |
| Operations | $320 |
| **Total** | **~$11,065/mo** |

At 1M DAU, that's **$0.011/user/month** or **$0.37/user/year**.

**Warning:** CloudFront transfer dominates cost. If image sizes are not kept under control or CDN cache hit rate drops below 90%, this number doubles.

---

## 8. WEAK POINTS IN RANKING & EXPOSURE LOGIC

### 8.1 — Batch normalization is unstable

The ranking formula normalizes likes and velocity against the batch maximum:

```sql
ln(1 + like_count) / ln(1 + max_likes)
```

**Problem:** `max_likes` changes with every request. If a viral post enters the window, every other post's like score drops relative to it. Feed ordering becomes unstable — users see different rankings on every refresh even when nothing changed.

**Fix:** Use a rolling 24-hour percentile instead of batch max:

```sql
-- Pre-compute percentiles hourly
like_score = ln(1 + like_count) / ln(1 + p99_likes_24h)
```

### 8.2 — Exposure cap is trivially bypassable

The exposure cap is tracked per calendar day (UTC). A user loading feeds at 23:59 UTC sees author X twice, then at 00:01 UTC the counter resets and they see author X twice more — 4 posts in 2 minutes.

**Fix:** Use a rolling 24-hour window instead of calendar day:

```sql
-- Change feed_exposures PK from (viewer_id, author_id, feed_date) to:
CREATE TABLE feed_exposures (
    viewer_id UUID, author_id UUID, exposed_at TIMESTAMPTZ,
    PRIMARY KEY (viewer_id, author_id, exposed_at)
);
-- Query: COUNT(*) WHERE exposed_at > now() - INTERVAL '24 hours'
```

### 8.3 — Exposure tracking is fire-and-forget

`record_feed_exposures()` is called after serving the feed. If the client drops the connection before the call completes, or the server crashes between serving and recording, the cap is not enforced. The user sees the same author again.

**Fix:** Record exposures atomically with the feed query, inside the same transaction.

### 8.4 — Freshness weight (0.45) is too dominant

With a 13.86-hour half-life and 0.45 weight, a brand-new post with 0 likes scores:

```
0.20×0 + 0.25×0 + 0.45×1.0 + 0.10×0 = 0.450
```

A 24-hour-old post with maximum likes and maximum velocity scores:

```
0.20×1.0 + 0.25×1.0 + 0.45×0.301 + 0.10×0 = 0.585
```

The viral post only beats the zero-engagement new post by 0.135. A 30-hour-old viral post:

```
0.20×1.0 + 0.25×1.0 + 0.45×0.223 + 0.10×0 = 0.550
```

This means any post >30 hours old, regardless of engagement, loses to a brand-new zero-engagement post if the viewer follows the new author:

```
New post from followed author: 0.45×1.0 + 0.10×1.0 = 0.550
```

**Impact:** The feed will feel like reverse-chronological with a slight quality boost, not a discovery feed. High-quality older posts sink too fast.

**Fix:** Reduce freshness to 0.30, increase like weight to 0.30, or use a gentler decay (λ=0.03, half-life ~23 hours).

### 8.5 — Personalization signal is too weak

The only personalization input is a binary follow signal (0.10 weight). This means the Main feed is functionally identical for all users who follow similar people.

**Missing signals:**
- Historical like patterns (collaborative filtering)
- Tag-based affinity (user who likes posts tagged "Nike" sees more "Nike" posts)
- Negative signals (posts viewed but not liked → reduce similar content)

These are phase-2 concerns but the schema has no foundation for them. No `user_interests` table, no tag-based scoring.

### 8.6 — No cold-start handling

New users with 0 follows get the same Main feed as everyone else, but with personalization_score = 0 for all posts. The feed has no way to learn their preferences.

**Fix:** Add an onboarding flow that collects initial interests, or boost high-quality diverse content for users with <10 follows.

---

## 9. iOS CLIENT ISSUES (Production Blockers)

| Issue | Severity | File |
|---|---|---|
| Auth token stored in `UserDefaults` instead of Keychain | **CRITICAL** | `APIClient.swift:161` |
| `activeContinuation` not cleaned up on dealloc — causes hanging tasks | **CRITICAL** | `CameraRepresentable.swift:71` |
| New `URLSession` created per upload, `defer` invalidates before completion | **HIGH** | `ImageUploadService.swift:201` |
| Feed `posts` array grows unbounded — OOM on long scroll | **HIGH** | `FeedViewModel.swift:posts` |
| Like toggle has race condition on index lookup | **HIGH** | `FeedViewModel.swift:93-120` |
| No image disk cache — every scroll re-downloads from network | **HIGH** | All `AsyncImage` usage |
| No client-side 24h rule check — user uploads image then gets rejected | **MEDIUM** | `PostViewModel.swift` |
| Camera `deinit` doesn't stop session — battery drain | **MEDIUM** | `CameraRepresentable.swift` |

---

## 10. SUMMARY — PRIORITY FIX ORDER

### Must fix before any production traffic:
1. Pre-compute feed scores (background job) — eliminates 3M-row scan per request
2. Replace `post_views` raw events with direct `post_view_hourly` increment
3. Add Redis caching layer for feeds, profiles, and like state
4. Fix iOS token storage (Keychain, not UserDefaults)
5. Add CDN for image delivery
6. Fix camera continuation cleanup
7. Add image disk caching on client

### Must fix before 100K DAU:
8. Batch counter updates (move triggers to background worker)
9. Add read replicas and route feed queries there
10. Fix feed exposure tracking to be atomic with feed serving
11. Implement client-side 24h rule gate
12. Add `URLCache` for API responses
13. Cap in-memory feed array size (virtualized window)

### Must fix before 1M DAU:
14. Stabilize ranking normalization (rolling percentile, not batch max)
15. Fix exposure cap to use rolling 24h window
16. Add S3 lifecycle policies for cost control
17. Re-tune freshness weight (0.45 is too dominant)
18. Add collaborative filtering signals to ranking
19. Implement edge caching for base feed ranking
