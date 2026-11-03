begin;

set local search_path = extensions, public, pg_catalog;

select plan(36);

select has_function(
  'public',
  'commit_create_idea',
  array['uuid', 'uuid', 'text', 'text', 'integer', 'smallint', 'text', 'text', 'text'],
  'commit_create_idea exists with the server command signature'
);

select function_returns(
  'public',
  'commit_create_idea',
  array['uuid', 'uuid', 'text', 'text', 'integer', 'smallint', 'text', 'text', 'text'],
  'uuid',
  'commit_create_idea returns the created idea id'
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
      'public.commit_create_idea(uuid,uuid,text,text,integer,smallint,text,text,text)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute commit_create_idea'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'public.commit_create_idea(uuid,uuid,text,text,integer,smallint,text,text,text)',
    'EXECUTE'
  ),
  'anon cannot execute commit_create_idea'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated',
    'public.commit_create_idea(uuid,uuid,text,text,integer,smallint,text,text,text)',
    'EXECUTE'
  ),
  'authenticated cannot execute commit_create_idea'
);

select ok(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.commit_create_idea(uuid,uuid,text,text,integer,smallint,text,text,text)',
    'EXECUTE'
  ),
  'service_role can execute commit_create_idea'
);

select ok(
  (
    select function_row.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc as function_row
    where function_row.oid =
      'public.commit_create_idea(uuid,uuid,text,text,integer,smallint,text,text,text)'::regprocedure
  ),
  'commit_create_idea fixes an empty search_path'
);

insert into auth.users (id)
values
  ('d1900000-0000-4000-8000-000000000001'),
  ('d1900000-0000-4000-8000-000000000002'),
  ('d1900000-0000-4000-8000-000000000003'),
  ('d1900000-0000-4000-8000-000000000004'),
  ('d1900000-0000-4000-8000-000000000005'),
  ('d1900000-0000-4000-8000-000000000006'),
  ('d1900000-0000-4000-8000-000000000007'),
  ('d1900000-0000-4000-8000-000000000008');

do $$
declare
  actor_user_id uuid;
begin
  foreach actor_user_id in array array[
    'd1900000-0000-4000-8000-000000000001'::uuid,
    'd1900000-0000-4000-8000-000000000002'::uuid,
    'd1900000-0000-4000-8000-000000000003'::uuid,
    'd1900000-0000-4000-8000-000000000004'::uuid,
    'd1900000-0000-4000-8000-000000000005'::uuid,
    'd1900000-0000-4000-8000-000000000006'::uuid,
    'd1900000-0000-4000-8000-000000000007'::uuid,
    'd1900000-0000-4000-8000-000000000008'::uuid
  ]
  loop
    perform public.commit_start_game(
      actor_user_id,
      'BE-019 ' || actor_user_id::text,
      'mainstream',
      null
    );
  end loop;
end;
$$;

select lives_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000001',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000001'),
      E' \t Normal idea \n ',
      'Description without an invented limit',
      0,
      84::smallint,
      'completed',
      'test-model-2026-11-03',
      'idea-evaluation-v1'
    )
  $$,
  'a valid idea is created atomically'
);

select is(
  (
    select jsonb_build_array(title, description, created_week, deleted_at)
    from public.player_ideas
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000001'
    )
      and title = 'Normal idea'
  ),
  '["Normal idea","Description without an invented limit",1,null]'::jsonb,
  'the idea stores its normalized title, optional description, and current week'
);

select is(
  (
    select jsonb_build_array(
      evaluation.score,
      evaluation.evaluation_status,
      evaluation.model,
      evaluation.prompt_version,
      evaluation.evaluated_at is not null
    )
    from public.idea_evaluations as evaluation
    join public.player_ideas as idea on idea.id = evaluation.idea_id
    where idea.title = 'Normal idea'
  ),
  '[84,"completed","test-model-2026-11-03","idea-evaluation-v1",true]'::jsonb,
  'the completed evaluation and audit metadata are stored privately'
);

select is(
  (
    select position
    from public.idea_queue_entries as queue_entry
    join public.player_ideas as idea on idea.id = queue_entry.idea_id
    where idea.title = 'Normal idea'
  ),
  1,
  'the first idea is appended at queue position one'
);

select is(
  (
    select state_version
    from public.run_state
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000001'
    )
  ),
  1,
  'creating an idea increments state_version once'
);

select lives_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000001',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000001'),
      '企', null, 1, 1::smallint, 'completed', 'model', 'prompt-v1'
    )
  $$,
  'a one-character title is accepted'
);

select lives_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000001',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000001'),
      repeat('企', 100), null, 2, 100::smallint, 'completed', 'model', 'prompt-v1'
    )
  $$,
  'a one-hundred-character title is accepted'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000001',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000001'),
      E' \t\n ', null, 3, 60::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_VALIDATION_ERROR',
  'a whitespace-only title is rejected'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000001',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000001'),
      repeat('企', 101), null, 3, 60::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_VALIDATION_ERROR',
  'a one-hundred-and-one-character title is rejected'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000006',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000001'),
      'Forged owner', null, 3, 60::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_FORBIDDEN',
  'a different owner is rejected'
);

update public.game_runs
set status = 'stage_cleared'
where user_id = 'd1900000-0000-4000-8000-000000000005';

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000005',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000005'),
      'Not playing', null, 0, 60::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_RUN_NOT_PLAYABLE',
  'a non-playing run is rejected'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000004',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000004'),
      'Stale state', null, 99, 60::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_STALE_STATE',
  'a stale expectedVersion is rejected'
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
where game_run.user_id = 'd1900000-0000-4000-8000-000000000004'
limit 1;

update public.run_state
set current_week = 2
where run_id = (
  select id from public.game_runs
  where user_id = 'd1900000-0000-4000-8000-000000000004'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000004',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000004'),
      'Unavailable week', null, 0, 60::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_ACTIVITY_UNAVAILABLE',
  'idea creation is rejected during an unavailable week'
);

select lives_ok(
  $$
    do $create_three$
    declare
      target_run_id uuid;
      idea_number integer;
    begin
      select id into target_run_id
      from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000002';

      for idea_number in 1..3 loop
        perform public.commit_create_idea(
          'd1900000-0000-4000-8000-000000000002',
          target_run_id,
          'Weekly idea ' || idea_number,
          null,
          idea_number - 1,
          70::smallint,
          'completed',
          'model',
          'prompt-v1'
        );
      end loop;
    end;
    $create_three$
  $$,
  'three ideas can be created in one week'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000002',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000002'),
      'Fourth idea', null, 3, 70::smallint, 'completed', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_WEEKLY_LIMIT',
  'a fourth idea in the same week is rejected'
);

update public.player_ideas
set deleted_at = pg_catalog.statement_timestamp()
where id = (
  select id
  from public.player_ideas
  where run_id = (
    select id from public.game_runs
    where user_id = 'd1900000-0000-4000-8000-000000000002'
  )
  order by created_at
  limit 1
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000002',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000002'),
      'Deleted slot is not restored', null, 3, 70::smallint, 'completed', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_WEEKLY_LIMIT',
  'deleting an idea does not restore the weekly creation slot'
);

select is(
  (
    select count(*)::integer
    from public.player_ideas
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000002'
    )
      and created_week = 1
  ),
  3,
  'deleted ideas remain in the weekly creation count'
);

select is(
  (
    select jsonb_agg(position order by position)
    from public.idea_queue_entries
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000001'
    )
  ),
  '[1,2,3]'::jsonb,
  'each successful creation appends to the queue tail'
);

select lives_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000008',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000008'),
      'Fallback idea', null, 0, 60::smallint, 'fallback', 'fallback-model', 'prompt-v2'
    )
  $$,
  'a fallback evaluation creates an idea'
);

select is(
  (
    select jsonb_build_array(score, evaluation_status, model, prompt_version)
    from public.idea_evaluations as evaluation
    join public.player_ideas as idea on idea.id = evaluation.idea_id
    where idea.title = 'Fallback idea'
  ),
  '[60,"fallback","fallback-model","prompt-v2"]'::jsonb,
  'fallback score 60 and its audit metadata are stored'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000008',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000008'),
      'Invalid fallback', null, 1, 59::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_VALIDATION_ERROR',
  'fallback evaluations must use score 60'
);

select lives_ok(
  $$
    do $fill_stock$
    declare
      target_run_id uuid;
      idea_number integer;
      version_number integer;
    begin
      select id into target_run_id
      from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000003';

      for idea_number in 1..30 loop
        update public.run_state
        set current_week = 1 + ((idea_number - 1) / 3)
        where run_id = target_run_id
        returning state_version into version_number;

        perform public.commit_create_idea(
          'd1900000-0000-4000-8000-000000000003',
          target_run_id,
          'Stock idea ' || idea_number,
          null,
          version_number,
          60::smallint,
          'fallback',
          'model',
          'prompt-v1'
        );
      end loop;
    end;
    $fill_stock$
  $$,
  'thirty pending ideas can be stocked across weeks'
);

select is(
  (
    select count(*)::integer
    from public.player_ideas
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000003'
    )
      and deleted_at is null
  ),
  30,
  'the stock reaches exactly the rule-set limit of thirty'
);

update public.run_state
set current_week = current_week + 1
where run_id = (
  select id from public.game_runs
  where user_id = 'd1900000-0000-4000-8000-000000000003'
);

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000003',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000003'),
      'Stock idea 31', null, 30, 60::smallint, 'fallback', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'CREATE_IDEA_STOCK_FULL',
  'a thirty-first pending idea is rejected'
);

create function public.fail_be019_queue_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.game_runs
    where id = new.run_id
      and user_id = 'd1900000-0000-4000-8000-000000000007'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'BE019_FORCED_QUEUE_FAILURE';
  end if;
  return new;
end;
$$;

create trigger fail_be019_queue_insert
before insert on public.idea_queue_entries
for each row execute function public.fail_be019_queue_insert();

select throws_ok(
  $$
    select public.commit_create_idea(
      'd1900000-0000-4000-8000-000000000007',
      (select id from public.game_runs where user_id = 'd1900000-0000-4000-8000-000000000007'),
      'Must roll back', null, 0, 88::smallint, 'completed', 'model', 'prompt-v1'
    )
  $$,
  'P0001',
  'BE019_FORCED_QUEUE_FAILURE',
  'an intermediate queue failure aborts the command'
);

select is(
  (
    select count(*)::integer
    from public.player_ideas
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000007'
    )
  ),
  0,
  'a failed command leaves no player idea'
);

select is(
  (
    select count(*)::integer
    from public.idea_evaluations as evaluation
    join public.player_ideas as idea on idea.id = evaluation.idea_id
    where idea.run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000007'
    )
  ),
  0,
  'a failed command leaves no evaluation'
);

select is(
  (
    select count(*)::integer
    from public.idea_queue_entries
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000007'
    )
  ),
  0,
  'a failed command leaves no queue entry'
);

select is(
  (
    select state_version
    from public.run_state
    where run_id = (
      select id from public.game_runs
      where user_id = 'd1900000-0000-4000-8000-000000000007'
    )
  ),
  0,
  'a failed command does not increment state_version'
);

select * from finish();

rollback;
