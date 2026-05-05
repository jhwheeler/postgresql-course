-- List all incoming and outgoing FKs for a table
-- NB: This was the first attempt, using scalar subqueries; it is not correct.
-- Refer to ./incoming-outgoing-fks.sql for the correct answer
SELECT
  conname,
  conrelid,
  confrelid,
  conrelid::regclass as source_table,
  confrelid::regclass as ref_table,
  case when
    conrelid = (
      select pg_class.oid
      from pg_class
      where pg_class.relname = :'tbl'
    )
    then 'outgoing'
    else 'incoming'
  end as direction
FROM
  pg_constraint
WHERE
  (conrelid = (
    SELECT
      oid
    FROM
      pg_class
    WHERE
      pg_class.relname = :'tbl'
  )
  OR confrelid = (
    SELECT
      oid
    FROM
      pg_class
    WHERE
      pg_class.relname = :'tbl'
  ))
  AND confrelid > 0;
