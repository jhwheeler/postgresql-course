-- Get triggers with timing and events
-- NB: The `#define` lines in the comments
-- from src/include/catalog/pg_trigger.h
-- are bitmask definitions for tgtype
select
  tgtype,
  tgname,
  -- when trigger fires
  case when tgtype & 64 = 64 then
    -- #define TRIGGER_TYPE_INSTEAD (1 << 6)
    'instead of'
  when tgtype & 2 = 2 then
    -- #define TRIGGER_TYPE_BEFORE (1 << 1)
    'before'
  else
    -- #define TRIGGER_TYPE_AFTER 0
    -- NB: AFTER is default, i.e. has no bitmask,
    -- so it's the fallthrough case
    'after'
  end as timing,
  array_remove(array[
    -- event trigger fires on
    case when tgtype & 4 = 4 then
      -- #define TRIGGER_TYPE_INSERT (1 << 2)
      'insert'
    end, case when tgtype & 16 = 16 then
      -- #define TRIGGER_TYPE_UPDATE (1 << 4)
      'update'
    end, case when tgtype & 8 = 8 then
      -- #define TRIGGER_TYPE_DELETE (1 << 3)
      'delete'
    end, case when tgtype & 32 = 32 then
      -- #define TRIGGER_TYPE_TRUNCATE (1 << 5)
      'truncate'
    end], null) as events,
  -- row vs statement level
  case when tgtype & 1 = 1 then
    -- #define TRIGGER_TYPE_ROW (1 << 0)
    'row'
  else
    -- #define TRIGGER_TYPE_ROW 0
    -- NB: STATEMENT is default, i.e. has no bitmask,
    -- so it's the fallthrough case
    'statement'
  end as level
from
  pg_trigger
where
  tgisinternal = false;

