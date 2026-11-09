begin;

set local search_path = extensions, public, pg_catalog;

select plan(27);

select has_function(
  'public',
  'abandon_game',
  array['uuid', 'uuid', 'integer'],
  'abandon_game exists with the server command signature'
);

select has_function(
  'public',
  'rename_channel',
  array['uuid', 'uuid', 'text', 'integer'],
  'rename_channel exists with the server command signature'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.abandon_game(uuid,uuid,integer)',
    'EXECUTE'
  ),
  'anon cannot execute abandon_game'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.abandon_game(uuid,uuid,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute abandon_game'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.abandon_game(uuid,uuid,integer)',
    'EXECUTE'
  ),
  'service_role can execute abandon_game'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.rename_channel(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'anon cannot execute rename_channel'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.rename_channel(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute rename_channel'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.rename_channel(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'service_role can execute rename_channel'
);

insert into auth.users (id)
values
  ('f1600000-0000-4000-8000-000000000001'),
  ('f1600000-0000-4000-8000-000000000002'),
  ('f1600000-0000-4000-8000-000000000003'),
  ('f1600000-0000-4000-8000-000000000004');

do $$
declare
  ignored_run_id uuid;
begin
  select public.commit_start_game(
    'f1600000-0000-4000-8000-000000000001', '  Management test  ', 'mainstream', null
  ) into ignored_run_id;
  select public.commit_start_game(
    'f1600000-0000-4000-8000-000000000002', 'Stage cleared test', 'mainstream', null
  ) into ignored_run_id;
  select public.commit_start_game(
    'f1600000-0000-4000-8000-000000000003', 'Rename test', 'specialized', 'gaming'
  ) into ignored_run_id;
end;
$$;

update public.game_runs
set status = 'stage_cleared'
where user_id = 'f1600000-0000-4000-8000-000000000002';

select is(
  public.rename_channel(
    'f1600000-0000-4000-8000-000000000003',
    (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000003'),
    '  Renamed  ',
    0
  ),
  '{"channelName": "Renamed", "nextStateVersion": 1}'::jsonb,
  'rename_channel trims the name and increments state_version once'
);

select is(
  (select channel_name from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000003'),
  'Renamed',
  'rename_channel changes only the channel name'
);

select is(
  (select state_version from public.run_state where run_id = (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000003')),
  1,
  'rename_channel advances state_version by one'
);

select throws_ok(
  $$select public.rename_channel('f1600000-0000-4000-8000-000000000003', (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000003'), '   ', 1)$$,
  'P0001',
  'RENAME_CHANNEL_INVALID_CHANNEL_NAME',
  'blank channel names are rejected'
);

select throws_ok(
  $$select public.rename_channel('f1600000-0000-4000-8000-000000000002', (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001'), 'forbidden', 0)$$,
  'P0001',
  'RENAME_CHANNEL_FORBIDDEN',
  'another user cannot rename a run'
);

select throws_ok(
  $$select public.rename_channel('f1600000-0000-4000-8000-000000000003', (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000003'), 'stale', 0)$$,
  'P0001',
  'RENAME_CHANNEL_STALE_STATE',
  'stale rename versions are rejected'
);

select is(
  public.abandon_game(
    'f1600000-0000-4000-8000-000000000001',
    (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001'),
    0
  ),
  '{"occurredWeek": 1}'::jsonb,
  'a playing run can be abandoned'
);

select is(
  (select status from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001'),
  'abandoned',
  'abandon_game updates the run status'
);

select ok(
  (select completed_at is not null from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001'),
  'abandon_game sets completed_at'
);

select is(
  (select count(*)::integer from public.game_terminations where run_id = (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001')),
  1,
  'abandon_game stores exactly one termination'
);

select is(
  (select reason from public.game_terminations where run_id = (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001')),
  'abandoned',
  'abandoned termination stores the abandoned reason'
);

select ok(
  (select execution_id is null and week_result_id is null and calculated_energy is null and calculated_flame_count is null
   from public.game_terminations
   where run_id = (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001')),
  'abandoned termination does not store week execution values'
);

select throws_ok(
  $$select public.abandon_game('f1600000-0000-4000-8000-000000000001', (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000001'), 0)$$,
  'P0001',
  'ABANDON_GAME_ALREADY_ABANDONED',
  'a run cannot be abandoned twice'
);

select throws_ok(
  $$select public.abandon_game('f1600000-0000-4000-8000-000000000002', (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000002'), 0)$$,
  'P0001',
  'ABANDON_GAME_FORBIDDEN',
  'another user cannot abandon a run'
);

select is(
  public.abandon_game(
    'f1600000-0000-4000-8000-000000000002',
    (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000002'),
    0
  ),
  '{"occurredWeek": 1}'::jsonb,
  'a stage-cleared run can be abandoned'
);

select is(
  (select count(*)::integer from public.game_terminations where reason = 'abandoned'),
  2,
  'each abandoned run has one termination'
);

select throws_ok(
  $$select public.abandon_game('f1600000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000004', 0)$$,
  'P0001',
  'ABANDON_GAME_RUN_NOT_FOUND',
  'missing runs use the stable not-found error'
);

select throws_ok(
  $$select public.abandon_game('f1600000-0000-4000-8000-000000000003', (select id from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000003'), 0)$$,
  'P0001',
  'ABANDON_GAME_STALE_STATE',
  'abandon rejects a stale state version without changing the run'
);

select is(
  (select status from public.game_runs where user_id = 'f1600000-0000-4000-8000-000000000003'),
  'playing',
  'failed abandon leaves the run active'
);

select * from finish();
rollback;
