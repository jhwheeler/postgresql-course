# Learning PostgreSQL for backend work at Peterson Academy

A focused, mostly-free curriculum aimed at making me a stronger backend engineer
on the PA web codebase specifically. Ordered by leverage, not difficulty.

## What our codebase actually uses

Knowing the target shapes the curriculum. `packages/supabase/schema.sql` is
~3,950 lines and contains 168+ uses of `CREATE TRIGGER / FUNCTION / POLICY /
INDEX / MATERIALIZED VIEW / cron.*`. The Postgres surface area I need to be
fluent in:

- **Supabase-flavored Postgres** — RLS is first-class, not optional. Most tables
  have policies; understanding `auth.uid()`, `USING` vs `WITH CHECK`, and the
  performance characteristics of policy expressions is required for any
  user-facing data work.
- **Triggers + PL/pgSQL functions** — e.g. `trigger_grade_short_answer_quiz`,
  the auto-`updated_at` trigger applied broadly, and the new grading triggers
  in `20260428152506_add_grading_triggers.sql`. Triggers fire async work via
  cron, so understanding `BEFORE/AFTER`, `FOR EACH ROW/STATEMENT`, and `WHEN`
  clauses matters.
- **pg_cron jobs** — `process_course_reminders_cron`, `grade_short_answers_cron`.
  These are scheduled SQL — they share the same DB, locks, and resources as
  user requests, so understanding cost is critical.
- **Custom enum types** — `question_type`, `notification_subject`,
  `gift_status`, etc. Adding values to enums has migration constraints worth
  knowing (no removal, transactional rules).
- **Prisma + TypedSQL** — typed raw SQL files in `packages/app/prisma/sql/`,
  regenerated via `pnpm --filter app exec prisma generate --sql`. Means I'll
  hand-write SQL with generated TypeScript types — no ORM hand-holding.
- **Partial indexes**, check constraints, FK cascade rules, generated columns —
  scattered throughout the schema.
- **Edge functions** (Deno) hitting the DB — separate auth model, different
  performance envelope.

Anything that doesn't map to those is lower priority.

---

## Recommended free path, in order

### 1. Foundations — official tutorial, then build something

Work through Part I (the [official tutorial](https://www.postgresql.org/docs/current/tutorial.html))
end-to-end in `psql` against a local DB. Type the queries, don't just read
them.

From Parts II onward, treat these chapters as **reference, not pre-reading** —
open them when the exercise below makes you reach for something specific:

- **Ch 8 Data Types** — when choosing `text` vs `varchar` vs `citext` (we
  use `citext`), `numeric` precision, `timestamptz` vs `timestamp`, `jsonb`,
  arrays, `enum`.
- **Ch 5 Data Definition** — when writing CHECK / FK / generated columns.
- **Ch 11 Indexes** — when deciding B-tree vs GIN, partial vs covering.
- **Ch 13 Concurrency Control** — defer to Week 4.
- **Ch 14 Performance Tips** — defer to Week 3.

Bookmark for `Cmd+F` later: `SELECT`, `INSERT`, `UPDATE`, `CREATE INDEX`,
`CREATE POLICY`, `CREATE TRIGGER`, `EXPLAIN`.

**Practical exercise (Week 1 deliverable):** Spin up local Postgres (or use
the Supabase local dev DB), recreate one of our tables — `user_quizzes` is a
good size — with all constraints + indexes from memory. Don't peek at
`schema.sql` until you're stuck, and when you do, only consult Ch 5/8/11
for the syntax you need. When you think you're done, run `pg_dump
--schema-only -t user_quizzes` against your version and the real one, and
`diff`. Pass/fail: diff is empty, or you can articulate every remaining
difference.

### 2. psql + SQL fluency for ad-hoc data work

Goal: write off-the-cuff exploratory queries fluently — CS investigations,
debugging user states, sanity-checking new features — without an LLM
in the loop. The blocker isn't deep Postgres; it's idiom recall and `psql`
muscle memory.

**`~/.psqlrc` setup:**

```
-- silence the echo of these commands while .psqlrc runs (restored at the end)
\set QUIET 1
-- render NULL explicitly instead of as a blank — easy to confuse with empty string otherwise
\pset null '<NULL>'
-- nicer table borders
\pset linestyle unicode
\pset border 2
-- auto-switch to expanded display (\x) when a row is wider than the terminal
\x auto
-- show query duration in ms after every statement
\timing on
-- separate command history file per database, so `\s` history isn't polluted across DBs
\set HISTFILE ~/.psql_history- :DBNAME
-- skip storing consecutive duplicate history entries
\set HISTCONTROL ignoredups
-- tab-complete SQL keywords in UPPER CASE
\set COMP_KEYWORD_CASE upper
-- bold prompt showing host / user@db / transaction state — guards against forgetting you're on prod
\set PROMPT1 '%[%033[1m%]%M %n@%/%R%[%033[0m%]%# '
\set QUIET 0
```

Reference: [psql meta-commands & variables](https://www.postgresql.org/docs/current/app-psql.html)
documents every `\set`, `\pset`, prompt escape (`%M`, `%n`, `%/`, `%R`),
and built-in variable (`HISTFILE`, `HISTCONTROL`, `COMP_KEYWORD_CASE`,
`QUIET`) used above. Skim §"Variables" and §"Prompting" once.

**Meta commands worth memorizing:**

- `\d`, `\dt`, `\d <pattern>` — list / describe.
- `\d+ table` — describe with sizes, indexes, FK details.
- `\df <pattern>`, `\sf func`, `\ef func` — list / show / edit functions.
- `\dn`, `\dx`, `\dy` — schemas / extensions / event triggers.
- `\dp table` — policies on a table.
- `\timing`, `\gx` (force expanded for one query), `\watch 5` (re-run every 5s).
- `\copy ... TO 'file.csv' CSV HEADER` — export to CSV (client-side).
- `\set foo 'bar'` then `:foo`; `\e` to edit current query in `$EDITOR`.

**Workbook — write each in `psql`, then try the variation.** Each section
header links to the PG docs (and Modern SQL where it's tighter than the
official docs) for the idioms it uses. The intended workflow: read the
question, attempt the query, hit a wall, open the linked reference for the
specific operator/clause you need, finish the query. Don't pre-read the
whole reference.

_Schema introspection_ — [Information Schema](https://www.postgresql.org/docs/current/information-schema.html),
[System Catalogs](https://www.postgresql.org/docs/current/catalogs.html)
(especially `pg_class`, `pg_constraint`, `pg_trigger`, `pg_proc`,
`pg_policies`):

1. List all tables in `public` with their estimated row counts (`pg_class.reltuples`). _Variation: order by table size on disk (`pg_total_relation_size`) descending._

- Proposed answer: ./row_counts_all_tables.sql

2. For `user_quizzes`, list all incoming and outgoing FKs by querying `pg_constraint`. _Variation: do the same for any table given via `\set tbl 'table_name'`._

- Proposed answer: ./incoming-outgoing-fks.sql
  (Initially, I did it with scalar subqueries -- ./\_incoming-outgoing-fks_scalar-subqueries.sql -- until I learned about `regclass`)

3. List all triggers on a given table along with the function each calls. _Variation: across the whole schema, only triggers whose function calls `net.http_post` (i.e., `pg_net` async fan-out)._

- Proposed answer: ./triggers-with-functions.sql. Variation for `net.http_post`: ./net-http-posttriggers-with-functions.sql.
- Reinforcement drills against the same `pg_trigger` / `pg_proc` catalogs:
  - a) Decode `tgtype` into `(timing, events[])`. Bitmask: `1`=ROW, `2`=BEFORE, `4`=INSERT, `8`=DELETE, `16`=UPDATE, `32`=TRUNCATE, `64`=INSTEAD OF. Cross-check decoded output against `pg_get_triggerdef(oid)` for the same row.
    - Proposed answer: ./triggers-with-timing-and-events.sql
  - b) Aggregation pivot — same join as the schema-wide variation, but `GROUP BY` function and `array_agg(tgrelid::regclass)` the tables; filter `HAVING count(*) >= 2` to keep only functions called by multiple triggers. Collapses per-trigger rows into one row per function so you can read the blast radius of shared utilities like `set_updated_at` at a glance.
  - c) Anti-join — tables in `public` with no `updated_at` trigger. Write it both as `LEFT JOIN ... WHERE tg.oid IS NULL` and as `NOT EXISTS (...)`; verify the same row set.
  - d) Disabled triggers across the schema (`tgenabled <> 'O'`; values are `O`=enabled/origin, `D`=disabled, `R`=replica-only, `A`=always). Catches "turned off for a migration, never turned back on."
  - e) `SECURITY DEFINER` trigger functions with their pinned `search_path` — join `pg_trigger` → `pg_proc` → `pg_namespace`, filter `prosecdef = true`, surface `proconfig`. Bridges to Week 5; rows where `proconfig` lacks a `search_path=` entry are the hijacking footgun.

_Joins, anti-joins, aggregations_ — [PG §7.2 Table Expressions](https://www.postgresql.org/docs/current/queries-table-expressions.html),
[PG §9.21 Aggregate Functions](https://www.postgresql.org/docs/current/functions-aggregate.html),
[Modern SQL](https://modern-sql.com/) (Markus Winand — same author as
Use The Index, Luke!; covers `FILTER`, `LATERAL`, anti-join patterns):

4. Find users who started a quiz in the last 7 days but never submitted. Use `NOT EXISTS`. _Variation: rewrite as `LEFT JOIN ... WHERE submitted_at IS NULL` and verify the same row set._
5. For each course, count enrolled users; include courses with zero enrollments. Use `LEFT JOIN ... GROUP BY`. _Variation: only courses where the count is below the average across all courses (subquery in `HAVING`)._
6. Find quizzes with no questions linked. _Variation: quizzes with fewer than N questions, where N is a `\set` parameter._

_Top-N-per-group + window functions_ — [PG §3.5 Window Functions tutorial](https://www.postgresql.org/docs/current/tutorial-window.html)
(read this end-to-end — it's short and the single best window-function
intro), [PG §4.2.8 Window Function Calls](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS)
for syntax reference:

7. For each user, find their most recent quiz attempt. Use `row_number() OVER (PARTITION BY user_id ORDER BY started_at DESC)`. _Variation: their 3 most recent._
8. For each course, top 3 most-attempted quizzes. _Variation: top 3 by completion rate (a ratio, not a raw count) — and only courses with ≥ 50 attempts total._
9. Running total of quizzes started per day, last 30 days. Use `SUM(...) OVER (ORDER BY day)`. _Variation: 7-day moving average via `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW`._

_JSONB, arrays, enums_ — [PG §9.16 JSON Functions and Operators](https://www.postgresql.org/docs/current/functions-json.html),
[PG §9.19 Array Functions and Operators](https://www.postgresql.org/docs/current/functions-array.html),
[PG §8.7 Enumerated Types](https://www.postgresql.org/docs/current/datatype-enum.html):

10. Find rows where a JSONB column contains a specific top-level key (`?` operator). _Variation: where it contains a nested value at a given path (`#>` or `jsonb_path_exists`)._
11. For a `text[]` column, find rows whose array contains a specific value (`'val' = ANY(col)`). _Variation: rows whose array overlaps a set (`&&`), or contains all values in a set (`@>`)._
12. Aggregate JSONB across rows: per user, build a single JSONB object keyed by quiz*id with the score as value (`jsonb_object_agg`). \_Variation: same shape using `jsonb_agg` to build an array of small objects instead.*

_Date / time_ — [PG §9.9 Date/Time Functions](https://www.postgresql.org/docs/current/functions-datetime.html),
[PG §8.5 Date/Time Types](https://www.postgresql.org/docs/current/datatype-datetime.html)
(especially the timezone-handling section):

13. Quizzes started today in `America/Denver` (use `AT TIME ZONE`). _Variation: this calendar week (Mon–Sun) in the user's stored timezone._
14. Quiz starts bucketed by hour, last 24 hours, including hours with zero starts (`generate_series` LEFT JOIN). _Variation: by day, last 30 days; or by 5-minute buckets, last hour._
15. Time between quiz `started_at` and `submitted_at`: p50, p95, p99 using `percentile_cont`. _Variation: per course; or only for users in a given cohort._

_CS-investigation realism_ — composition over the prior idioms; new ref:
[PG §7.8 WITH Queries (CTEs)](https://www.postgresql.org/docs/current/queries-with.html):

16. Given a user*id (via `\set uid '...'`), build one query returning: their recent activity, their enrollments, their quiz attempts, their grades — as a single JSONB blob. Use CTEs + `jsonb_build_object`. \_Variation: same shape but for a list of user_ids, returning one row per user.*
17. Find users in a "shouldn't-exist" state — completed quizzes recorded but no enrollment row for the parent course. _Variation: users with conflicting timestamps across two tables (e.g., enrollment dated after their first completed quiz)._
18. Find probable duplicate users by normalized email (lowercased, trimmed) or another heuristic. _Variation: by a fuzzy match on name + signup date proximity (`pg_trgm` similarity ≥ 0.8 and signup within 24h)._

**Pass/fail:** write any of these in under 2 minutes without looking up syntax. Each subsequent week ends with a 3-query drill that keeps the muscle memory warm.

### 3. Indexing + query plans — highest-leverage skill

- [Use The Index, Luke!](https://use-the-index-luke.com/) by Markus Winand
- [EXPLAIN (ANALYZE, BUFFERS) in PostgreSQL](https://use-the-index-luke.com/sql/explain-plan/postgresql/getting-an-execution-plan)
- [PostgreSQL execution plan operations](https://use-the-index-luke.com/sql/explain-plan/postgresql/operations)

This is the single resource that will most change how I write queries. Free,
vendor-agnostic but with a dedicated PostgreSQL track. Covers B-tree internals,
index-only scans, why compound index column order matters, and how to read
`EXPLAIN ANALYZE` output without guessing.

**Why this matters for PA:** several of our slow endpoints are slow because of
missing or mis-ordered indexes (see the recent
`20260330000000_add_notifications_created_at_id_index.sql` migration). Being
able to look at a query and predict the plan is the skill that prevents these.

**Practical exercise (Week 3 deliverable):** run `EXPLAIN (ANALYZE, BUFFERS)`
on every query in `packages/app/prisma/sql/` and tabulate, per query:
top-level scan type, rows estimated vs actual, total time, buffers hit. Then
pick one offender — either a Seq Scan on a table over ~100k rows, or a node
where the planner's row estimate is >10x off — propose an index (or query
rewrite) and prove the fix with a before/after `EXPLAIN ANALYZE`. Pass/fail:
at least one measurable improvement, with the buffers + timing delta written
down.

**Side exercise — recursive CTEs:** Our prereq cycle detection
(`20260417173500_generalize_course_prereqs_to_course_associations.sql`)
uses `WITH RECURSIVE`. Read [PG docs §7.8](https://www.postgresql.org/docs/current/queries-with.html)
and write your own: given a small graph table, traverse it to find all
descendants of a node and detect cycles.

**Drill (3 queries):**

- For `user_quizzes`, find the 10 rows with the largest `(submitted_at - started_at)` interval. _Variation: same, but only for users who took ≥ 5 quizzes._
- Compare two indexes' selectivity on `user_quizzes`: count distinct values for `(user_id)` vs `(user_id, quiz_id)`, and look up `null_frac` and `n_distinct` for each in `pg_stats`. _Variation: also compute `correlation` (physical row order) — useful for predicting whether a BRIN index could work._
- Force a Seq Scan on a large table with `SET LOCAL enable_indexscan = off; EXPLAIN ANALYZE ...;` and compare to the index plan. _Variation: also disable `enable_bitmapscan` to see the full cost gap._

### 4. Internals — so I understand _why_ things are slow

Reference for the exercises below:

- [Bruce Momjian's internals presentations](https://momjian.us/main/presentations/internals.html)
  — open the MVCC deck when looking at `ctid`, `xmin`, `xmax` during the
  exercise.
- [The Internals of PostgreSQL — Ch 5 Concurrency Control](https://www.interdb.jp/pg/pgsql05.html)
  — open this when querying `pg_locks`. Buffer manager / WAL / vacuum
  chapters are on-demand only.

**Practical exercise (Week 4 deliverable):** Open two `psql` sessions against
a local DB. In session A, `BEGIN; UPDATE user_quizzes SET updated_at = now()
WHERE id = $row_a;` and don't commit. In session B, query `pg_locks` joined
to `pg_stat_activity` to see the row-level lock session A is holding, then
`UPDATE` a _different_ row — it should not block. Now `UPDATE` the same row
— it should block until session A commits or rolls back. Then check `ctid`
on the row before and after the update to see MVCC's insert-then-mark-dead
in action, and `pg_stat_user_tables.n_dead_tup` to see the dead tuple
accumulate. This is the concrete demonstration that the broadly-applied
`updated_at` trigger only takes row-level locks, so concurrent writers to
different rows don't contend.

**Side exercise — advisory locks:** Look at the prereq cycle detection in
`20260417173500_generalize_course_prereqs_to_course_associations.sql` — it
uses `pg_advisory_xact_lock` to serialize concurrent inserts. Reproduce the
table locally _without_ the advisory lock, fire two concurrent transactions
that would form a cycle (each adds an edge whose other half is being added
by the other transaction), and watch them both commit a cycle into
existence. Add the advisory lock back; watch the second transaction wait.

**Drill (3 queries):**

- Tables with the most dead tuples right now: `SELECT relname, n_live_tup, n_dead_tup, last_autovacuum FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 20;`. _Variation: order by `n_dead_tup::float / nullif(n_live_tup, 0)` (bloat ratio) descending._
- Active queries with their lock status: join `pg_stat_activity` to `pg_locks` for `state = 'active'`. _Variation: only sessions waiting on a lock (`wait_event_type = 'Lock'`), with the blocker's `pid` resolved via `pg_blocking_pids(pid)`._
- Largest tables (heap + indexes): `SELECT relname, pg_size_pretty(pg_total_relation_size(oid)) FROM pg_class WHERE relkind = 'r' ORDER BY pg_total_relation_size(oid) DESC LIMIT 20;`. _Variation: split heap size from index size and show the ratio — heavy index-to-heap ratios often signal redundant indexes._

### 5. Performance / EXPLAIN deep dives — reference for Week 3

Reference for the Week 3 exercise. Open during, not before:

- [pganalyze eBooks](https://pganalyze.com/resources/ebooks) (free with
  email).
- [Tigerdata: Optimizing PostgreSQL Indexes](https://www.tigerdata.com/learn/postgresql-performance-tuning-optimizing-database-indexes).
- [oneuptime: PostgreSQL Query Optimization (2026)](https://oneuptime.com/blog/post/2026-01-26-postgresql-query-optimization/view).

### 6. Supabase + RLS — PA-specific

Read the [agent-skills RLS reference](https://github.com/supabase/agent-skills/blob/main/skills/supabase-postgres-best-practices/references/security-rls-basics.md)
once before the exercise. The full [Supabase RLS docs](https://supabase.com/docs/guides/database/postgres/row-level-security)
and [Column Level Security docs](https://supabase.com/docs/guides/database/postgres/column-level-security)
are reference.

Footguns:

- Calling `auth.uid()` per-row instead of wrapping it in `(SELECT auth.uid())`.
- Mixing `USING` and `WITH CHECK` incorrectly on `UPDATE` policies.
- Forgetting that policies are additive (`OR`-combined within a role).
- Joining against tables that themselves have RLS (compounding cost).
- **`SECURITY DEFINER` functions bypass RLS for callers** — every one of
  them is a security surface. Always set `search_path` explicitly inside
  the function body to prevent search-path hijacking.
- **`pg_net` async fan-out from triggers** — `net.http_post()` from an
  `AFTER` trigger fires edge functions outside the transaction. The trigger
  can't await the response, so retry/idempotency lives in the edge function,
  not the SQL.

**Practical exercise (Week 5 deliverable):** Three parts.

1. **`auth.uid()` rewrap.** Pick a non-trivial policy from
   `packages/supabase/schema.sql` that calls `auth.uid()` (ideally on a
   table with many rows). Recreate the table locally, seed it with
   realistic row counts, and run `EXPLAIN (ANALYZE, BUFFERS)` against a
   typical `SELECT` both with the policy as written and with `auth.uid()`
   rewrapped as `(SELECT auth.uid())`. The unwrapped form re-evaluates per
   row; the wrapped form evaluates once.
2. **Trigger reimplementation.** Pick one trigger (e.g.
   `trigger_grade_short_answer_quiz`) and reimplement a minimal version
   locally: define the function, attach the trigger, fire it via INSERT,
   verify the side effect.
3. **`SECURITY DEFINER` + `pg_net` audit.** Find one `SECURITY DEFINER`
   function in `schema.sql` and write down what RLS it bypasses, what its
   `search_path` is set to, and who can `EXECUTE` it. Then look at one
   `pg_net`-using trigger (e.g. the embedding triggers in
   `20251205124411_add_embedding_triggers.sql`) and list the failure modes:
   what happens if the HTTP call fails? If the trigger fires twice? If the
   row is deleted before the edge function processes it?

Pass/fail: you can read any `CREATE TRIGGER` / `CREATE POLICY` /
`SECURITY DEFINER` function in `schema.sql` and explain it as code.

**Drill (3 queries):**

- All policies on a given table with their `qual` and `with_check`: `SELECT policyname, cmd, qual, with_check FROM pg_policies WHERE tablename = :'tbl';`. _Variation: across all tables, only policies whose `qual` text mentions `auth.uid()` *not* preceded by `SELECT ` (the unwrapped footgun)._
- All `SECURITY DEFINER` functions in `public` with their pinned `search_path`: `SELECT proname, prosecdef, proconfig FROM pg_proc JOIN pg_namespace n ON n.oid = pronamespace WHERE n.nspname = 'public' AND prosecdef;`. _Variation: only those where `proconfig IS NULL` or has no `search_path=` entry — the hijacking risk._
- All triggers across the schema that call `net.http_post`: join `pg_trigger` to `pg_proc` and grep `prosrc` for `'net.http_post'`. _Variation: include the table name, trigger timing (BEFORE/AFTER), and event (decode `tgtype` bitmask) so you can scan for INSERT-only vs all-event triggers._

### 7. Migrations + production observability — day-job skills

The two skills I'll exercise weekly once shipping: writing migrations that
don't lock production, and finding the actually-slow query rather than the
one I suspect is slow.

**Safe migrations:**

- [`CREATE INDEX CONCURRENTLY`](https://www.postgresql.org/docs/current/sql-createindex.html)
  — read the CONCURRENTLY section carefully. Costs more, blocks less, can't
  run inside a transaction.
- [`ALTER TABLE` lock levels](https://www.postgresql.org/docs/current/sql-altertable.html)
  — the section enumerating which subforms take `ACCESS EXCLUSIVE` vs.
  lighter locks. Single most-referenced page when reviewing a migration.
- [Strong Migrations README](https://github.com/ankane/strong_migrations) —
  Rails-flavored, but the catalog of unsafe operations and the recommended
  multi-step rewrites is canonical Postgres advice (NOT NULL + default,
  type changes, batch backfills, etc.).

The patterns that bite most often in Supabase land: adding a NOT NULL column
with a non-constant default on a big table, renaming a column the app still
reads, changing a column type in-place, creating an index without
`CONCURRENTLY`, `ALTER TYPE ... ADD VALUE` inside a transaction, and any
`ALTER TABLE` that holds `ACCESS EXCLUSIVE` while a long query is running
(it queues _every_ subsequent query behind it).

**Production observability:**

- [`pg_stat_statements`](https://www.postgresql.org/docs/current/pgstatstatements.html)
  — already enabled on Supabase.
- Supabase's Query Performance dashboard — same data with a UI, plus the
  built-in index advisor.
- [`auto_explain`](https://www.postgresql.org/docs/current/auto-explain.html)
  — logs slow query plans automatically; useful when something only goes
  slow in prod with prod data.

**Practical exercise (Week 6 deliverable):** Pick one recent migration from
`packages/supabase/migrations/`. For each statement, write down: lock level
acquired, whether it requires a full table rewrite/scan, and whether it's
safe on a 10M-row table under live traffic. Rewrite anything unsafe (e.g.
`CREATE INDEX` → `CREATE INDEX CONCURRENTLY`; `ADD COLUMN ... NOT NULL
DEFAULT <expr>` → add nullable, backfill in batches, set NOT NULL with
`NOT VALID` then `VALIDATE`). Then on Supabase prod, pull the top 10
queries from `pg_stat_statements` (or the Query Performance pane) ordered
by `total_exec_time` and tag each as one of: indexed-fine, missing-index,
n+1-pattern, or RLS-overhead. Pass/fail: a per-statement lock annotation
for the migration, plus the tagged top-10.

**Drill (3 queries):**

- Top 10 from `pg_stat_statements` by `total_exec_time`: `SELECT query, calls, total_exec_time, mean_exec_time FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;`. _Variation: also rank by `mean_exec_time` (per-call), `calls` (frequency), and `rows / nullif(calls, 0)` (rows-per-call) — different rankings surface different problems._
- Tables whose `seq_scan` count exceeds `idx_scan`: `SELECT relname, seq_scan, idx_scan, n_live_tup FROM pg_stat_user_tables WHERE seq_scan > idx_scan ORDER BY seq_scan - idx_scan DESC;`. _Variation: only tables with `n_live_tup > 100000` (small tables Seq-Scan correctly)._
- Currently-running long DDL: `SELECT pid, now() - query_start AS dur, state, query FROM pg_stat_activity WHERE query ~* '^(alter|create index|reindex)\s' AND state = 'active' ORDER BY dur DESC;`. _Variation: include `pg_blocking_pids(pid)` so you can see which DDL is queued behind a long-running read._

### 8. Vector + full-text search — hybrid retrieval

The codebase ships hybrid search (FTS + vector + RRF) in
`post_search_hybrid`. References:

- [pgvector README](https://github.com/pgvector/pgvector) — operators
  (`<=>` cosine, `<->` L2, `<#>` inner product), HNSW vs IVFFLAT trade-offs,
  the `m` / `ef_construction` / `ef_search` tuning knobs.
- [PG Ch 12 Full Text Search](https://www.postgresql.org/docs/current/textsearch.html)
  — read 12.1 (intro) and 12.3 (configurations) before building; the rest
  is reference.

Footguns: HNSW indexes are not free to maintain (insert cost, build time on
seed); the distance operator must match the index `*_ops` (e.g.
`vector_cosine_ops` ↔ `<=>`); `to_tsvector(language, ...)` configuration is
sticky once data is indexed; tsvector columns need a trigger to stay in
sync unless they're `GENERATED ALWAYS`.

**Practical exercise (Week 7 deliverable):** Spin up a local DB with
pgvector installed. Create a `posts` table with `title`, `body`, a
`text_search_vector tsvector` column maintained by a trigger, and an
`embedding vector(384)` column with an HNSW index. Seed ~10k rows
(Wikipedia dump excerpts or synthetic content; fake embeddings via random
unit vectors are fine — index mechanics don't care about semantic
correctness for this exercise). Then implement, as separate queries:

1. Pure FTS with `ts_rank` over `text_search_vector`.
2. Pure vector KNN with `<=>` and `ORDER BY ... LIMIT k`.
3. Hybrid via Reciprocal Rank Fusion (`SUM(1.0 / (k + rank))` summed across
   both rankings), matching the shape of `post_search_hybrid`.

Run `EXPLAIN (ANALYZE, BUFFERS)` on each and verify the GIN index is hit
for FTS and the HNSW index for vector. Pass/fail: all three queries return
sane top-k results, both indexes are actually used, and you can articulate
when to reach for each retrieval mode.

**Drill (3 queries against the seeded `posts` table):**

- Top 10 nearest posts to a target embedding with their cosine distance: `SELECT id, title, embedding <=> :'target' AS dist FROM posts ORDER BY embedding <=> :'target' LIMIT 10;`. _Variation: with a hard distance threshold (`WHERE embedding <=> :'target' < 0.3`); compare LIMIT-only vs threshold + LIMIT plans (HNSW behaves differently)._
- Posts that score high on FTS for a phrase but are _far_ from a target embedding (FTS-relevant, semantically unrelated). _Variation: the inverse — close in embedding space but no FTS match. Useful for spot-checking embedding quality._
- Histogram of FTS rank scores for a given query, bucketed by `ntile(10)`: `SELECT ntile(10) OVER (ORDER BY ts_rank(...)) AS bucket, count(*), avg(ts_rank(...)) FROM posts WHERE text_search_vector @@ to_tsquery(:'q') GROUP BY bucket;`. _Variation: same buckets but for cosine distance to a target vector — shows whether your corpus is densely or sparsely clustered around it._

### 9. Structured video course (optional, if I want lectures)

- [PostgreSQL for Everybody Specialization (Coursera)](https://www.coursera.org/specializations/postgresql-for-everybody) — Charles Severance / U. Michigan, audit-free
- freeCodeCamp PostgreSQL course on YouTube — solid ~4 hour intro

Decent for fundamentals if reading-only is grinding. Skippable if the docs +
Use The Index, Luke! click for me.

---

## What to skip

- **Reading parts II–VIII cover-to-cover** — section 1 lists the chapters
  worth pre-reading; the rest is reference material.
- **W3Schools / Tutorialspoint** — too shallow; the official tutorial dominates.
- **Udemy "PostgreSQL Bootcamp" courses** — fine, but mostly repeat free content.
- **DataCamp / paid SaaS platforms** — everything they teach is in the free
  list above; not worth a subscription unless I prefer their UI.
- **Random Medium posts** — useful for one-off questions, not a curriculum.

---

## Suggested 7-week sequence

| Week | Focus                                               | Hands-on deliverable                                                                                                                           |
| ---- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | SQL fundamentals, types, constraints, schema design | Recreate `user_quizzes` from memory; `pg_dump --schema-only` + `diff` against the real one is empty                                            |
| 2    | psql + SQL fluency for ad-hoc data work             | 18-query workbook (schema introspection, joins, top-N, JSONB, dates, CS-investigation); write any in <2 min                                    |
| 3    | Indexes, EXPLAIN ANALYZE, query planning            | Tabulate plans for every query in `packages/app/prisma/sql/`; ship one measured index/rewrite fix; one `WITH RECURSIVE` graph traversal        |
| 4    | MVCC, transactions, locking, advisory locks         | Two-`psql`-session demo of row locks + MVCC `ctid` churn; reproduce the prereq cycle race with/without `pg_advisory_xact_lock`                 |
| 5    | RLS, triggers, PL/pgSQL, `SECURITY DEFINER`, pg_net | `auth.uid()` rewrap with `EXPLAIN ANALYZE` delta; reimplement one trigger end-to-end; audit one `SECURITY DEFINER` fn and one `pg_net` trigger |
| 6    | Safe migrations + production observability          | Lock-annotate one recent migration and rewrite anything unsafe; tag top-10 prod queries from `pg_stat_statements` by issue type                |
| 7    | Vector + full-text search (hybrid retrieval)        | Build a 10k-row `posts` table with tsvector + `vector(384)` + HNSW; ship FTS, vector KNN, and RRF-hybrid queries; verify both indexes are hit  |

Weeks 3–7 each carry a 3-query drill that keeps Week 2's idiom muscle warm
while reinforcing that week's topic.

---

## Reference / cheat sheet links to keep open

- [PostgreSQL docs (current)](https://www.postgresql.org/docs/current/)
- [Use The Index, Luke!](https://use-the-index-luke.com/)
- [Supabase RLS docs](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Bruce Momjian's site](https://momjian.us/main/)
- [pganalyze blog & ebooks](https://pganalyze.com/resources/ebooks)
- [The Internals of PostgreSQL](https://www.interdb.jp/pg/)
