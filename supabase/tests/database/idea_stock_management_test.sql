begin;

set local search_path = extensions, public, pg_catalog;

select plan(51);

select has_function(
  'public',
  'delete_idea',
  array['uuid', 'uuid', 'uuid', 'integer'],
  'delete_idea exists with the server command signature'
);

select function_returns(
  'public',
  'delete_idea',
  array['uuid', 'uuid', 'uuid', 'integer'],
  'integer',
  'delete_idea returns the next state version'
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
      'public.delete_idea(uuid,uuid,uuid,integer)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute delete_idea'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.delete_idea(uuid,uuid,uuid,integer)',
    'EXECUTE'
  ),
  'anon cannot execute delete_idea'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.delete_idea(uuid,uuid,uuid,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute delete_idea'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.delete_idea(uuid,uuid,uuid,integer)',
    'EXECUTE'
  ),
  'service_role can execute delete_idea'
);

select ok(
  (
    select function_row.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc as function_row
    where function_row.oid =
      'public.delete_idea(uuid,uuid,uuid,integer)'::regprocedure
  ),
  'delete_idea fixes an empty search_path'
);

select has_function(
  'public',
  'reorder_idea_stock',
  array['uuid', 'uuid', 'uuid[]', 'integer'],
  'reorder_idea_stock exists with the server command signature'
);

select function_returns(
  'public',
  'reorder_idea_stock',
  array['uuid', 'uuid', 'uuid[]', 'integer'],
  'integer',
  'reorder_idea_stock returns the next state version'
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
      'public.reorder_idea_stock(uuid,uuid,uuid[],integer)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute reorder_idea_stock'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.reorder_idea_stock(uuid,uuid,uuid[],integer)',
    'EXECUTE'
  ),
  'anon cannot execute reorder_idea_stock'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.reorder_idea_stock(uuid,uuid,uuid[],integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute reorder_idea_stock'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.reorder_idea_stock(uuid,uuid,uuid[],integer)',
    'EXECUTE'
  ),
  'service_role can execute reorder_idea_stock'
);

select ok(
  (
    select function_row.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc as function_row
    where function_row.oid =
      'public.reorder_idea_stock(uuid,uuid,uuid[],integer)'::regprocedure
  ),
  'reorder_idea_stock fixes an empty search_path'
);

create temporary table idea_fixture (
  fixture_name text not null,
  ordinal integer not null,
  idea_id uuid not null,
  primary key (fixture_name, ordinal)
);

create function pg_temp.add_ideas(
  fixture_name text,
  actor_user_id uuid,
  idea_count integer
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  target_run_id uuid;
  item_number integer;
  created_idea_id uuid;
begin
  select id into target_run_id
  from public.game_runs
  where user_id = actor_user_id;

  for item_number in 1..idea_count loop
    created_idea_id := public.commit_create_idea(
      actor_user_id,
      target_run_id,
      fixture_name || ' idea ' || item_number,
      null,
      item_number - 1,
      75::smallint,
      'completed',
      'be020-test-model',
      'be020-v1'
    );
    insert into pg_temp.idea_fixture (fixture_name, ordinal, idea_id)
    values (fixture_name, item_number, created_idea_id);
  end loop;
end;
$$;

insert into auth.users (id)
select ('e0200000-0000-4000-8000-' || pg_catalog.lpad(item::text, 12, '0'))::uuid
from pg_catalog.generate_series(1, 9) as item;

do $$
declare
  item integer;
  actor_user_id uuid;
begin
  for item in 1..9 loop
    actor_user_id := (
      'e0200000-0000-4000-8000-' || pg_catalog.lpad(item::text, 12, '0')
    )::uuid;
    perform public.commit_start_game(
      actor_user_id,
      'BE-020 ' || item,
      'mainstream',
      null
    );
  end loop;
end;
$$;

select pg_temp.add_ideas(
  'delete',
  'e0200000-0000-4000-8000-000000000001',
  3
);

select lives_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 3)',
    'e0200000-0000-4000-8000-000000000001',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000001'),
    (select idea_id from idea_fixture
      where fixture_name = 'delete' and ordinal = 2)
  ),
  'a pending player idea can be soft-deleted'
);

select is(
  (
    select jsonb_build_array(
      idea.id is not null,
      idea.created_week,
      idea.deleted_at is not null
    )
    from public.player_ideas as idea
    where idea.id = (
      select idea_id from idea_fixture
      where fixture_name = 'delete' and ordinal = 2
    )
  ),
  '[true,1,true]'::jsonb,
  'the idea source remains with its original created_week and deleted_at set'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.idea_evaluations
    where idea_id = (
      select idea_id from idea_fixture
      where fixture_name = 'delete' and ordinal = 2
    )
  ),
  1,
  'the deleted idea evaluation remains stored'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.idea_queue_entries
    where idea_id = (
      select idea_id from idea_fixture
      where fixture_name = 'delete' and ordinal = 2
    )
  ),
  0,
  'only the deleted idea queue row is removed'
);

select is(
  (
    select jsonb_agg(position order by position)
    from public.idea_queue_entries
    where run_id = (
      select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000001'
    )
  ),
  '[1,2]'::jsonb,
  'queue positions are compacted to a one-based sequence'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.player_ideas
    where run_id = (
      select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000001'
    )
      and created_week = 1
  ),
  3,
  'soft deletion does not restore the weekly creation slot'
);

select is(
  (
    select state_version
    from public.run_state
    where run_id = (
      select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000001'
    )
  ),
  4,
  'successful deletion increments state_version exactly once'
);

select throws_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 4)',
    'e0200000-0000-4000-8000-000000000001',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000001'),
    (select idea_id from idea_fixture
      where fixture_name = 'delete' and ordinal = 2)
  ),
  'P0001',
  'DELETE_IDEA_IDEA_ALREADY_DELETED',
  'a deleted idea cannot be deleted again'
);

select is(
  (
    select state_version
    from public.run_state
    where run_id = (
      select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000001'
    )
  ),
  4,
  'failed repeated deletion does not increment state_version'
);

select pg_temp.add_ideas(
  'owner',
  'e0200000-0000-4000-8000-000000000002',
  1
);
select pg_temp.add_ideas(
  'other',
  'e0200000-0000-4000-8000-000000000003',
  1
);

select throws_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 1)',
    'e0200000-0000-4000-8000-000000000002',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000002'),
    (select idea_id from idea_fixture
      where fixture_name = 'other' and ordinal = 1)
  ),
  'P0001',
  'DELETE_IDEA_IDEA_NOT_FOUND',
  'an idea from another run is hidden as not found'
);

select is(
  (
    select deleted_at
    from public.player_ideas
    where id = (
      select idea_id from idea_fixture
      where fixture_name = 'other' and ordinal = 1
    )
  ),
  null::timestamptz,
  'the other run idea remains unchanged'
);

select throws_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 0)',
    'e0200000-0000-4000-8000-000000000002',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000002'),
    (select idea_id from idea_fixture
      where fixture_name = 'owner' and ordinal = 1)
  ),
  'P0001',
  'DELETE_IDEA_STALE_STATE',
  'stale deletion is rejected'
);

select pg_temp.add_ideas(
  'unavailable',
  'e0200000-0000-4000-8000-000000000004',
  1
);

update public.run_state
set current_week = 2
where run_id = (
  select id from public.game_runs
  where user_id = 'e0200000-0000-4000-8000-000000000004'
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
  game_run.id,
  health_rule.id,
  1,
  1,
  2,
  2
from public.game_runs as game_run
join public.health_risk_rules as health_rule
  on health_rule.rule_set_id = game_run.rule_set_id
where game_run.user_id = 'e0200000-0000-4000-8000-000000000004'
limit 1;

select throws_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 1)',
    'e0200000-0000-4000-8000-000000000004',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000004'),
    (select idea_id from idea_fixture
      where fixture_name = 'unavailable' and ordinal = 1)
  ),
  'P0001',
  'DELETE_IDEA_ACTIVITY_UNAVAILABLE',
  'deletion is rejected during an activity-unavailable week'
);

select is(
  (
    select jsonb_build_array(idea.deleted_at, state.state_version, queue.position)
    from public.player_ideas as idea
    join public.run_state as state on state.run_id = idea.run_id
    join public.idea_queue_entries as queue on queue.idea_id = idea.id
    where idea.id = (
      select idea_id from idea_fixture
      where fixture_name = 'unavailable' and ordinal = 1
    )
  ),
  '[null,1,1]'::jsonb,
  'activity-unavailable rejection leaves the idea, queue, and version unchanged'
);

select pg_temp.add_ideas(
  'posted',
  'e0200000-0000-4000-8000-000000000005',
  1
);

delete from public.idea_queue_entries
where idea_id = (
  select idea_id from idea_fixture
  where fixture_name = 'posted' and ordinal = 1
);
set local session_replication_role = replica;
insert into public.videos (
  week_result_id,
  sequence_number,
  player_idea_id,
  title_snapshot
)
values (
  'e0200000-0000-4000-8000-999999999999',
  1,
  (select idea_id from idea_fixture
    where fixture_name = 'posted' and ordinal = 1),
  'Posted idea'
);
set local session_replication_role = origin;

select throws_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 1)',
    'e0200000-0000-4000-8000-000000000005',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000005'),
    (select idea_id from idea_fixture
      where fixture_name = 'posted' and ordinal = 1)
  ),
  'P0001',
  'DELETE_IDEA_IDEA_ALREADY_POSTED',
  'a posted idea cannot be deleted'
);

select pg_temp.add_ideas(
  'not-playing',
  'e0200000-0000-4000-8000-000000000006',
  1
);
update public.game_runs
set status = 'stage_cleared'
where user_id = 'e0200000-0000-4000-8000-000000000006';

select throws_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 1)',
    'e0200000-0000-4000-8000-000000000006',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000006'),
    (select idea_id from idea_fixture
      where fixture_name = 'not-playing' and ordinal = 1)
  ),
  'P0001',
  'DELETE_IDEA_RUN_NOT_PLAYABLE',
  'deletion requires a playing run'
);

select throws_ok(
  format(
    'select public.delete_idea(%L, %L, %L, 1)',
    'e0200000-0000-4000-8000-000000000003',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000002'),
    (select idea_id from idea_fixture
      where fixture_name = 'owner' and ordinal = 1)
  ),
  'P0001',
  'DELETE_IDEA_FORBIDDEN',
  'deletion rejects a non-owner of the requested run'
);

select throws_ok(
  $$select public.delete_idea(
    'e0200000-0000-4000-8000-000000000001',
    'e0200000-0000-4000-8000-999999999998',
    'e0200000-0000-4000-8000-999999999997',
    0
  )$$,
  'P0001',
  'DELETE_IDEA_RUN_NOT_FOUND',
  'deletion rejects a missing run'
);

select pg_temp.add_ideas(
  'reorder',
  'e0200000-0000-4000-8000-000000000007',
  3
);

select lives_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L]::uuid[], 3)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 3),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1)
  ),
  'a complete reversed order is applied without unique collisions'
);

select is(
  (
    select jsonb_agg(fixture.ordinal order by queue.position)
    from public.idea_queue_entries as queue
    join idea_fixture as fixture on fixture.idea_id = queue.idea_id
    where fixture.fixture_name = 'reorder'
  ),
  '[3,2,1]'::jsonb,
  'the requested order is reflected as positions one through three'
);

select is(
  (
    select state_version
    from public.run_state
    where run_id = (
      select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'
    )
  ),
  4,
  'successful reorder increments state_version exactly once'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L]::uuid[], 4)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 3)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER',
  'duplicate IDs are rejected'
);

select is(
  (
    select jsonb_agg(fixture.ordinal order by queue.position)
    from public.idea_queue_entries as queue
    join idea_fixture as fixture on fixture.idea_id = queue.idea_id
    where fixture.fixture_name = 'reorder'
  ),
  '[3,2,1]'::jsonb,
  'a rejected reorder does not partially change queue positions'
);

select is(
  (
    select state_version
    from public.run_state
    where run_id = (
      select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'
    )
  ),
  4,
  'a rejected reorder does not increment state_version'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L]::uuid[], 4)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER',
  'a missing ID is rejected'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L,%L]::uuid[], 4)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 3),
    'e0200000-0000-4000-8000-999999999996'
  ),
  'P0001',
  'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER',
  'an extra ID is rejected'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L]::uuid[], 4)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2),
    (select idea_id from idea_fixture
      where fixture_name = 'other' and ordinal = 1)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER',
  'an ID from another run is rejected without exposing its state'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L]::uuid[], 4)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2),
    (select idea_id from idea_fixture
      where fixture_name = 'delete' and ordinal = 2)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER',
  'a deleted idea ID is rejected'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L]::uuid[], 4)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2),
    (select idea_id from idea_fixture
      where fixture_name = 'posted' and ordinal = 1)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER',
  'a posted idea ID is rejected'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L]::uuid[], 1)',
    'e0200000-0000-4000-8000-000000000004',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000004'),
    (select idea_id from idea_fixture
      where fixture_name = 'unavailable' and ordinal = 1)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_ACTIVITY_UNAVAILABLE',
  'reorder is rejected during an activity-unavailable week'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L]::uuid[], 3)',
    'e0200000-0000-4000-8000-000000000007',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 3)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_STALE_STATE',
  'stale reorder is rejected'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L]::uuid[], 1)',
    'e0200000-0000-4000-8000-000000000006',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000006'),
    (select idea_id from idea_fixture
      where fixture_name = 'not-playing' and ordinal = 1)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_RUN_NOT_PLAYABLE',
  'reorder requires a playing run'
);

select throws_ok(
  format(
    'select public.reorder_idea_stock(%L, %L, ARRAY[%L,%L,%L]::uuid[], 4)',
    'e0200000-0000-4000-8000-000000000003',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000007'),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 1),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 2),
    (select idea_id from idea_fixture
      where fixture_name = 'reorder' and ordinal = 3)
  ),
  'P0001',
  'REORDER_IDEA_STOCK_FORBIDDEN',
  'reorder rejects a non-owner of the requested run'
);

select throws_ok(
  $$select public.reorder_idea_stock(
    'e0200000-0000-4000-8000-000000000001',
    'e0200000-0000-4000-8000-999999999998',
    array[]::uuid[],
    0
  )$$,
  'P0001',
  'REORDER_IDEA_STOCK_RUN_NOT_FOUND',
  'reorder rejects a missing run'
);

select lives_ok(
  $$select public.reorder_idea_stock(
    'e0200000-0000-4000-8000-000000000008',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000008'),
    array[]::uuid[],
    0
  )$$,
  'an empty complete order is valid for empty stock'
);

select is(
  (
    select state_version
    from public.run_state
    where run_id = (
      select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000008'
    )
  ),
  1,
  'successful empty reorder increments state_version once'
);

select throws_ok(
  $$select public.reorder_idea_stock(
    'e0200000-0000-4000-8000-000000000008',
    (select id from public.game_runs
      where user_id = 'e0200000-0000-4000-8000-000000000008'),
    null,
    1
  )$$,
  'P0001',
  'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER',
  'a null order is rejected'
);

select * from finish();

rollback;
