begin;

set local search_path = extensions, public, pg_catalog;

select plan(41);

create function pg_temp.create_ability_run(
  target_user_id uuid,
  target_run_id uuid,
  target_week integer default 1,
  target_version integer default 0,
  target_status text default 'playing'
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into auth.users (id) values (target_user_id);
  insert into public.game_runs (
    id, user_id, rule_set_id, channel_rule_id, channel_name, status
  ) values (
    target_run_id,
    target_user_id,
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'BE-022 test channel',
    target_status
  );
  insert into public.run_state (
    run_id, current_week, posting_frequency_rule_id, state_version
  ) values (
    target_run_id,
    target_week,
    '00000000-0000-4000-8100-000000001201',
    target_version
  );
  insert into public.run_abilities (run_id, ability_code, value)
  select target_run_id, code, 10
  from public.ability_definitions;
end;
$$;

select has_function(
  'public',
  'allocate_ability_points',
  array['uuid', 'uuid', 'jsonb', 'integer'],
  'allocate_ability_points exists with the server command signature'
);

select function_returns(
  'public',
  'allocate_ability_points',
  array['uuid', 'uuid', 'jsonb', 'integer'],
  'integer',
  'allocate_ability_points returns the next state version'
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
      'public.allocate_ability_points(uuid,uuid,jsonb,integer)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute allocate_ability_points'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.allocate_ability_points(uuid,uuid,jsonb,integer)',
    'EXECUTE'
  ),
  'anon cannot execute allocate_ability_points'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.allocate_ability_points(uuid,uuid,jsonb,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute allocate_ability_points directly'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.allocate_ability_points(uuid,uuid,jsonb,integer)',
    'EXECUTE'
  ),
  'service_role can execute allocate_ability_points'
);

select ok(
  (
    select function_row.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc as function_row
    where function_row.oid =
      'public.allocate_ability_points(uuid,uuid,jsonb,integer)'::regprocedure
  ),
  'allocate_ability_points fixes an empty search_path'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000001',
  'e2200000-0000-4000-8100-000000000001'
);
insert into public.ability_point_grants (
  id, run_id, earned_week, available_from_week, amount, status
) values (
  'e2200000-0000-4000-8200-000000000001',
  'e2200000-0000-4000-8100-000000000001',
  1, 1, 21, 'available'
);

select is(
  public.allocate_ability_points(
    'e2200000-0000-4000-8000-000000000001',
    'e2200000-0000-4000-8100-000000000001',
    '{"planning":1,"talking":2,"expertise":3,"editing":4,"visual":5,"filming":6}',
    0
  ),
  1,
  'all six abilities are allocated and the next version is returned'
);

select is(
  (
    select pg_catalog.jsonb_object_agg(ability_code, value order by ability_code)
    from public.run_abilities
    where run_id = 'e2200000-0000-4000-8100-000000000001'
  ),
  '{"editing":14,"expertise":13,"filming":16,"planning":11,"talking":12,"visual":15}'::jsonb,
  'all six current ability rows are updated'
);

select is(
  (
    select pg_catalog.jsonb_object_agg(ability_code, points order by ability_code)
    from public.ability_allocations
    where grant_id = 'e2200000-0000-4000-8200-000000000001'
  ),
  '{"editing":4,"expertise":3,"filming":6,"planning":1,"talking":2,"visual":5}'::jsonb,
  'positive allocation history is appended for every changed ability'
);

select is(
  (
    select status
    from public.ability_point_grants
    where id = 'e2200000-0000-4000-8200-000000000001'
  ),
  'consumed',
  'a fully used grant becomes consumed'
);

select is(
  (
    select pg_catalog.jsonb_build_array(state_version, energy, cash, current_week)
    from public.run_state
    where run_id = 'e2200000-0000-4000-8100-000000000001'
  ),
  '[1,100,100000,1]'::jsonb,
  'allocation increments only state_version and consumes no energy, cash, or week'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000002',
  'e2200000-0000-4000-8100-000000000002',
  2
);
insert into public.ability_point_grants (
  id, run_id, earned_week, available_from_week, amount, status
) values
  (
    'e2200000-0000-4000-8200-000000000002',
    'e2200000-0000-4000-8100-000000000002',
    1, 1, 3, 'available'
  ),
  (
    'e2200000-0000-4000-8200-000000000003',
    'e2200000-0000-4000-8100-000000000002',
    2, 2, 5, 'available'
  );

select lives_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000002',
      'e2200000-0000-4000-8100-000000000002',
      '{"planning":4,"talking":1,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'a partial subset of abilities can be allocated across multiple grants'
);

select is(
  (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(grant_id, ability_code, points)
      order by grant_id, ability_code
    )
    from public.ability_allocations
    where grant_id in (
      'e2200000-0000-4000-8200-000000000002',
      'e2200000-0000-4000-8200-000000000003'
    )
  ),
  '[["e2200000-0000-4000-8200-000000000002","planning",3],["e2200000-0000-4000-8200-000000000003","planning",1],["e2200000-0000-4000-8200-000000000003","talking",1]]'::jsonb,
  'grants are consumed by available week, earned week, and id while abilities use fixed order'
);

select is(
  (
    select pg_catalog.jsonb_object_agg(id, status order by id)
    from public.ability_point_grants
    where run_id = 'e2200000-0000-4000-8100-000000000002'
  ),
  '{"e2200000-0000-4000-8200-000000000002":"consumed","e2200000-0000-4000-8200-000000000003":"available"}'::jsonb,
  'a fully used earlier grant is consumed while a partially used grant remains available'
);

select is(
  (
    select amount - coalesce(pg_catalog.sum(allocation.points), 0)
    from public.ability_point_grants as point_grant
    left join public.ability_allocations as allocation
      on allocation.grant_id = point_grant.id
    where point_grant.id = 'e2200000-0000-4000-8200-000000000003'
    group by point_grant.amount
  ),
  3::bigint,
  'the partial grant retains its balance derived from amount minus allocation history'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000003',
  'e2200000-0000-4000-8100-000000000003'
);
update public.run_abilities
set value = 98
where run_id = 'e2200000-0000-4000-8100-000000000003'
  and ability_code = 'planning';
insert into public.ability_point_grants (
  run_id, earned_week, available_from_week, amount, status
) values (
  'e2200000-0000-4000-8100-000000000003', 1, 1, 2, 'available'
);
select lives_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000003',
      'e2200000-0000-4000-8100-000000000003',
      '{"planning":2,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'an ability may reach exactly 100'
);
select is(
  (
    select value from public.run_abilities
    where run_id = 'e2200000-0000-4000-8100-000000000003'
      and ability_code = 'planning'
  ),
  100::smallint,
  'the exact ability limit is stored without clamping or discarding points'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000004',
  'e2200000-0000-4000-8100-000000000004'
);
insert into public.ability_point_grants (
  id, run_id, earned_week, available_from_week, amount, status
) values (
  'e2200000-0000-4000-8200-000000000004',
  'e2200000-0000-4000-8100-000000000004',
  1, 1, 2, 'available'
);
select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000004',
      'e2200000-0000-4000-8100-000000000004',
      '{"planning":3,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INSUFFICIENT_ABILITY_POINTS',
  'allocation above the database-derived available balance is rejected'
);

update public.run_abilities
set value = 99
where run_id = 'e2200000-0000-4000-8100-000000000004'
  and ability_code = 'planning';
select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000004',
      'e2200000-0000-4000-8100-000000000004',
      '{"planning":2,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_ABILITY_LIMIT_EXCEEDED',
  'allocation above ability 100 is rejected instead of clamped'
);

select is(
  (
    select pg_catalog.jsonb_build_array(
      (select pg_catalog.count(*) from public.ability_allocations where grant_id = 'e2200000-0000-4000-8200-000000000004'),
      (select status from public.ability_point_grants where id = 'e2200000-0000-4000-8200-000000000004'),
      (select state_version from public.run_state where run_id = 'e2200000-0000-4000-8100-000000000004')
    )
  ),
  '[0,"available",0]'::jsonb,
  'failed validation changes no history, grant status, or version'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000004',
      'e2200000-0000-4000-8100-000000000004',
      '{"planning":-1,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION',
  'negative allocation is rejected'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000004',
      'e2200000-0000-4000-8100-000000000004',
      '{"planning":0.5,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION',
  'fractional allocation is rejected'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000004',
      'e2200000-0000-4000-8100-000000000004',
      '{"planning":"1","talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION',
  'a nonnumeric allocation is rejected'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000004',
      'e2200000-0000-4000-8100-000000000004',
      '{"planning":0,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0,"charisma":1}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION',
  'an unknown ability code is rejected'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000004',
      'e2200000-0000-4000-8100-000000000004',
      '{"planning":0,"talking":0,"expertise":0,"editing":0,"visual":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION',
  'all six ability codes are required'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000005',
  'e2200000-0000-4000-8100-000000000005',
  2
);
insert into public.ability_point_grants (
  run_id, earned_week, available_from_week, amount, status
) values (
  'e2200000-0000-4000-8100-000000000005', 1, 1, 3, 'available'
);
insert into public.run_conditions (
  run_id, health_risk_rule_id, started_week, duration_weeks,
  unavailable_from_week, unavailable_through_week
) values (
  'e2200000-0000-4000-8100-000000000005',
  '00000000-0000-4000-8100-000000002102',
  1, 1, 2, 2
);
select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000005',
      'e2200000-0000-4000-8100-000000000005',
      '{"planning":1,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_ACTIVITY_UNAVAILABLE',
  'allocation is rejected during an activity-unavailable week'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000001',
      'e2200000-0000-4000-8100-000000000005',
      '{"planning":1,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_FORBIDDEN',
  'another user cannot allocate points for the run'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000005',
      'e2200000-0000-4000-8100-000000000005',
      '{"planning":1,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      99
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_STALE_STATE',
  'a stale state version is rejected'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000006',
  'e2200000-0000-4000-8100-000000000006',
  1,
  0,
  'stage_cleared'
);
select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000006',
      'e2200000-0000-4000-8100-000000000006',
      '{"planning":0,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_RUN_NOT_PLAYABLE',
  'only playing runs can allocate ability points'
);

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000006',
      'e2200000-0000-4000-8100-000000000099',
      '{"planning":0,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_RUN_NOT_FOUND',
  'a missing run is distinguished from a forbidden run'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000007',
  'e2200000-0000-4000-8100-000000000007',
  2
);
insert into public.ability_point_grants (
  run_id, earned_week, available_from_week, amount, status
) values
  ('e2200000-0000-4000-8100-000000000007', 1, 1, 1, 'available'),
  ('e2200000-0000-4000-8100-000000000007', 2, 2, 10, 'held'),
  ('e2200000-0000-4000-8100-000000000007', 3, 3, 10, 'available');
select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000007',
      'e2200000-0000-4000-8100-000000000007',
      '{"planning":2,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INSUFFICIENT_ABILITY_POINTS',
  'held and future grants are excluded from available balance'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000008',
  'e2200000-0000-4000-8100-000000000008'
);
select is(
  public.allocate_ability_points(
    'e2200000-0000-4000-8000-000000000008',
    'e2200000-0000-4000-8100-000000000008',
    '{"planning":0,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
    0
  ),
  1,
  'all-zero input is allowed because the specification has no positive-total constraint'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from public.ability_allocations as allocation
    join public.ability_point_grants as point_grant on point_grant.id = allocation.grant_id
    where point_grant.run_id = 'e2200000-0000-4000-8100-000000000008'
  ),
  0,
  'all-zero input appends no zero-point history rows'
);

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000010',
  'e2200000-0000-4000-8100-000000000010'
);
insert into public.ability_point_grants (
  id, run_id, earned_week, available_from_week, amount, status
) values (
  'e2200000-0000-4000-8200-000000000010',
  'e2200000-0000-4000-8100-000000000010',
  1, 1, 5, 'available'
);
insert into public.ability_allocations (
  grant_id, ability_code, points, allocated_week
) values (
  'e2200000-0000-4000-8200-000000000010', 'planning', 2, 1
);
update public.run_abilities
set value = 12
where run_id = 'e2200000-0000-4000-8100-000000000010'
  and ability_code = 'planning';

select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000010',
      'e2200000-0000-4000-8100-000000000010',
      '{"planning":0,"talking":4,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'ALLOCATE_ABILITY_POINTS_INSUFFICIENT_ABILITY_POINTS',
  'existing allocation history is subtracted from the grant amount'
);

select lives_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000010',
      'e2200000-0000-4000-8100-000000000010',
      '{"planning":0,"talking":3,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'the exact history-derived remaining balance can be allocated'
);

create function pg_temp.fail_be022_ability_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.run_id = 'e2200000-0000-4000-8100-000000000009'
    and new.ability_code = 'talking'
  then
    raise exception using errcode = 'P0001', message = 'BE022_FORCED_FAILURE';
  end if;
  return new;
end;
$$;
create trigger fail_be022_ability_update
before update on public.run_abilities
for each row execute function pg_temp.fail_be022_ability_update();

select pg_temp.create_ability_run(
  'e2200000-0000-4000-8000-000000000009',
  'e2200000-0000-4000-8100-000000000009'
);
insert into public.ability_point_grants (
  id, run_id, earned_week, available_from_week, amount, status
) values (
  'e2200000-0000-4000-8200-000000000009',
  'e2200000-0000-4000-8100-000000000009',
  1, 1, 2, 'available'
);
select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000009',
      'e2200000-0000-4000-8100-000000000009',
      '{"planning":1,"talking":1,"expertise":0,"editing":0,"visual":0,"filming":0}',
      0
    )
  $$,
  'P0001',
  'BE022_FORCED_FAILURE',
  'a failure after history insertion aborts the whole RPC'
);
select is(
  (
    select pg_catalog.jsonb_build_array(
      (select pg_catalog.count(*) from public.ability_allocations where grant_id = 'e2200000-0000-4000-8200-000000000009'),
      (select pg_catalog.min(value) from public.run_abilities where run_id = 'e2200000-0000-4000-8100-000000000009'),
      (select pg_catalog.max(value) from public.run_abilities where run_id = 'e2200000-0000-4000-8100-000000000009'),
      (select status from public.ability_point_grants where id = 'e2200000-0000-4000-8200-000000000009'),
      (select state_version from public.run_state where run_id = 'e2200000-0000-4000-8100-000000000009')
    )
  ),
  '[0,10,10,"available",0]'::jsonb,
  'history, every ability, grant status, and version all roll back together'
);

select throws_ok(
  $$
    update public.ability_allocations
    set points = points + 1
    where grant_id = 'e2200000-0000-4000-8200-000000000001'
  $$,
  '23514',
  'ability_allocations rows are immutable',
  'saved allocation history cannot be changed'
);
select throws_ok(
  $$
    delete from public.ability_allocations
    where grant_id = 'e2200000-0000-4000-8200-000000000001'
  $$,
  '23514',
  'ability_allocations rows are immutable',
  'saved allocation history cannot be deleted'
);

set local role authenticated;
select throws_ok(
  $$
    select public.allocate_ability_points(
      'e2200000-0000-4000-8000-000000000008',
      'e2200000-0000-4000-8100-000000000008',
      '{"planning":0,"talking":0,"expertise":0,"editing":0,"visual":0,"filming":0}',
      1
    )
  $$,
  '42501',
  null,
  'authenticated cannot invoke the server-only RPC directly'
);
reset role;

select * from finish();

rollback;
