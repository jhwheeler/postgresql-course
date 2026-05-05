-- Find users who started an exam in the last 7 days but never answered a question.
select
  u.id as user_id,
  u.username as username,
  array_agg(ue.id) as user_exam_ids,
  count(*) as abandoned_exam_count
from
  users u
  join user_exams ue on u.id = ue.user_id
  left join user_exam_answers uea on ue.id = uea.user_exam_id
    and (uea.answer_id is not null
      or uea.answer_text is not null)
where
  uea.id is null
  and ue.created_at > now() - interval '7 days'
group by
  u.id;

