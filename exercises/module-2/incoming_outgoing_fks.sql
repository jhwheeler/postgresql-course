-- List all incoming and outgoing FKs for a table
select
  conname, -- name of the constraint
  conrelid::regclass as source_table, -- name of the source table
  confrelid::regclass as ref_table, -- name of the referenced table
  pg_get_constraintdef(oid) as fk_definition, -- definition of the foreign key relation
  -- whether it's incoming or outgoing foreign key relation (relative to the table)
  case when conrelid = :'tbl'::regclass then
    'outgoing'
  else
    'incoming'
  end as direction,
  conindid::regclass as index -- supporting index
from
  pg_constraint
where (conrelid = :'tbl'::regclass -- gets the outgoing fkey relations
  or confrelid = :'tbl'::regclass -- gets the incoming fkey relations
)
and contype = 'f';

-- filter to only show foreign key constraints
-- f = foreign key, c = check, n = not-null, p = primary key, u = unique, t = trigger, x = exclusion
-- ----------------------------------------------------------------------
-- Feedback (from Claude)
-- ----------------------------------------------------------------------
-- 1. Filtering FKs. `confrelid > 0` works because of how non-FK
--    constraints populate that column, but it's an indirect filter.
--    Look at the `pg_constraint` catalog page — there's a column whose
--    explicit job is to identify the constraint type. Using it makes
--    the query say what it means, and prepares you to filter for other
--    constraint types (CHECK, UNIQUE, EXCLUSION) later.
--      - https://www.postgresql.org/docs/current/catalog-pg-constraint.html
--
-- ANSWER: Fixed. Now has `contype = 'f'` instead of `confrelid > 0`.
--
-- 2. Output is missing the most important detail of an FK. You're
--    showing source_table and ref_table, but what about the columns?
--    A FK between users and orders is meaningless without knowing
--    `orders.user_id -> users.id`. Look up:
--      - `conkey` and `confkey` in pg_constraint (the raw column-number
--        arrays) — and how to resolve those via `pg_attribute`
--      - the convenience function `pg_get_constraintdef(oid)` which
--        returns the human-readable form including ON DELETE/UPDATE
--        actions
--        https://www.postgresql.org/docs/current/functions-info.html
--
-- ANSWER: Good point, added with `pg_get_constraintdef(oid)`.
--
-- 3. Output noise: you're returning both raw OIDs (`conrelid`,
--    `confrelid`) AND their `regclass` casts. That was useful while
--    debugging, but for the final form, decide which audience you're
--    serving and drop the redundant one.
--
-- ANSWER: Fixed. Removed the two id cols.
--
-- 4. Good instinct switching from scalar subqueries to `regclass`.
--    Worth noting *why* it's not just shorter: `pg_class.relname`
--    isn't unique across schemas, so the scalar-subquery version
--    has a latent bug if the same table name exists in two schemas.
--    `regclass` resolves through `search_path` and gives you exactly
--    one OID. Keep that in your head — it's a recurring catalog gotcha.
--
-- ANSWER: Noted.
