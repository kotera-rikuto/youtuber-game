begin;

set local search_path = extensions, public, pg_catalog;

select plan(25);

select has_function(
  'public', 'purchase_equipment', array['uuid', 'uuid', 'text', 'text', 'integer'],
  'purchase_equipment exists with the server command signature'
);
select function_returns(
  'public', 'purchase_equipment', array['uuid', 'uuid', 'text', 'text', 'integer'],
  'jsonb', 'purchase_equipment returns a receipt'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function_row
    cross join lateral pg_catalog.aclexplode(
      coalesce(function_row.proacl, pg_catalog.acldefault('f', function_row.proowner))
    ) as privilege
    where function_row.oid =
      'public.purchase_equipment(uuid,uuid,text,text,integer)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute purchase_equipment'
);
select ok(
  not pg_catalog.has_function_privilege('anon', 'public.purchase_equipment(uuid,uuid,text,text,integer)', 'EXECUTE'),
  'anon cannot execute purchase_equipment'
);
select ok(
  not pg_catalog.has_function_privilege('authenticated', 'public.purchase_equipment(uuid,uuid,text,text,integer)', 'EXECUTE'),
  'authenticated cannot execute purchase_equipment directly'
);
select ok(
  pg_catalog.has_function_privilege('service_role', 'public.purchase_equipment(uuid,uuid,text,text,integer)', 'EXECUTE'),
  'service_role can execute purchase_equipment'
);
select ok(
  (select proconfig @> array['search_path=""']::text[] from pg_catalog.pg_proc
   where oid = 'public.purchase_equipment(uuid,uuid,text,text,integer)'::regprocedure),
  'purchase_equipment fixes an empty search_path'
);

create function pg_temp.create_equipment_run(
  target_user_id uuid, target_run_id uuid, target_week integer default 1,
  target_version integer default 0, target_status text default 'playing'
)
returns void language plpgsql set search_path = '' as $$
begin
  insert into auth.users (id) values (target_user_id);
  insert into public.game_runs (
    id, user_id, rule_set_id, channel_rule_id, channel_name, status
  ) values (
    target_run_id, target_user_id,
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'BE-023 test channel', target_status
  );
  insert into public.run_state (
    run_id, current_week, posting_frequency_rule_id, state_version
  ) values (
    target_run_id, target_week,
    '00000000-0000-4000-8100-000000001201', target_version
  );
end;
$$;

select pg_temp.create_equipment_run(
  'e2300000-0000-4000-8000-000000000001',
  'e2300000-0000-4000-8100-000000000001'
);

select is(
  public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000001',
    'e2300000-0000-4000-8100-000000000001', 'camera', 'beginner', 0
  ),
  jsonb_build_object(
    'equipmentType', 'camera', 'previousLevel', 'none',
    'purchasedLevel', 'beginner', 'pricePaid', 30000,
    'cashAfter', 70000, 'purchasedWeek', 1, 'nextStateVersion', 1
  ),
  'none to beginner uses the rule price and advances one version'
);
select is(
  (select jsonb_build_array(cash, energy, current_week, state_version)
   from public.run_state where run_id = 'e2300000-0000-4000-8100-000000000001'),
  '[70000,100,1,1]'::jsonb,
  'cash changes while energy and week remain unchanged'
);
select is(
  (select tier from public.equipment_tier_rules as rule
   join public.run_equipment as equipment on equipment.equipment_tier_rule_id = rule.id
   where equipment.run_id = 'e2300000-0000-4000-8100-000000000001'),
  'beginner', 'the current equipment is replaced with the purchased tier'
);
select is(
  (select jsonb_build_array(from_tier_rule_id, price_paid, purchased_week)
   from public.equipment_purchases
   where run_id = 'e2300000-0000-4000-8100-000000000001'),
  jsonb_build_array(null, 30000, 1),
  'first purchase stores NULL as the previous tier rule'
);

select pg_temp.create_equipment_run(
  'e2300000-0000-4000-8000-000000000002',
  'e2300000-0000-4000-8100-000000000002'
);
select is(
  (select (public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000002',
    'e2300000-0000-4000-8100-000000000002', 'camera', 'advanced', 0
  )->>'pricePaid')::bigint),
  500000::bigint, 'none can buy advanced directly at the advanced rule price'
);
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000002',
    'e2300000-0000-4000-8100-000000000002', 'camera', 'advanced', 1)$$,
  'P0001', 'PURCHASE_EQUIPMENT_SAME_OR_LOWER_TIER',
  'same tier is rejected'
);
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000002',
    'e2300000-0000-4000-8100-000000000002', 'camera', 'beginner', 1)$$,
  'P0001', 'PURCHASE_EQUIPMENT_SAME_OR_LOWER_TIER',
  'lower tier is rejected'
);
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000002',
    'camera-run-not-found', 'camera', 'beginner', 1)$$,
  '22P02', null, 'malformed UUID does not execute a purchase'
);

select pg_temp.create_equipment_run(
  'e2300000-0000-4000-8000-000000000003',
  'e2300000-0000-4000-8100-000000000003'
);
update public.run_state set cash = 1
where run_id = 'e2300000-0000-4000-8100-000000000003';
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000003',
    'e23000000-0000-4000-8100-000000000003', 'camera', 'beginner', 0)$$,
  'P0001', 'PURCHASE_EQUIPMENT_RUN_NOT_FOUND', 'unknown run is rejected'
);
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000003',
    'e2300000-0000-4000-8100-000000000003', 'camera', 'beginner', 0)$$,
  'P0001', 'PURCHASE_EQUIPMENT_INSUFFICIENT_CASH', 'insufficient cash is rejected'
);
select is(
  (select jsonb_build_array(cash, state_version)
   from public.run_state where run_id = 'e2300000-0000-4000-8100-000000000003'),
  '[1,0]'::jsonb, 'failed purchase leaves cash and version unchanged'
);

select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000099',
    'e2300000-0000-4000-8100-000000000001', 'camera', 'beginner', 0)$$,
  'P0001', 'PURCHASE_EQUIPMENT_FORBIDDEN', 'another actor is rejected'
);
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000001',
    'e2300000-0000-4000-8100-000000000001', 'none', 'beginner', 1)$$,
  'P0001', 'PURCHASE_EQUIPMENT_INVALID_EQUIPMENT_TYPE', 'none is not a type'
);
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000001',
    'e2300000-0000-4000-8100-000000000001', 'camera', 'none', 1)$$,
  'P0001', 'PURCHASE_EQUIPMENT_INVALID_EQUIPMENT_LEVEL', 'none is not a purchasable level'
);
select throws_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000001',
    'e2300000-0000-4000-8100-000000000001', 'camera', 'intermediate', 0)$$,
  'P0001', 'PURCHASE_EQUIPMENT_STALE_STATE', 'stale state is rejected'
);

select pg_temp.create_equipment_run(
  'e2300000-0000-4000-8000-000000000004',
  'e2300000-0000-4000-8100-000000000004'
);
select lives_ok(
  $$select public.purchase_equipment(
    'e2300000-0000-4000-8000-000000000004',
    'e2300000-0000-4000-8100-000000000004', 'microphone', 'beginner', 0)$$,
  'a valid purchase commits atomically'
);
select throws_ok(
  $$update public.equipment_purchases set price_paid = 1
    where run_id = 'e2300000-0000-4000-8100-000000000004'$$,
  '23514', null, 'purchase history cannot be updated'
);
select throws_ok(
  $$delete from public.equipment_purchases
    where run_id = 'e2300000-0000-4000-8100-000000000004'$$,
  '23514', null, 'purchase history cannot be deleted'
);

select * from finish();
rollback;