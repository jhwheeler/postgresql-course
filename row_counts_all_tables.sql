-- Get estimated row counts for all tables in the public schema
SELECT
  relid AS table_id,
  relname AS table_name,
  n_live_tup AS row_count
FROM
  pg_stat_user_tables
WHERE
  schemaname = 'public'
ORDER BY
  n_live_tup DESC;

-- ----------------------------------------------------------------------
-- Feedback / review notes
-- ----------------------------------------------------------------------
-- 1. Source column. The exercise specifies `pg_class.reltuples`, but you
--    pulled `n_live_tup` from `pg_stat_user_tables`. Both are estimates,
--    but they're maintained by different mechanisms and can drift apart.
--    Worth understanding when each is updated and which one the planner
--    actually uses for cost estimation.
--      - https://www.postgresql.org/docs/current/catalog-pg-class.html
--      - https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ALL-TABLES-VIEW
--      - Try: ANALYZE one table, then compare the two values before/after.
--
-- 2. If you rewrite using `pg_class` directly, you'll need to filter
--    by `relkind` (you'll see why when you look at the catalog — what
--    ELSE lives in pg_class besides regular tables?). `pg_stat_user_tables`
--    does this filtering for you, which is a hint about what's in there.
--      - https://www.postgresql.org/docs/current/catalog-pg-class.html
--        (look at the `relkind` column's documented values)
--
-- 3. Variation not implemented: order by table size on disk via
--    `pg_total_relation_size`. Worth thinking about: this function
--    returns *what* exactly — just the heap? heap + indexes? + TOAST?
--    The answer matters for interpreting the ranking.
--      - https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-DBOBJECT
--      - Also look up `pg_relation_size`, `pg_indexes_size`, and
--        `pg_size_pretty` while you're there.
