begin;

set local search_path = extensions, public, pg_catalog;

select plan(33);

select has_function(
  'public',
  'select_weekly_main_action',
  array['uuid', 'uuid', 'text', 'integer'],
  'select_weekly_main_action exists with the server command signature'
);

select function_returns(
  'public',
  'select_weekly_main_action',
  array['uuid', 'uuid', 'text', 'integer'],
  'jsonb',
  'select_weekly_main_action returns a selection receipt'
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
      'public.select_weekly_main_action(uuid,uuid,text,integer)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute select_weekly_main_action'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.select_weekly_main_action(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'anon cannot execute select_weekly_main_action'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.select_weekly_main_action(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute select_weekly_main_action directly'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.select_weekly_main_action(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'service_role can execute select_weekly_main_action'
);

select ok(
  (
    select function_row.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc as function_row
    where function_row.oid =
      'public.select_weekly_main_action(uuid,uuid,text,integer)'::regprocedure
  ),
  'select_weekly_main_action fixes an empty search_path'
);

create function pg_temp.create_weekly_action_run(
  target_user_id uuid,
  target_run_id uuid,
  target_week integer default 1,
  target_version integer default 0,
  target_subscribers bigint default 0
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into auth.users (id) values (target_user_id);

  insert into public.game_runs (
    id,
    user_id,
    rule_set_id,
    channel_rule_id,
    channel_name
  ) values (
    target_run_id,
    target_user_id,
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'BE-024 test channel'
  );

  insert into public.run_state (
    run_id,
    current_week,
    posting_frequency_rule_id,
    subscribers,
    state_version
  ) values (
    target_run_id,
    target_week,
    '00000000-0000-4000-8100-000000001201',
    target_subscribers,
    target_version
  );
end;
$$;

create function pg_temp.unlock_action_feature(
  target_run_id uuid,
  target_feature_code text,
  unlocked_week integer,
  active_from_week integer
)
returns void
language sql
set search_path = ''
as $$
  insert into public.run_feature_unlocks (
    run_id,
    feature_rule_id,
    unlocked_week,
    active_from_week
  )
  select
    target_run_id,
    feature_rule.id,
    unlocked_week,
    active_from_week
  from public.feature_rules as feature_rule
  where feature_rule.rule_set_id = '00000000-0000-4000-8000-000000000001'
    and feature_rule.feature_code = target_feature_code;
$$;

create function pg_temp.add_weekly_action(
  target_run_id uuid,
  target_week integer,
  target_action_code text,
  is_locked boolean
)
returns void
language sql
set search_path = ''
as $$
  insert into public.weekly_actions (
    run_id,
    week_number,
    action_rule_id,
    selected_at,
    locked_at
  )
  select
    target_run_id,
    target_week,
    action_rule.id,
    pg_catalog.statement_timestamp() - interval '1 minute',
    case when is_locked then pg_catalog.statement_timestamp() else null end
  from public.action_rules as action_rule
  where action_rule.rule_set_id = '00000000-0000-4000-8000-000000000001'
    and action_rule.action_code = target_action_code;
$$;

select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000001',
  'd2400000-0000-4000-8100-000000000001'
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000002',
  'd2400000-0000-4000-8100-000000000002'
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000003',
  'd2400000-0000-4000-8100-000000000003'
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000004',
  'd2400000-0000-4000-8100-000000000004'
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000005',
  'd2400000-0000-4000-8100-000000000005'
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000006',
  'd2400000-0000-4000-8100-000000000006',
  3,
  0,
  0
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000007',
  'd2400000-0000-4000-8100-000000000007'
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000008',
  'd2400000-0000-4000-8100-000000000008',
  2
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000009',
  'd2400000-0000-4000-8100-000000000009',
  4
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000010',
  'd2400000-0000-4000-8100-000000000010',
  2
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000011',
  'd2400000-0000-4000-8100-000000000011'
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000012',
  'd2400000-0000-4000-8100-000000000012',
  2
);
select pg_temp.create_weekly_action_run(
  'd2400000-0000-4000-8000-000000000013',
  'd2400000-0000-4000-8100-000000000013'
);

select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000001',
    'd2400000-0000-4000-8100-000000000001',
    'part_time_job',
    0
  ),
  '{"action":"part_time_job","weekNumber":1,"stateVersion":1}'::jsonb,
  'part-time work can be selected'
);

select is(
  (
    select pg_catalog.jsonb_build_array(
      state.cash,
      state.energy,
      state.state_version,
      (select pg_catalog.count(*) from public.weekly_actions where run_id = state.run_id),
      action_rule.action_code
    )
    from public.run_state as state
    join public.weekly_actions as weekly_action
      on weekly_action.run_id = state.run_id
      and weekly_action.week_number = state.current_week
    join public.action_rules as action_rule
      on action_rule.id = weekly_action.action_rule_id
    where state.run_id = 'd2400000-0000-4000-8100-000000000001'
  ),
  '[100000,100,1,1,"part_time_job"]'::jsonb,
  'selection stores one row and increments only state_version'
);

select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000002',
    'd2400000-0000-4000-8100-000000000002',
    'rest',
    0
  ),
  '{"action":"rest","weekNumber":1,"stateVersion":1}'::jsonb,
  'rest can be selected'
);

select pg_temp.unlock_action_feature(
  'd2400000-0000-4000-8100-000000000003',
  'collaboration',
  1,
  1
);
select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000003',
    'd2400000-0000-4000-8100-000000000003',
    'collaboration',
    0
  ),
  '{"action":"collaboration","weekNumber":1,"stateVersion":1}'::jsonb,
  'an active collaboration unlock permits selection'
);

select pg_temp.unlock_action_feature(
  'd2400000-0000-4000-8100-000000000004',
  'sponsorship',
  1,
  1
);
select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000004',
    'd2400000-0000-4000-8100-000000000004',
    'sponsorship',
    0
  ),
  '{"action":"sponsorship","weekNumber":1,"stateVersion":1}'::jsonb,
  'an active sponsorship unlock permits selection'
);

select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000005',
    'd2400000-0000-4000-8100-000000000005',
    'collaboration',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_FEATURE_LOCKED',
  'collaboration is rejected before its persistent unlock exists'
);

select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000005',
    'd2400000-0000-4000-8100-000000000005',
    'sponsorship',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_FEATURE_LOCKED',
  'sponsorship is rejected before its persistent unlock exists'
);

select is(
  (select state_version from public.run_state where run_id = 'd2400000-0000-4000-8100-000000000005'),
  0,
  'feature validation failures do not increment state_version'
);

select pg_temp.unlock_action_feature(
  'd2400000-0000-4000-8100-000000000006',
  'collaboration',
  1,
  2
);
select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000006',
    'd2400000-0000-4000-8100-000000000006',
    'collaboration',
    0
  ),
  '{"action":"collaboration","weekNumber":3,"stateVersion":1}'::jsonb,
  'persistent history permits collaboration after subscribers fall to zero'
);

select pg_temp.unlock_action_feature(
  'd2400000-0000-4000-8100-000000000007',
  'collaboration',
  1,
  2
);
select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000007',
    'd2400000-0000-4000-8100-000000000007',
    'collaboration',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_FEATURE_LOCKED',
  'an unlock cannot be used before active_from_week'
);

select pg_temp.unlock_action_feature(
  'd2400000-0000-4000-8100-000000000008',
  'collaboration',
  1,
  1
);
select pg_temp.add_weekly_action(
  'd2400000-0000-4000-8100-000000000008',
  1,
  'collaboration',
  true
);
select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000008',
    'd2400000-0000-4000-8100-000000000008',
    'collaboration',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_ACTION_ON_COOLDOWN',
  'collaboration is on cooldown in the week after use'
);

select is(
  (select state_version from public.run_state where run_id = 'd2400000-0000-4000-8100-000000000008'),
  0,
  'a cooldown failure does not increment state_version'
);

update public.run_state
set current_week = 3
where run_id = 'd2400000-0000-4000-8100-000000000008';
select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000008',
    'd2400000-0000-4000-8100-000000000008',
    'collaboration',
    0
  ),
  '{"action":"collaboration","weekNumber":3,"stateVersion":1}'::jsonb,
  'collaboration becomes available at the cooldown boundary'
);

select pg_temp.unlock_action_feature(
  'd2400000-0000-4000-8100-000000000009',
  'sponsorship',
  1,
  1
);
select pg_temp.add_weekly_action(
  'd2400000-0000-4000-8100-000000000009',
  1,
  'sponsorship',
  true
);
select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000009',
    'd2400000-0000-4000-8100-000000000009',
    'sponsorship',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_ACTION_ON_COOLDOWN',
  'sponsorship remains on cooldown through week N+3'
);

update public.run_state
set current_week = 5
where run_id = 'd2400000-0000-4000-8100-000000000009';
select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000009',
    'd2400000-0000-4000-8100-000000000009',
    'sponsorship',
    0
  ),
  '{"action":"sponsorship","weekNumber":5,"stateVersion":1}'::jsonb,
  'sponsorship becomes available at the cooldown boundary'
);

select pg_temp.unlock_action_feature(
  'd2400000-0000-4000-8100-000000000010',
  'collaboration',
  1,
  1
);
select pg_temp.add_weekly_action(
  'd2400000-0000-4000-8100-000000000010',
  1,
  'collaboration',
  false
);
select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000010',
    'd2400000-0000-4000-8100-000000000010',
    'collaboration',
    0
  ),
  '{"action":"collaboration","weekNumber":2,"stateVersion":1}'::jsonb,
  'an uncommitted past selection does not start cooldown'
);

select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000011',
    'd2400000-0000-4000-8100-000000000011',
    'part_time_job',
    0
  ),
  '{"action":"part_time_job","weekNumber":1,"stateVersion":1}'::jsonb,
  'the first current-week selection succeeds'
);

update public.weekly_actions
set selected_at = '2020-01-01 00:00:00+00'
where run_id = 'd2400000-0000-4000-8100-000000000011';

select is(
  public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000011',
    'd2400000-0000-4000-8100-000000000011',
    'rest',
    1
  ),
  '{"action":"rest","weekNumber":1,"stateVersion":2}'::jsonb,
  'an unlocked current-week selection can be replaced'
);

select is(
  (
    select pg_catalog.jsonb_build_array(
      pg_catalog.count(*),
      pg_catalog.max(action_rule.action_code),
      pg_catalog.bool_and(weekly_action.selected_at > '2020-01-01 00:00:00+00'),
      pg_catalog.max(state.state_version)
    )
    from public.weekly_actions as weekly_action
    join public.action_rules as action_rule on action_rule.id = weekly_action.action_rule_id
    join public.run_state as state on state.run_id = weekly_action.run_id
    where weekly_action.run_id = 'd2400000-0000-4000-8100-000000000011'
  ),
  '[1,"rest",true,2]'::jsonb,
  'replacement keeps one row and refreshes action_rule_id and selected_at'
);

update public.weekly_actions
set locked_at = pg_catalog.statement_timestamp()
where run_id = 'd2400000-0000-4000-8100-000000000011';
select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000011',
    'd2400000-0000-4000-8100-000000000011',
    'part_time_job',
    2
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_WEEK_ALREADY_COMMITTED',
  'a locked weekly action cannot be changed'
);

insert into public.run_conditions (
  run_id,
  health_risk_rule_id,
  started_week,
  duration_weeks,
  unavailable_from_week,
  unavailable_through_week
)
select
  'd2400000-0000-4000-8100-000000000012',
  health_rule.id,
  1,
  1,
  2,
  2
from public.health_risk_rules as health_rule
where health_rule.rule_set_id = '00000000-0000-4000-8000-000000000001'
order by health_rule.min_energy
limit 1;

select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000012',
    'd2400000-0000-4000-8100-000000000012',
    'rest',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_ACTIVITY_UNAVAILABLE',
  'activity-unavailable weeks reject main-action selection'
);

select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000001',
    'd2400000-0000-4000-8100-000000000013',
    'rest',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_FORBIDDEN',
  'another owner cannot select an action'
);

select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000013',
    'd2400000-0000-4000-8100-000000000013',
    'rest',
    1
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_STALE_STATE',
  'a stale expected version is rejected'
);

select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000013',
    'd2400000-0000-4000-8100-000000000013',
    'study',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_INVALID_ACTION',
  'an action outside the four supported codes is rejected'
);

select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000013',
    'd2400000-0000-4000-8100-000000000099',
    'rest',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_FOUND',
  'a missing game run is rejected'
);

update public.game_runs
set status = 'stage_cleared'
where id = 'd2400000-0000-4000-8100-000000000013';
select throws_ok(
  $$select public.select_weekly_main_action(
    'd2400000-0000-4000-8000-000000000013',
    'd2400000-0000-4000-8100-000000000013',
    'rest',
    0
  )$$,
  'P0001',
  'SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_PLAYABLE',
  'a non-playing game run is rejected'
);

select * from finish();
rollback;
