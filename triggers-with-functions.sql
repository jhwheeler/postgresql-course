-- List all user-defined triggers on a given table along with the function each calls

select
  tg.tgrelid as "Table ID",
  tg.tgrelid::regclass as "Table",
  tg.oid as "Trigger ID",
  tg.tgname as "Trigger Name",
  pg_get_triggerdef(tg.oid) as "Trigger Definition", -- definition of the trigger itself
  tg.tgfoid as "Triggered Function ID",
  pr.proname as "Function Name"
  -- pg_get_functiondef(tg.tgfoid) as "Triggered Function Definition" -- uncomment this to get the full definition of the function that the trigger calls
from
  pg_trigger tg
join pg_proc pr on tg.tgfoid = pr.oid
where
  tgrelid = :'tbl'::regclass
  -- and pr.prosrc like '%http_post%' -- uncomment this to filter out trigger fns that don't call net.http_post
  and not tg.tgisinternal;
