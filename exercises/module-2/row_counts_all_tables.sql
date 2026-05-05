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
