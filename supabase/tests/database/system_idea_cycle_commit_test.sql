begin;

set local search_path = extensions, public, pg_catalog;

select plan(19);

select has_function(
  'public',
  'commit_system_idea_cycle',
  array['uuid', 'uuid', 'integer', 'uuid[]'],
  'commit_system_idea_cycle exists with the server command signature'
);

select function_returns(
  'public',
  'commit_system_idea_cycle',
  array['uuid', 'uuid', 'integer', 'uuid[]'],
  'uuid',
  'commit_system_idea_cycle returns the persisted cycle id'
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
      'public.commit_system_idea_cycle(uuid,uuid,integer,uuid[])'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute commit_system_idea_cycle'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.commit_system_idea_cycle(uuid,uuid,integer,uuid[])',
    'EXECUTE'
  ),
  'anon cannot execute commit_system_idea_cycle'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.commit_system_idea_cycle(uuid,uuid,integer,uuid[])',
    'EXECUTE'
  ),
  'authenticated cannot execute commit_system_idea_cycle'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.commit_system_idea_cycle(uuid,uuid,integer,uuid[])',
    'EXECUTE'
  ),
  'service_role can execute commit_system_idea_cycle'
);

insert into auth.users (id)
values
  ('d2800000-0000-4000-8000-000000000001'),
  ('d2800000-0000-4000-8000-000000000002');

insert into public.game_runs (
  id,
  user_id,
  rule_set_id,
  channel_rule_id,
  channel_name
)
values (
  'd2810000-0000-4000-8000-000000000001',
  'd2800000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001001',
  'BE-028 Mainstream'
);

insert into public.run_state (run_id, posting_frequency_rule_id)
values (
  'd2810000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001201'
);

select lives_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000001',
      'd2810000-0000-4000-8000-000000000001',
      7,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and rule_idea.enabled
          and template.enabled
          and template.channel_type_code = 'mainstream'
          and template.specialty_code is null
        order by rule_idea.id
      )
    )
  $$,
  'the server command atomically creates a complete cycle'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.system_idea_cycles
    where run_id = 'd2810000-0000-4000-8000-000000000001'
  ),
  1,
  'one cycle is persisted for the run'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.system_idea_cycle_entries as entry
    join public.system_idea_cycles as cycle on cycle.id = entry.cycle_id
    where cycle.run_id = 'd2810000-0000-4000-8000-000000000001'
  ),
  50,
  'the cycle contains exactly 50 entries'
);

select is(
  (
    select pg_catalog.jsonb_agg(entry.position order by entry.position)
    from public.system_idea_cycle_entries as entry
    join public.system_idea_cycles as cycle on cycle.id = entry.cycle_id
    where cycle.run_id = 'd2810000-0000-4000-8000-000000000001'
  ),
  pg_catalog.to_jsonb(array(select pg_catalog.generate_series(1, 50))),
  'cycle positions are contiguous from 1 through 50'
);

select is(
  (
    select pg_catalog.count(distinct rule_idea.system_idea_template_id)::integer
    from public.system_idea_cycle_entries as entry
    join public.system_idea_cycles as cycle on cycle.id = entry.cycle_id
    join public.rule_set_system_ideas as rule_idea
      on rule_idea.id = entry.rule_set_system_idea_id
    where cycle.run_id = 'd2810000-0000-4000-8000-000000000001'
  ),
  50,
  'the cycle contains 50 unique templates'
);

select lives_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000001',
      'd2810000-0000-4000-8000-000000000001',
      7,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and rule_idea.enabled
          and template.enabled
          and template.channel_type_code = 'mainstream'
          and template.specialty_code is null
        order by rule_idea.id desc
      )
    )
  $$,
  'a competing command reuses the already sufficient immutable cycle'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.system_idea_cycles
    where run_id = 'd2810000-0000-4000-8000-000000000001'
  ),
  1,
  'reusing the current cycle does not create a duplicate cycle number'
);

select throws_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000002',
      'd2810000-0000-4000-8000-000000000001',
      1,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and template.channel_type_code = 'mainstream'
        order by rule_idea.id
      )
    )
  $$,
  'P0001',
  'SYSTEM_IDEA_CYCLE_RUN_NOT_FOUND',
  'the RPC rejects a non-owner even with a valid run id'
);

select throws_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000001',
      'd2810000-0000-4000-8000-000000000001',
      1,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and template.channel_type_code = 'mainstream'
        order by rule_idea.id
        limit 49
      )
    )
  $$,
  'P0001',
  'SYSTEM_IDEA_CYCLE_VALIDATION_ERROR',
  'the RPC rejects a 49-entry command'
);

select throws_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000001',
      'd2810000-0000-4000-8000-000000000001',
      1,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and template.channel_type_code = 'specialized'
          and template.specialty_code = 'gaming'
        order by rule_idea.id
      )
    )
  $$,
  'P0001',
  'SYSTEM_IDEA_CYCLE_POOL_INVALID',
  'the RPC rejects ideas from another channel pool'
);

set local session_replication_role = replica;

update public.rule_set_system_ideas
set enabled = false
where rule_set_id = '00000000-0000-4000-8000-000000000001'
  and system_idea_template_id = (
    select id
    from public.system_idea_templates
    where code = 'mainstream_002'
  );

set local session_replication_role = origin;

select throws_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000001',
      'd2810000-0000-4000-8000-000000000001',
      1,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and template.channel_type_code = 'mainstream'
          and template.specialty_code is null
        order by rule_idea.id
      )
    )
  $$,
  'P0001',
  'SYSTEM_IDEA_CYCLE_POOL_INVALID',
  'the RPC refuses to finalize when a rule-set association is disabled'
);

set local session_replication_role = replica;

update public.rule_set_system_ideas
set enabled = true
where rule_set_id = '00000000-0000-4000-8000-000000000001'
  and system_idea_template_id = (
    select id
    from public.system_idea_templates
    where code = 'mainstream_002'
  );

set local session_replication_role = origin;

update public.system_idea_templates
set enabled = false
where code = 'mainstream_001';

select throws_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000001',
      'd2810000-0000-4000-8000-000000000001',
      1,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and rule_idea.enabled
          and template.channel_type_code = 'mainstream'
        order by rule_idea.id
      )
    )
  $$,
  'P0001',
  'SYSTEM_IDEA_CYCLE_POOL_INVALID',
  'the RPC refuses to finalize when an enabled pool has only 49 entries'
);

update public.system_idea_templates
set enabled = true
where code = 'mainstream_001';

set local session_replication_role = replica;

insert into public.system_idea_templates (
  id,
  code,
  channel_type_code,
  title,
  description
)
values (
  'd2820000-0000-4000-8000-000000000001',
  'be028_extra_mainstream',
  'mainstream',
  'Extra idea',
  'Makes the pool invalid at 51 entries.'
);

insert into public.rule_set_system_ideas (
  id,
  rule_set_id,
  system_idea_template_id
)
values (
  'd2830000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  'd2820000-0000-4000-8000-000000000001'
);

set local session_replication_role = origin;

select throws_ok(
  $$
    select public.commit_system_idea_cycle(
      'd2800000-0000-4000-8000-000000000001',
      'd2810000-0000-4000-8000-000000000001',
      1,
      array(
        select rule_idea.id
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.rule_set_id = '00000000-0000-4000-8000-000000000001'
          and rule_idea.enabled
          and template.enabled
          and template.channel_type_code = 'mainstream'
          and template.specialty_code is null
        order by rule_idea.id
        limit 50
      )
    )
  $$,
  'P0001',
  'SYSTEM_IDEA_CYCLE_POOL_INVALID',
  'the RPC refuses to finalize when an enabled pool has 51 entries'
);

select * from finish();

rollback;
