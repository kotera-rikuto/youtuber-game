begin;

set local search_path = extensions, public, pg_catalog;

select plan(37);

select has_function(
  'public',
  'commit_start_game',
  array['uuid', 'text', 'text', 'text'],
  'commit_start_game exists with the server command signature'
);

select function_returns(
  'public',
  'commit_start_game',
  array['uuid', 'text', 'text', 'text'],
  'uuid',
  'commit_start_game returns the created run id'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name, display_order) order by display_order)
    from public.channel_types
  ),
  '[["mainstream","王道系",1],["specialized","特化系",2],["controversial","炎上系",3],["idol","アイドル系",4]]'::jsonb,
  'posting style display order is stored in the catalog'
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
    where function_row.oid = 'public.commit_start_game(uuid,text,text,text)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute commit_start_game'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.commit_start_game(uuid,text,text,text)',
    'EXECUTE'
  ),
  'anon cannot execute commit_start_game'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.commit_start_game(uuid,text,text,text)',
    'EXECUTE'
  ),
  'authenticated cannot execute commit_start_game'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.commit_start_game(uuid,text,text,text)',
    'EXECUTE'
  ),
  'service_role can execute commit_start_game'
);

insert into auth.users (id)
values
  ('d1500000-0000-4000-8000-000000000001'),
  ('d1500000-0000-4000-8000-000000000002'),
  ('d1500000-0000-4000-8000-000000000003'),
  ('d1500000-0000-4000-8000-000000000004'),
  ('d1500000-0000-4000-8000-000000000005'),
  ('d1500000-0000-4000-8000-000000000006'),
  ('d1500000-0000-4000-8000-000000000007');

select lives_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000001', '  Main Channel  ', 'mainstream', null)$$,
  'a mainstream game starts successfully'
);

select is(
  (select count(*)::integer from public.game_runs where user_id = 'd1500000-0000-4000-8000-000000000001'),
  1,
  'game start creates one game run'
);

select is(
  (
    select jsonb_build_array(
      game_run.channel_name,
      channel_rule.channel_type_code,
      game_run.specialty_code,
      game_run.status,
      rule_set.status
    )
    from public.game_runs as game_run
    join public.channel_rules as channel_rule on channel_rule.id = game_run.channel_rule_id
    join public.rule_sets as rule_set on rule_set.id = game_run.rule_set_id
    where game_run.user_id = 'd1500000-0000-4000-8000-000000000001'
  ),
  '["Main Channel","mainstream",null,"playing","active"]'::jsonb,
  'the run stores normalized selections and the active rule set'
);

select is(
  (
    select jsonb_build_array(
      run_state.current_week,
      posting_frequency.videos_per_week,
      run_state.cash,
      run_state.energy,
      run_state.subscribers,
      run_state.cumulative_views,
      run_state.flame_count,
      run_state.state_version
    )
    from public.run_state
    join public.game_runs on game_runs.id = run_state.run_id
    join public.posting_frequency_rules as posting_frequency
      on posting_frequency.id = run_state.posting_frequency_rule_id
    where game_runs.user_id = 'd1500000-0000-4000-8000-000000000001'
  ),
  '[1,1,100000,100,0,0,0,0]'::jsonb,
  'run state has the specified initial values and weekly posting rule'
);

select is(
  (
    select count(*)::integer
    from public.run_abilities
    join public.game_runs on game_runs.id = run_abilities.run_id
    where game_runs.user_id = 'd1500000-0000-4000-8000-000000000001'
  ),
  6,
  'game start creates all six abilities'
);

select ok(
  not exists (
    select 1
    from public.run_abilities
    join public.game_runs on game_runs.id = run_abilities.run_id
    where game_runs.user_id = 'd1500000-0000-4000-8000-000000000001'
      and run_abilities.value <> 10
  ),
  'all initial abilities equal ten'
);

select is(
  (
    select jsonb_build_array(
      goal_rule.stage_number,
      goal_rule.target_subscribers,
      run_goal.started_week,
      run_goal.deadline_week,
      run_goal.status
    )
    from public.run_goals as run_goal
    join public.game_runs on game_runs.id = run_goal.run_id
    join public.goal_rules as goal_rule on goal_rule.id = run_goal.goal_rule_id
    where game_runs.user_id = 'd1500000-0000-4000-8000-000000000001'
  ),
  '[1,100000,1,156,"active"]'::jsonb,
  'game start creates the stage-one goal from the active rules'
);

select is(
  (
    select count(*)::integer
    from public.run_equipment
    join public.game_runs on game_runs.id = run_equipment.run_id
    where game_runs.user_id = 'd1500000-0000-4000-8000-000000000001'
  ),
  0,
  'game start creates no equipment rows'
);

select is(
  (
    select count(*)::integer
    from public.player_ideas
    join public.game_runs on game_runs.id = player_ideas.run_id
    where game_runs.user_id = 'd1500000-0000-4000-8000-000000000001'
  ),
  0,
  'game start creates no player idea rows'
);

select is(
  (
    select
      (select count(*) from public.idea_queue_entries where run_id = game_run.id)
      + (select count(*) from public.system_idea_cycles where run_id = game_run.id)
    from public.game_runs as game_run
    where game_run.user_id = 'd1500000-0000-4000-8000-000000000001'
  )::integer,
  0,
  'game start creates no queued or generated idea stock rows'
);

select is(
  (
    select count(*)::integer
    from public.ability_point_grants
    join public.game_runs on game_runs.id = ability_point_grants.run_id
    where game_runs.user_id = 'd1500000-0000-4000-8000-000000000001'
  ),
  0,
  'game start creates no ability point grants'
);

select lives_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000002', 'Specialized Channel', 'specialized', 'gaming')$$,
  'a specialized game starts with an enabled specialty'
);

select is(
  (select specialty_code from public.game_runs where user_id = 'd1500000-0000-4000-8000-000000000002'),
  'gaming',
  'the specialized run stores its specialty'
);

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000003', 'Missing Specialty', 'specialized', null)$$,
  'P0001',
  'START_GAME_SPECIALTY_REQUIRED',
  'specialized game start requires a specialty'
);

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000003', 'Forbidden Specialty', 'mainstream', 'gaming')$$,
  'P0001',
  'START_GAME_SPECIALTY_NOT_ALLOWED',
  'non-specialized game start forbids a specialty'
);

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000003', 'Invalid Specialty', 'specialized', 'invalid')$$,
  'P0001',
  'START_GAME_SPECIALTY_NOT_ALLOWED',
  'game start rejects a specialty outside the active rule set'
);

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000003', 'Invalid Style', 'invalid', null)$$,
  'P0001',
  'START_GAME_VALIDATION_ERROR',
  'game start rejects an invalid posting style'
);

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000003', '   ', 'mainstream', null)$$,
  'P0001',
  'START_GAME_VALIDATION_ERROR',
  'game start rejects a blank channel name'
);

insert into public.ability_definitions (code, name, display_order)
values ('unexpected_start_ability', '開始失敗検証用', 99);

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000003', 'Rollback Check', 'mainstream', null)$$,
  'P0001',
  'START_GAME_RULES_UNAVAILABLE',
  'a rule inconsistency after initial inserts aborts game start'
);

delete from public.ability_definitions
where code = 'unexpected_start_ability';

select is(
  (select count(*)::integer from public.game_runs where user_id = 'd1500000-0000-4000-8000-000000000003'),
  0,
  'failed starts leave no game run behind'
);

select is(
  (
    select count(*)::integer
    from public.run_state
    where run_id in (
      select id from public.game_runs where user_id = 'd1500000-0000-4000-8000-000000000003'
    )
  ),
  0,
  'failed starts leave no partial initial state behind'
);

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000001', 'Second Run', 'idol', null)$$,
  'P0001',
  'START_GAME_ACTIVE_GAME_EXISTS',
  'the same user cannot start a second active game'
);

select is(
  (select count(*)::integer from public.game_runs where user_id = 'd1500000-0000-4000-8000-000000000001'),
  1,
  'a rejected second start preserves the original run only'
);

select lives_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000004', 'Other User', 'controversial', null)$$,
  'a different user can start independently'
);

select is(
  (
    select count(*)::integer
    from public.game_runs
    where status = 'playing'
      and user_id in (
        'd1500000-0000-4000-8000-000000000001',
        'd1500000-0000-4000-8000-000000000002',
        'd1500000-0000-4000-8000-000000000004'
      )
  ),
  3,
  'three different users have independent active games'
);

set local role authenticated;

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000006', 'Blocked Authenticated', 'mainstream', null)$$,
  '42501',
  null,
  'authenticated cannot invoke the server-only RPC directly'
);

reset role;
set local role anon;

select throws_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000007', 'Blocked Anon', 'mainstream', null)$$,
  '42501',
  null,
  'anon cannot invoke the server-only RPC directly'
);

reset role;
set local role service_role;

select lives_ok(
  $$select public.commit_start_game('d1500000-0000-4000-8000-000000000005', 'Trusted Server', 'idol', null)$$,
  'service_role can invoke the server-only RPC'
);

reset role;

select is(
  (select count(*)::integer from public.game_runs where user_id = 'd1500000-0000-4000-8000-000000000005'),
  1,
  'the trusted server call commits its game'
);

select is(
  (select count(*)::integer from public.game_runs where user_id in ('d1500000-0000-4000-8000-000000000006', 'd1500000-0000-4000-8000-000000000007')),
  0,
  'denied direct RPC calls create no games'
);

select * from finish();

rollback;
