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
-- contype: f = foreign key, c = check, n = not-null, p = primary key, u = unique, t = trigger, x = exclusion
and contype = 'f';
