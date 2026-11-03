\set ON_ERROR_STOP on

begin;

insert into public.game_runs (
  id,
  user_id,
  rule_set_id,
  channel_rule_id,
  specialty_code,
  channel_name,
  status
)
select
  '00000000-0000-4000-8000-00000000b013',
  :'owner_user_id'::uuid,
  rule_set.id,
  channel_rule.id,
  null,
  'BE-013 Owner Channel',
  'playing'
from public.rule_sets as rule_set
join public.channel_rules as channel_rule
  on channel_rule.rule_set_id = rule_set.id
 and channel_rule.channel_type_code = 'mainstream'
where rule_set.status = 'active'
on conflict (id) do nothing;

insert into public.game_runs (
  id,
  user_id,
  rule_set_id,
  channel_rule_id,
  specialty_code,
  channel_name,
  status
)
select
  '00000000-0000-4000-8000-00000000b014',
  :'other_user_id'::uuid,
  rule_set.id,
  channel_rule.id,
  null,
  'BE-013 Other Channel',
  'playing'
from public.rule_sets as rule_set
join public.channel_rules as channel_rule
  on channel_rule.rule_set_id = rule_set.id
 and channel_rule.channel_type_code = 'mainstream'
where rule_set.status = 'active'
on conflict (id) do nothing;

insert into public.run_state (
  run_id,
  current_week,
  posting_frequency_rule_id,
  cash,
  energy,
  subscribers,
  cumulative_views,
  flame_count,
  state_version
)
select
  run.id,
  4,
  frequency.id,
  1000,
  80,
  30,
  220,
  0,
  2
from public.game_runs as run
join public.posting_frequency_rules as frequency
  on frequency.rule_set_id = run.rule_set_id
 and frequency.videos_per_week = 1
where run.id in (
  '00000000-0000-4000-8000-00000000b013',
  '00000000-0000-4000-8000-00000000b014'
)
on conflict (run_id) do nothing;

insert into public.run_abilities (run_id, ability_code, value)
select run.id, ability.code, 10
from public.game_runs as run
cross join public.ability_definitions as ability
where run.id in (
  '00000000-0000-4000-8000-00000000b013',
  '00000000-0000-4000-8000-00000000b014'
)
on conflict (run_id, ability_code) do nothing;

insert into public.run_goals (
  id,
  run_id,
  goal_rule_id,
  started_week,
  deadline_week,
  status
)
select
  case run.id
    when '00000000-0000-4000-8000-00000000b013' then '00000000-0000-4000-8000-00000000b113'::uuid
    else '00000000-0000-4000-8000-00000000b114'::uuid
  end,
  run.id,
  goal.id,
  1,
  156,
  'active'
from public.game_runs as run
join public.goal_rules as goal
  on goal.rule_set_id = run.rule_set_id
 and goal.stage_number = 1
where run.id in (
  '00000000-0000-4000-8000-00000000b013',
  '00000000-0000-4000-8000-00000000b014'
)
on conflict (id) do nothing;

insert into public.player_ideas (
  id,
  run_id,
  title,
  description,
  created_week
)
values
  (
    '00000000-0000-4000-8000-00000000c131',
    '00000000-0000-4000-8000-00000000b013',
    'Queue Second',
    null,
    4
  ),
  (
    '00000000-0000-4000-8000-00000000c132',
    '00000000-0000-4000-8000-00000000b013',
    'Queue First',
    'first item',
    4
  )
on conflict (id) do nothing;

insert into public.idea_queue_entries (idea_id, run_id, position)
values
  (
    '00000000-0000-4000-8000-00000000c131',
    '00000000-0000-4000-8000-00000000b013',
    2
  ),
  (
    '00000000-0000-4000-8000-00000000c132',
    '00000000-0000-4000-8000-00000000b013',
    1
  )
on conflict (idea_id) do nothing;

insert into public.run_conditions (
  id,
  run_id,
  health_risk_rule_id,
  started_week,
  duration_weeks,
  unavailable_from_week,
  unavailable_through_week
)
select
  '00000000-0000-4000-8000-00000000c013',
  run.id,
  health.id,
  1,
  2,
  2,
  3
from public.game_runs as run
join lateral (
  select id
  from public.health_risk_rules
  where rule_set_id = run.rule_set_id
  order by min_energy
  limit 1
) as health on true
where run.id = '00000000-0000-4000-8000-00000000b013'
on conflict (id) do nothing;

insert into public.advance_week_executions (
  idempotency_key,
  run_id,
  attempted_week,
  expected_state_version,
  outcome
)
values
  (
    '00000000-0000-4000-8000-00000000d132',
    '00000000-0000-4000-8000-00000000b013',
    2,
    0,
    'week_committed'
  ),
  (
    '00000000-0000-4000-8000-00000000d133',
    '00000000-0000-4000-8000-00000000b013',
    3,
    1,
    'week_committed'
  )
on conflict (idempotency_key) do nothing;

insert into public.week_results (
  id,
  execution_id,
  run_id,
  week_number,
  weekly_action_id,
  posting_frequency_rule_id,
  views_before_event,
  final_views,
  subscribers_before,
  max_subscribers_during_week,
  subscribers_after,
  energy_before,
  energy_after,
  cash_before,
  cash_after,
  ad_revenue,
  flame_count_after,
  run_status_after,
  state_version_after
)
values
  (
    '00000000-0000-4000-8000-00000000e132',
    '00000000-0000-4000-8000-00000000d132',
    '00000000-0000-4000-8000-00000000b013',
    2,
    null,
    null,
    0,
    0,
    20,
    20,
    20,
    70,
    80,
    1000,
    1000,
    0,
    0,
    'playing',
    1
  ),
  (
    '00000000-0000-4000-8000-00000000e133',
    '00000000-0000-4000-8000-00000000d133',
    '00000000-0000-4000-8000-00000000b013',
    3,
    null,
    null,
    0,
    0,
    20,
    20,
    20,
    80,
    90,
    1000,
    1000,
    0,
    0,
    'playing',
    2
  )
on conflict (id) do nothing;

commit;
