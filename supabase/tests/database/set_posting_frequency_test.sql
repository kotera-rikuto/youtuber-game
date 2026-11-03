begin;

set local search_path = extensions, public, pg_catalog;

select plan(27);

select has_function(
  'public',
  'set_posting_frequency',
  array['uuid', 'uuid', 'integer', 'integer'],
  'set_posting_frequency exists with the server command signature'
);

select function_returns(
  'public',
  'set_posting_frequency',
  array['uuid', 'uuid', 'integer', 'integer'],
  'jsonb',
  'set_posting_frequency returns a compact commit result'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function_row
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_row.proacl,
        pg_catalog.acldefault('f', function_row.proowner)
      )
    ) as privilege
    where function_row.oid =
      'public.set_posting_frequency(uuid,uuid,integer,integer)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute set_posting_frequency'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.set_posting_frequency(uuid,uuid,integer,integer)',
    'EXECUTE'
  ),
  'anon cannot execute set_posting_frequency'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.set_posting_frequency(uuid,uuid,integer,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute set_posting_frequency directly'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.set_posting_frequency(uuid,uuid,integer,integer)',
    'EXECUTE'
  ),
  'service_role can execute set_posting_frequency'
);

select ok(
  (
    select function_row.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc as function_row
    where function_row.oid =
      'public.set_posting_frequency(uuid,uuid,integer,integer)'::regprocedure
  ),
  'set_posting_frequency fixes an empty search_path'
);

insert into auth.users (id)
values
  ('e2100000-0000-4000-8000-000000000001'),
  ('e2100000-0000-4000-8000-000000000002'),
  ('e2100000-0000-4000-8000-000000000003'),
  ('e2100000-0000-4000-8000-000000000004'),
  ('e2100000-0000-4000-8000-000000000005'),
  ('e2100000-0000-4000-8000-000000000006'),
  ('e2100000-0000-4000-8000-000000000007');

do $$
declare
  actor_user_id uuid;
begin
  foreach actor_user_id in array array[
    'e2100000-0000-4000-8000-000000000001'::uuid,
    'e2100000-0000-4000-8000-000000000002'::uuid,
    'e2100000-0000-4000-8000-000000000004'::uuid,
    'e2100000-0000-4000-8000-000000000005'::uuid
  ]
  loop
    perform public.commit_start_game(
      actor_user_id,
      'BE-021 ' || actor_user_id::text,
      'mainstream',
      null
    );
  end loop;
end;
$$;

select is(
  public.set_posting_frequency(
    'e2100000-0000-4000-8000-000000000001',
    (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000001'),
    1,
    0
  ),
  '{"videosPerWeek": 1, "nextStateVersion": 1}'::jsonb,
  'one video per week can be selected'
);

select is(
  public.set_posting_frequency(
    'e2100000-0000-4000-8000-000000000001',
    (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000001'),
    3,
    1
  ),
  '{"videosPerWeek": 3, "nextStateVersion": 2}'::jsonb,
  'three videos per week can be selected'
);

select is(
  public.set_posting_frequency(
    'e2100000-0000-4000-8000-000000000001',
    (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000001'),
    7,
    2
  ),
  '{"videosPerWeek": 7, "nextStateVersion": 3}'::jsonb,
  'seven videos per week can be selected'
);

select is(
  (
    select pg_catalog.jsonb_build_array(frequency_rule.videos_per_week, state.state_version)
    from public.run_state as state
    join public.game_runs as game_run on game_run.id = state.run_id
    join public.posting_frequency_rules as frequency_rule
      on frequency_rule.id = state.posting_frequency_rule_id
    where game_run.user_id = 'e2100000-0000-4000-8000-000000000001'
  ),
  '[7, 3]'::jsonb,
  'the frequency rule and state version are updated together'
);

insert into public.rule_sets (version)
values ('be021-alternate-draft');

insert into public.posting_frequency_rules (
  rule_set_id,
  videos_per_week,
  view_multiplier,
  energy_cost,
  ability_points_awarded
)
select id, 7, 9.9, 99, 99
from public.rule_sets
where version = 'be021-alternate-draft';

select ok(
  (
    select frequency_rule.rule_set_id = game_run.rule_set_id
      and frequency_rule.id <> alternate_rule.id
    from public.run_state as state
    join public.game_runs as game_run on game_run.id = state.run_id
    join public.posting_frequency_rules as frequency_rule
      on frequency_rule.id = state.posting_frequency_rule_id
    cross join public.posting_frequency_rules as alternate_rule
    join public.rule_sets as alternate_rule_set
      on alternate_rule_set.id = alternate_rule.rule_set_id
    where game_run.user_id = 'e2100000-0000-4000-8000-000000000001'
      and alternate_rule_set.version = 'be021-alternate-draft'
      and alternate_rule.videos_per_week = 7
  ),
  'the selected rule belongs to the game run rule set, not another rule set'
);

select public.commit_create_idea(
  'e2100000-0000-4000-8000-000000000001',
  (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000001'),
  'Frequency persistence check',
  null,
  3,
  75::smallint,
  'completed',
  'test-model',
  'test-prompt-v1'
);

select is(
  (
    select pg_catalog.jsonb_build_array(frequency_rule.videos_per_week, state.state_version)
    from public.run_state as state
    join public.game_runs as game_run on game_run.id = state.run_id
    join public.posting_frequency_rules as frequency_rule
      on frequency_rule.id = state.posting_frequency_rule_id
    where game_run.user_id = 'e2100000-0000-4000-8000-000000000001'
  ),
  '[7, 4]'::jsonb,
  'the configured frequency survives unrelated state changes'
);

select is(
  public.set_posting_frequency(
    'e2100000-0000-4000-8000-000000000001',
    (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000001'),
    3,
    4
  ),
  '{"videosPerWeek": 3, "nextStateVersion": 5}'::jsonb,
  'the configured frequency remains until the next successful change'
);

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000002',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000002'),
      0,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_INVALID_POSTING_FREQUENCY',
  'zero videos per week is rejected'
);

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000002',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000002'),
      2,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_INVALID_POSTING_FREQUENCY',
  'two videos per week is rejected'
);

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000002',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000002'),
      5,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_INVALID_POSTING_FREQUENCY',
  'five videos per week is rejected'
);

select is(
  (
    select pg_catalog.jsonb_build_array(frequency_rule.videos_per_week, state.state_version)
    from public.run_state as state
    join public.game_runs as game_run on game_run.id = state.run_id
    join public.posting_frequency_rules as frequency_rule
      on frequency_rule.id = state.posting_frequency_rule_id
    where game_run.user_id = 'e2100000-0000-4000-8000-000000000002'
  ),
  '[1, 0]'::jsonb,
  'invalid frequencies update neither the rule nor the version'
);

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000003',
      '00000000-0000-4000-8000-000000000099',
      3,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_RUN_NOT_FOUND',
  'a missing run is rejected'
);

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000003',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000002'),
      3,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_FORBIDDEN',
  'a different owner is rejected'
);

update public.game_runs
set status = 'game_over', completed_at = pg_catalog.statement_timestamp()
where user_id = 'e2100000-0000-4000-8000-000000000004';

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000004',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000004'),
      3,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_RUN_NOT_PLAYABLE',
  'a finished game is rejected'
);

update public.run_state
set current_week = 2
where run_id = (
  select id from public.game_runs
  where user_id = 'e2100000-0000-4000-8000-000000000005'
);

insert into public.run_conditions (
  run_id,
  health_risk_rule_id,
  started_week,
  duration_weeks,
  unavailable_from_week,
  unavailable_through_week
)
select game_run.id, health_rule.id, 1, 1, 2, 2
from public.game_runs as game_run
join public.health_risk_rules as health_rule
  on health_rule.rule_set_id = game_run.rule_set_id
where game_run.user_id = 'e2100000-0000-4000-8000-000000000005'
limit 1;

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000005',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000005'),
      3,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_ACTIVITY_UNAVAILABLE',
  'a frequency change is rejected during an unavailable week'
);

select is(
  (
    select pg_catalog.jsonb_build_array(frequency_rule.videos_per_week, state.state_version)
    from public.run_state as state
    join public.game_runs as game_run on game_run.id = state.run_id
    join public.posting_frequency_rules as frequency_rule
      on frequency_rule.id = state.posting_frequency_rule_id
    where game_run.user_id = 'e2100000-0000-4000-8000-000000000005'
  ),
  '[1, 0]'::jsonb,
  'an unavailable-week rejection updates neither the rule nor the version'
);

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000002',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000002'),
      7,
      99
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_STALE_STATE',
  'a stale expected version is rejected'
);

select is(
  (
    select pg_catalog.jsonb_build_array(frequency_rule.videos_per_week, state.state_version)
    from public.run_state as state
    join public.game_runs as game_run on game_run.id = state.run_id
    join public.posting_frequency_rules as frequency_rule
      on frequency_rule.id = state.posting_frequency_rule_id
    where game_run.user_id = 'e2100000-0000-4000-8000-000000000002'
  ),
  '[1, 0]'::jsonb,
  'a stale-version rejection updates neither the rule nor the version'
);

insert into public.global_rules (
  rule_set_id,
  base_views_min,
  base_views_max,
  energy_max,
  unavailable_energy_recovery,
  ideas_per_week,
  idea_stock_max,
  flame_subscriber_loss_rate,
  flame_energy_loss,
  ban_flame_count,
  ad_revenue_per_view,
  system_idea_view_multiplier,
  system_idea_subscriber_conversion_rate
)
select id, 0, 1, 100, 10, 3, 30, 0.05, 20, 3, 0.2, 0.6, 0.02
from public.rule_sets
where version = 'be021-alternate-draft';

insert into public.channel_rules (
  rule_set_id,
  channel_type_code,
  view_multiplier,
  weekly_flame_probability
)
select id, 'mainstream', 1, 0.001
from public.rule_sets
where version = 'be021-alternate-draft';

insert into public.posting_frequency_rules (
  rule_set_id,
  videos_per_week,
  view_multiplier,
  energy_cost,
  ability_points_awarded
)
select id, 1, 1.2, 3, 3
from public.rule_sets
where version = 'be021-alternate-draft';

insert into public.game_runs (
  user_id,
  rule_set_id,
  channel_rule_id,
  channel_name
)
select
  'e2100000-0000-4000-8000-000000000006',
  rule_set.id,
  channel_rule.id,
  'BE-021 unavailable rule'
from public.rule_sets as rule_set
join public.channel_rules as channel_rule
  on channel_rule.rule_set_id = rule_set.id
where rule_set.version = 'be021-alternate-draft';

insert into public.run_state (run_id, posting_frequency_rule_id)
select game_run.id, frequency_rule.id
from public.game_runs as game_run
join public.posting_frequency_rules as frequency_rule
  on frequency_rule.rule_set_id = game_run.rule_set_id
where game_run.user_id = 'e2100000-0000-4000-8000-000000000006'
  and frequency_rule.videos_per_week = 1;

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000006',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000006'),
      3,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_RULE_UNAVAILABLE',
  'a frequency absent from the game run rule set is unavailable'
);

insert into public.game_runs (
  user_id,
  rule_set_id,
  channel_rule_id,
  channel_name
)
select
  'e2100000-0000-4000-8000-000000000007',
  rule_set.id,
  channel_rule.id,
  'BE-021 missing state'
from public.rule_sets as rule_set
join public.channel_rules as channel_rule
  on channel_rule.rule_set_id = rule_set.id
where rule_set.version = 'be021-alternate-draft';

select throws_ok(
  $$
    select public.set_posting_frequency(
      'e2100000-0000-4000-8000-000000000007',
      (select id from public.game_runs where user_id = 'e2100000-0000-4000-8000-000000000007'),
      1,
      0
    )
  $$,
  'P0001',
  'SET_POSTING_FREQUENCY_COMMIT_FAILED',
  'an inconsistent run without current state is reported as a commit failure'
);

select * from finish();

rollback;
