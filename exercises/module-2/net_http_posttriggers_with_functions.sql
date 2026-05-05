-- List all user-defined triggers that call net.http_post
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
  pr.prosrc like '%net.http_post%'
  and not tg.tgisinternal;

