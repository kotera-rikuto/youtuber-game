begin;

set local search_path = extensions, public, pg_catalog;

select plan(79);

select has_table('public', 'player_ideas', 'player_ideas exists');
select has_table('public', 'idea_evaluations', 'idea_evaluations exists');
select has_table('public', 'idea_queue_entries', 'idea_queue_entries exists');
select has_table('public', 'weekly_actions', 'weekly_actions exists');
select has_table('public', 'ability_point_grants', 'ability_point_grants exists');
select has_table('public', 'ability_allocations', 'ability_allocations exists');
select has_table('public', 'equipment_purchases', 'equipment_purchases exists');

select has_pk('public', 'player_ideas', 'player_ideas has a primary key');
select has_pk('public', 'idea_evaluations', 'idea_evaluations has a primary key');
select has_pk('public', 'idea_queue_entries', 'idea_queue_entries has a primary key');
select has_pk('public', 'weekly_actions', 'weekly_actions has a primary key');
select has_pk('public', 'ability_point_grants', 'ability_point_grants has a primary key');
select has_pk('public', 'ability_allocations', 'ability_allocations has a primary key');
select has_pk('public', 'equipment_purchases', 'equipment_purchases has a primary key');

select has_fk('public', 'player_ideas', 'player_ideas has a foreign key');
select has_fk('public', 'idea_evaluations', 'idea_evaluations has a foreign key');
select has_fk('public', 'idea_queue_entries', 'idea_queue_entries has a foreign key');
select has_fk('public', 'weekly_actions', 'weekly_actions has foreign keys');
select has_fk('public', 'ability_point_grants', 'ability_point_grants has a foreign key');
select has_fk('public', 'ability_allocations', 'ability_allocations has foreign keys');
select has_fk('public', 'equipment_purchases', 'equipment_purchases has foreign keys');

select ok(
  not exists (
    select 1
    from (values
      ('player_ideas_run_id_id_key'),
      ('idea_queue_entries_run_idea_fkey'),
      ('idea_queue_entries_run_position_key'),
      ('weekly_actions_run_week_key'),
      ('weekly_actions_lock_time_check'),
      ('ability_point_grants_run_earned_week_key'),
      ('ability_allocations_points_positive_check'),
      ('equipment_purchases_price_paid_nonnegative_check')
    ) as expected(constraint_name)
    where not exists (
      select 1
      from pg_catalog.pg_constraint
      where connamespace = 'public'::regnamespace
        and conname = expected.constraint_name
    )
  ),
  'required cross-row, uniqueness, and value constraints exist'
);

select ok(
  not exists (
    select 1
    from (values
      ('player_ideas', 'status'),
      ('player_ideas', 'published_week'),
      ('player_ideas', 'queue_position'),
      ('idea_evaluations', 'view_multiplier'),
      ('idea_evaluations', 'subscriber_conversion_rate'),
      ('ability_point_grants', 'spent_amount'),
      ('weekly_actions', 'payload')
    ) as forbidden(table_name, column_name)
    join information_schema.columns
      on columns.table_schema = 'public'
      and columns.table_name = forbidden.table_name
      and columns.column_name = forbidden.column_name
  ),
  'derived state and generic payload columns are not duplicated'
);

insert into auth.users (id)
values
  ('61000000-0000-4000-8000-000000000001'),
  ('61000000-0000-4000-8000-000000000002');

insert into public.game_runs (
  id, user_id, rule_set_id, channel_rule_id, channel_name
)
values
  (
    '62000000-0000-4000-8000-000000000001',
    '61000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'BE-006 channel one'
  ),
  (
    '62000000-0000-4000-8000-000000000002',
    '61000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'BE-006 channel two'
  );

select lives_ok(
  $$
    insert into public.player_ideas (id, run_id, title, description, created_week)
    values (
      '63000000-0000-4000-8000-000000000001',
      '62000000-0000-4000-8000-000000000001',
      'A valid idea',
      'Original description',
      1
    )
  $$,
  'a player idea can be created'
);

select throws_ok(
  $$
    insert into public.player_ideas (run_id, title, created_week)
    values ('62000000-0000-4000-8000-000000000001', '   ', 1)
  $$,
  '23514', null, 'blank idea titles are rejected'
);

select throws_ok(
  $$
    insert into public.player_ideas (run_id, title, created_week)
    values ('62000000-0000-4000-8000-000000000001', repeat('a', 101), 1)
  $$,
  '23514', null, 'idea titles longer than 100 characters are rejected'
);

select throws_ok(
  $$
    insert into public.player_ideas (run_id, title, created_week)
    values ('62000000-0000-4000-8000-000000000001', 'Invalid week', 0)
  $$,
  '23514', null, 'idea creation weeks must be positive'
);

select throws_ok(
  $$update public.player_ideas set title = 'Changed' where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Player idea content and creation metadata are immutable',
  'idea titles are immutable'
);

select throws_ok(
  $$update public.player_ideas set description = 'Changed' where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Player idea content and creation metadata are immutable',
  'idea descriptions are immutable'
);

select throws_ok(
  $$update public.player_ideas set run_id = '62000000-0000-4000-8000-000000000002' where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Player idea content and creation metadata are immutable',
  'idea run ids are immutable'
);

select throws_ok(
  $$update public.player_ideas set created_week = 2 where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Player idea content and creation metadata are immutable',
  'idea creation weeks are immutable'
);

select throws_ok(
  $$update public.player_ideas set created_at = created_at + interval '1 second' where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Player idea content and creation metadata are immutable',
  'idea creation timestamps are immutable'
);

select lives_ok(
  $$update public.player_ideas set deleted_at = statement_timestamp() where id = '63000000-0000-4000-8000-000000000001'$$,
  'an idea can be logically deleted'
);

select throws_ok(
  $$update public.player_ideas set deleted_at = null where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Deleted player ideas cannot be restored or deleted again',
  'logical deletion cannot be reversed'
);

select throws_ok(
  $$update public.player_ideas set deleted_at = deleted_at + interval '1 second' where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Deleted player ideas cannot be restored or deleted again',
  'logical deletion timestamps cannot be rewritten'
);

select throws_ok(
  $$delete from public.player_ideas where id = '63000000-0000-4000-8000-000000000001'$$,
  '23514', 'Player ideas cannot be physically deleted',
  'player ideas cannot be physically deleted'
);

insert into public.player_ideas (id, run_id, title, created_week)
values
  ('63000000-0000-4000-8000-000000000002', '62000000-0000-4000-8000-000000000001', 'Queue idea one', 1),
  ('63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000001', 'Queue idea two', 1),
  ('63000000-0000-4000-8000-000000000004', '62000000-0000-4000-8000-000000000002', 'Other run idea', 1);

select lives_ok(
  $$
    insert into public.idea_evaluations (idea_id, score, evaluation_status, model, prompt_version)
    values ('63000000-0000-4000-8000-000000000002', 80, 'completed', 'test-model', 'v1')
  $$,
  'an idea evaluation can be created'
);

select throws_ok(
  $$
    insert into public.idea_evaluations (idea_id, score, evaluation_status, model, prompt_version)
    values ('63000000-0000-4000-8000-000000000002', 70, 'fallback', 'test-model', 'v1')
  $$,
  '23505', null, 'each idea can have only one evaluation'
);

select throws_ok(
  $$
    insert into public.idea_evaluations (idea_id, score, evaluation_status, model, prompt_version)
    values ('63000000-0000-4000-8000-000000000003', 101, 'completed', 'test-model', 'v1')
  $$,
  '23514', null, 'evaluation scores outside zero through 100 are rejected'
);

select throws_ok(
  $$
    insert into public.idea_evaluations (idea_id, score, evaluation_status, model, prompt_version)
    values ('63000000-0000-4000-8000-000000000003', 50, 'pending', 'test-model', 'v1')
  $$,
  '23514', null, 'unknown evaluation statuses are rejected'
);

select throws_ok(
  $$
    insert into public.idea_evaluations (idea_id, score, evaluation_status, model, prompt_version)
    values ('63000000-0000-4000-8000-000000000003', 50, 'completed', '  ', 'v1')
  $$,
  '23514', null, 'blank evaluation model names are rejected'
);

select throws_ok(
  $$
    insert into public.idea_evaluations (idea_id, score, evaluation_status, model, prompt_version)
    values ('63000000-0000-4000-8000-000000000003', 50, 'completed', 'test-model', E'\t')
  $$,
  '23514', null, 'blank prompt versions are rejected'
);

select throws_ok(
  $$update public.idea_evaluations set score = 81 where idea_id = '63000000-0000-4000-8000-000000000002'$$,
  '23514', 'idea_evaluations rows are immutable',
  'idea evaluations cannot be updated'
);

select throws_ok(
  $$delete from public.idea_evaluations where idea_id = '63000000-0000-4000-8000-000000000002'$$,
  '23514', 'idea_evaluations rows are immutable',
  'idea evaluations cannot be deleted'
);

select lives_ok(
  $$
    insert into public.idea_queue_entries (idea_id, run_id, position)
    values ('63000000-0000-4000-8000-000000000002', '62000000-0000-4000-8000-000000000001', 1)
  $$,
  'an idea can be added to its run queue'
);

select throws_ok(
  $$
    insert into public.idea_queue_entries (idea_id, run_id, position)
    values ('63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000001', 1)
  $$,
  '23505', null, 'queue positions are unique within a game run'
);

select lives_ok(
  $$
    insert into public.idea_queue_entries (idea_id, run_id, position)
    values ('63000000-0000-4000-8000-000000000004', '62000000-0000-4000-8000-000000000002', 1)
  $$,
  'different game runs may use the same queue position'
);

select throws_ok(
  $$
    insert into public.idea_queue_entries (idea_id, run_id, position)
    values ('63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000001', 0)
  $$,
  '23514', null, 'queue positions must be positive'
);

select throws_ok(
  $$
    insert into public.idea_queue_entries (idea_id, run_id, position)
    values ('63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000002', 2)
  $$,
  '23503', null, 'queue entries cannot use a different run from their idea'
);

select lives_ok(
  $$
    insert into public.idea_queue_entries (idea_id, run_id, position)
    values ('63000000-0000-4000-8000-000000000003', '62000000-0000-4000-8000-000000000001', 2)
  $$,
  'a second queue entry can be added at another position'
);

select lives_ok(
  $$update public.idea_queue_entries set position = 3 where idea_id = '63000000-0000-4000-8000-000000000003'$$,
  'queue entries can be reordered'
);

select lives_ok(
  $$delete from public.idea_queue_entries where idea_id = '63000000-0000-4000-8000-000000000003'$$,
  'queue entries can be removed'
);

select lives_ok(
  $$
    insert into public.weekly_actions (id, run_id, week_number, action_rule_id)
    values (
      '64000000-0000-4000-8000-000000000001',
      '62000000-0000-4000-8000-000000000001',
      1,
      '00000000-0000-4000-8100-000000001601'
    )
  $$,
  'a weekly action can be selected'
);

select throws_ok(
  $$
    insert into public.weekly_actions (run_id, week_number, action_rule_id)
    values (
      '62000000-0000-4000-8000-000000000001',
      1,
      '00000000-0000-4000-8100-000000001602'
    )
  $$,
  '23505', null, 'a run can have only one action per week'
);

select lives_ok(
  $$
    insert into public.weekly_actions (run_id, week_number, action_rule_id)
    values (
      '62000000-0000-4000-8000-000000000001',
      2,
      '00000000-0000-4000-8100-000000001601'
    )
  $$,
  'the same run can select an action for another week'
);

select lives_ok(
  $$
    insert into public.weekly_actions (run_id, week_number, action_rule_id)
    values (
      '62000000-0000-4000-8000-000000000002',
      1,
      '00000000-0000-4000-8100-000000001601'
    )
  $$,
  'another run can select an action for the same week'
);

select throws_ok(
  $$
    insert into public.weekly_actions (run_id, week_number, action_rule_id)
    values (
      '62000000-0000-4000-8000-000000000001',
      0,
      '00000000-0000-4000-8100-000000001601'
    )
  $$,
  '23514', null, 'weekly action week numbers must be positive'
);

select lives_ok(
  $$
    update public.weekly_actions
    set action_rule_id = '00000000-0000-4000-8100-000000001602',
        selected_at = selected_at + interval '1 second'
    where id = '64000000-0000-4000-8000-000000000001'
  $$,
  'an unlocked weekly action can be reselected'
);

select throws_ok(
  $$
    update public.weekly_actions
    set locked_at = selected_at - interval '1 second'
    where id = '64000000-0000-4000-8000-000000000001'
  $$,
  '23514', null, 'a weekly action cannot be locked before it was selected'
);

select lives_ok(
  $$
    update public.weekly_actions
    set locked_at = selected_at
    where id = '64000000-0000-4000-8000-000000000001'
  $$,
  'a weekly action can be locked'
);

select throws_ok(
  $$
    update public.weekly_actions
    set action_rule_id = '00000000-0000-4000-8100-000000001601'
    where id = '64000000-0000-4000-8000-000000000001'
  $$,
  '23514', 'Locked weekly actions cannot be changed or deleted',
  'locked weekly actions cannot be updated'
);

select throws_ok(
  $$delete from public.weekly_actions where id = '64000000-0000-4000-8000-000000000001'$$,
  '23514', 'Locked weekly actions cannot be changed or deleted',
  'locked weekly actions cannot be deleted'
);

select throws_ok(
  $$update public.weekly_actions set locked_at = null where id = '64000000-0000-4000-8000-000000000001'$$,
  '23514', 'Locked weekly actions cannot be changed or deleted',
  'weekly action locks cannot be removed'
);

select lives_ok(
  $$
    insert into public.ability_point_grants (
      id, run_id, earned_week, available_from_week, amount, status
    ) values (
      '65000000-0000-4000-8000-000000000001',
      '62000000-0000-4000-8000-000000000001',
      1,
      2,
      7,
      'available'
    )
  $$,
  'an ability point grant can be created'
);

select throws_ok(
  $$
    insert into public.ability_point_grants (
      run_id, earned_week, available_from_week, amount, status
    ) values (
      '62000000-0000-4000-8000-000000000001', 1, 2, 3, 'available'
    )
  $$,
  '23505', null, 'a run cannot receive two grants for the same earned week'
);

select throws_ok(
  $$
    insert into public.ability_point_grants (
      run_id, earned_week, available_from_week, amount, status
    ) values (
      '62000000-0000-4000-8000-000000000001', 2, 2, 0, 'available'
    )
  $$,
  '23514', null, 'ability point grant amounts must be positive'
);

select throws_ok(
  $$
    insert into public.ability_point_grants (
      run_id, earned_week, available_from_week, amount, status
    ) values (
      '62000000-0000-4000-8000-000000000001', 2, 2, 3, 'unknown'
    )
  $$,
  '23514', null, 'unknown ability point grant statuses are rejected'
);

select throws_ok(
  $$
    insert into public.ability_point_grants (
      run_id, earned_week, available_from_week, amount, status
    ) values (
      '62000000-0000-4000-8000-000000000001', 2, 1, 3, 'available'
    )
  $$,
  '23514', null, 'ability points cannot become available before they are earned'
);

select lives_ok(
  $$
    insert into public.ability_allocations (
      id, grant_id, ability_code, points, allocated_week
    ) values (
      '66000000-0000-4000-8000-000000000001',
      '65000000-0000-4000-8000-000000000001',
      'planning',
      3,
      2
    )
  $$,
  'an ability allocation can be recorded'
);

select throws_ok(
  $$
    insert into public.ability_allocations (grant_id, ability_code, points, allocated_week)
    values ('65000000-0000-4000-8000-000000000001', 'talking', 0, 2)
  $$,
  '23514', null, 'ability allocation points must be positive'
);

select throws_ok(
  $$
    insert into public.ability_allocations (grant_id, ability_code, points, allocated_week)
    values ('65000000-0000-4000-8000-000000000001', 'not_an_ability', 1, 2)
  $$,
  '23503', null, 'ability allocations require a defined ability code'
);

select throws_ok(
  $$update public.ability_allocations set points = 4 where id = '66000000-0000-4000-8000-000000000001'$$,
  '23514', 'ability_allocations rows are immutable',
  'ability allocations cannot be updated'
);

select throws_ok(
  $$delete from public.ability_allocations where id = '66000000-0000-4000-8000-000000000001'$$,
  '23514', 'ability_allocations rows are immutable',
  'ability allocations cannot be deleted'
);

select lives_ok(
  $$
    insert into public.equipment_purchases (
      id, run_id, equipment_type_code, from_tier_rule_id, to_tier_rule_id,
      price_paid, purchased_week
    ) values (
      '67000000-0000-4000-8000-000000000001',
      '62000000-0000-4000-8000-000000000001',
      'camera',
      null,
      '00000000-0000-4000-8100-000000001402',
      30000,
      2
    )
  $$,
  'a first equipment purchase can omit the previous tier'
);

select lives_ok(
  $$
    insert into public.equipment_purchases (
      id, run_id, equipment_type_code, from_tier_rule_id, to_tier_rule_id,
      price_paid, purchased_week
    ) values (
      '67000000-0000-4000-8000-000000000002',
      '62000000-0000-4000-8000-000000000001',
      'camera',
      '00000000-0000-4000-8100-000000001402',
      '00000000-0000-4000-8100-000000001403',
      150000,
      3
    )
  $$,
  'an equipment replacement records both previous and next tiers'
);

select throws_ok(
  $$
    insert into public.equipment_purchases (
      run_id, equipment_type_code, to_tier_rule_id, price_paid, purchased_week
    ) values (
      '62000000-0000-4000-8000-000000000001',
      'camera',
      '00000000-0000-4000-8100-000000001404',
      -1,
      4
    )
  $$,
  '23514', null, 'negative equipment purchase prices are rejected'
);

select throws_ok(
  $$
    insert into public.equipment_purchases (
      run_id, equipment_type_code, to_tier_rule_id, price_paid, purchased_week
    ) values (
      '62000000-0000-4000-8000-000000000001',
      'camera',
      '00000000-0000-4000-8100-000000001404',
      500000,
      0
    )
  $$,
  '23514', null, 'equipment purchase weeks must be positive'
);

select throws_ok(
  $$update public.equipment_purchases set price_paid = 1 where id = '67000000-0000-4000-8000-000000000001'$$,
  '23514', 'equipment_purchases rows are immutable',
  'equipment purchases cannot be updated'
);

select throws_ok(
  $$delete from public.equipment_purchases where id = '67000000-0000-4000-8000-000000000001'$$,
  '23514', 'equipment_purchases rows are immutable',
  'equipment purchases cannot be deleted'
);

select * from finish();

rollback;
