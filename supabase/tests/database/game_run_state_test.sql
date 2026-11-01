begin;

set local search_path = extensions, public, pg_catalog;

select plan(98);

select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'game_runs', 'game_runs exists');
select has_table('public', 'run_state', 'run_state exists');
select has_table('public', 'run_abilities', 'run_abilities exists');
select has_table('public', 'run_equipment', 'run_equipment exists');
select has_table('public', 'run_feature_unlocks', 'run_feature_unlocks exists');
select has_table('public', 'run_conditions', 'run_conditions exists');
select has_table('public', 'run_goals', 'run_goals exists');

select has_pk('public', 'profiles', 'profiles has a primary key');
select has_pk('public', 'game_runs', 'game_runs has a primary key');
select has_pk('public', 'run_state', 'run_state has a primary key');
select has_pk('public', 'run_abilities', 'run_abilities has a primary key');
select has_pk('public', 'run_equipment', 'run_equipment has a primary key');
select has_pk('public', 'run_feature_unlocks', 'run_feature_unlocks has a primary key');
select has_pk('public', 'run_conditions', 'run_conditions has a primary key');
select has_pk('public', 'run_goals', 'run_goals has a primary key');

select has_fk('public', 'profiles', 'profiles has an auth user foreign key');
select has_fk('public', 'game_runs', 'game_runs has foreign keys');
select has_fk('public', 'run_state', 'run_state has foreign keys');
select has_fk('public', 'run_abilities', 'run_abilities has foreign keys');
select has_fk('public', 'run_equipment', 'run_equipment has foreign keys');
select has_fk('public', 'run_feature_unlocks', 'run_feature_unlocks has foreign keys');
select has_fk('public', 'run_conditions', 'run_conditions has foreign keys');
select has_fk('public', 'run_goals', 'run_goals has foreign keys');

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_constraint
    where conname in ('profiles_user_id_fkey', 'game_runs_user_id_fkey')
      and confrelid = 'auth.users'::regclass
      and contype = 'f'
  ),
  2,
  'profiles and game_runs reference auth.users'
);

select ok(
  not exists (
    select 1
    from (values
      ('game_runs_rule_set_channel_rule_fkey'),
      ('game_runs_rule_set_specialty_fkey'),
      ('game_runs_status_check'),
      ('game_runs_completion_state_check'),
      ('run_state_current_week_positive_check'),
      ('run_state_cash_nonnegative_check'),
      ('run_abilities_value_range_check'),
      ('run_equipment_acquired_week_nonnegative_check'),
      ('run_feature_unlocks_week_range_check'),
      ('run_conditions_unavailable_period_check'),
      ('run_goals_run_goal_rule_key'),
      ('run_goals_achievement_state_check')
    ) as expected(constraint_name)
    where not exists (
      select 1
      from pg_catalog.pg_constraint
      where connamespace = 'public'::regnamespace
        and conname = expected.constraint_name
    )
  ),
  'required foreign key, unique, and check constraints exist'
);

select ok(
  not exists (
    select 1
    from (values
      ('game_runs', 'user_id'),
      ('game_runs', 'rule_set_id'),
      ('game_runs', 'channel_rule_id'),
      ('game_runs', 'channel_name'),
      ('game_runs', 'status'),
      ('run_state', 'posting_frequency_rule_id'),
      ('run_state', 'cash'),
      ('run_abilities', 'value'),
      ('run_equipment', 'equipment_tier_rule_id'),
      ('run_feature_unlocks', 'active_from_week'),
      ('run_conditions', 'duration_weeks'),
      ('run_goals', 'status')
    ) as expected(table_name, column_name)
    where not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and information_schema.columns.table_name = expected.table_name
        and information_schema.columns.column_name = expected.column_name
        and is_nullable = 'NO'
    )
  ),
  'required current-state columns are not nullable'
);

select ok(
  not exists (
    select 1
    from (values
      ('game_runs_one_active_per_user_idx'),
      ('run_goals_one_active_per_run_idx')
    ) as expected(index_name)
    where not exists (
      select 1
      from pg_catalog.pg_indexes
      where schemaname = 'public'
        and pg_indexes.indexname = expected.index_name
        and indexdef like 'CREATE UNIQUE INDEX%WHERE %'
    )
  ),
  'active game and active goal partial unique indexes exist'
);

insert into auth.users (id)
select ('10000000-0000-4000-8000-' || lpad(sequence_number::text, 12, '0'))::uuid
from generate_series(1, 20) as users(sequence_number);

insert into public.profiles (user_id)
values ('10000000-0000-4000-8000-000000000001');

select is(
  (select count(*)::integer from public.profiles where user_id = '10000000-0000-4000-8000-000000000001'),
  1,
  'an auth user can own one profile'
);

select throws_ok(
  $$insert into public.profiles (user_id) values ('10000000-0000-4000-8000-000000000001')$$,
  '23505', null, 'duplicate profiles are rejected'
);

select throws_ok(
  $$insert into public.profiles (user_id) values ('10000000-0000-4000-8000-999999999999')$$,
  '23503', null, 'profiles require an auth user'
);

insert into public.rule_sets (id, version)
values ('20000000-0000-4000-8000-000000000001', 'be005-other-version');

insert into public.channel_rules (id, rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability)
values
  ('20000000-0000-4000-8100-000000000001', '20000000-0000-4000-8000-000000000001', 'mainstream', 1, 0.001),
  ('20000000-0000-4000-8100-000000000002', '20000000-0000-4000-8000-000000000001', 'specialized', 1, 0.001);

insert into public.rule_set_specialties (rule_set_id, specialty_code)
values ('20000000-0000-4000-8000-000000000001', 'science');

insert into public.posting_frequency_rules (
  id, rule_set_id, videos_per_week, view_multiplier, energy_cost, ability_points_awarded
)
values ('20000000-0000-4000-8100-000000000003', '20000000-0000-4000-8000-000000000001', 1, 1, 3, 3);

select lives_ok(
  $$
    insert into public.game_runs (
      id, user_id, rule_set_id, channel_rule_id, channel_name
    ) values (
      '30000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001001',
      'Mainstream channel'
    )
  $$,
  'a non-specialized game run can be created without a specialty'
);

select lives_ok(
  $$
    insert into public.game_runs (
      id, user_id, rule_set_id, channel_rule_id, specialty_code, channel_name
    ) values (
      '30000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000003',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001002',
      'science',
      'Science channel'
    )
  $$,
  'a specialized game run accepts an enabled specialty'
);

select throws_ok(
  $$
    insert into public.game_runs (user_id, rule_set_id, channel_rule_id, channel_name)
    values (
      '10000000-0000-4000-8000-000000000002',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001003',
      'Second active channel'
    )
  $$,
  '23505', null, 'one user cannot own two active game runs'
);

update public.game_runs
set status = 'abandoned', completed_at = statement_timestamp()
where id = '30000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    insert into public.game_runs (
      id, user_id, rule_set_id, channel_rule_id, channel_name
    ) values (
      '30000000-0000-4000-8000-000000000003',
      '10000000-0000-4000-8000-000000000002',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001003',
      'New life after abandonment'
    )
  $$,
  'a completed run does not prevent a new active run'
);

insert into public.game_runs (
  id, user_id, rule_set_id, channel_rule_id, channel_name
) values (
  '30000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000005',
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001001',
  'Constraint test channel'
);

select throws_ok(
  $$
    insert into public.game_runs (user_id, rule_set_id, channel_rule_id, channel_name)
    values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001002',
      'Missing specialty'
    )
  $$,
  '23514', 'Specialized game runs require a specialty',
  'specialized runs require a specialty'
);

select throws_ok(
  $$
    insert into public.game_runs (
      user_id, rule_set_id, channel_rule_id, specialty_code, channel_name
    ) values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001001',
      'science',
      'Unexpected specialty'
    )
  $$,
  '23514', 'Only specialized game runs may have a specialty',
  'non-specialized runs reject specialties'
);

select throws_ok(
  $$
    insert into public.game_runs (
      user_id, rule_set_id, channel_rule_id, specialty_code, channel_name
    ) values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001002',
      'not_enabled',
      'Invalid specialty'
    )
  $$,
  '23503', null, 'specialties must be enabled in the selected rule set'
);

select throws_ok(
  $$
    insert into public.game_runs (user_id, rule_set_id, channel_rule_id, channel_name)
    values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8100-000000000001',
      'Mixed rule versions'
    )
  $$,
  '23503', null, 'channel rules cannot be mixed with another rule set'
);

select throws_ok(
  $$update public.game_runs set user_id = '10000000-0000-4000-8000-000000000005' where id = '30000000-0000-4000-8000-000000000002'$$,
  '23514', 'Game run ownership and starting selections are immutable',
  'game run ownership cannot be reassigned'
);

select throws_ok(
  $$update public.game_runs set rule_set_id = '20000000-0000-4000-8000-000000000001' where id = '30000000-0000-4000-8000-000000000002'$$,
  '23514', 'Game run ownership and starting selections are immutable',
  'the rule set cannot be changed after start'
);

select throws_ok(
  $$update public.game_runs set channel_rule_id = '00000000-0000-4000-8100-000000001001' where id = '30000000-0000-4000-8000-000000000002'$$,
  '23514', 'Game run ownership and starting selections are immutable',
  'the channel rule cannot be changed after start'
);

select throws_ok(
  $$update public.game_runs set specialty_code = 'baseball' where id = '30000000-0000-4000-8000-000000000002'$$,
  '23514', 'Game run ownership and starting selections are immutable',
  'the specialty cannot be changed after start'
);

select lives_ok(
  $$update public.game_runs set channel_name = 'Renamed science channel' where id = '30000000-0000-4000-8000-000000000002'$$,
  'channel names remain editable'
);

select throws_ok(
  $$
    insert into public.game_runs (user_id, rule_set_id, channel_rule_id, channel_name, status)
    values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001001',
      'Invalid status',
      'paused'
    )
  $$,
  '23514', null, 'unknown game run statuses are rejected'
);

select throws_ok(
  $$
    insert into public.game_runs (
      user_id, rule_set_id, channel_rule_id, channel_name, completed_at
    ) values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001001',
      'Active but completed',
      statement_timestamp()
    )
  $$,
  '23514', null, 'active runs cannot have a completion time'
);

select throws_ok(
  $$
    insert into public.game_runs (
      user_id, rule_set_id, channel_rule_id, channel_name, status
    ) values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001001',
      'Completed without time',
      'cleared'
    )
  $$,
  '23514', null, 'completed runs require a completion time'
);

select throws_ok(
  $$
    insert into public.game_runs (user_id, rule_set_id, channel_rule_id, channel_name)
    values (
      '10000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001001',
      '   '
    )
  $$,
  '23514', null, 'blank channel names are rejected'
);

insert into public.run_state (run_id, posting_frequency_rule_id)
values (
  '30000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8100-000000001201'
);

select is(
  (
    select jsonb_build_array(
      current_week, cash, energy, subscribers, cumulative_views, flame_count, state_version
    )
    from public.run_state
    where run_id = '30000000-0000-4000-8000-000000000002'
  ),
  '[1, 100000, 100, 0, 0, 0, 0]'::jsonb,
  'run state defaults match the game specification'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id) values ('30000000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001201')$$,
  '23505', null, 'one game run can have only one current state row'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, cash) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001201', -1)$$,
  '23514', null, 'negative cash is rejected'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, subscribers) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001201', -1)$$,
  '23514', null, 'negative subscribers are rejected'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, cumulative_views) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001201', -1)$$,
  '23514', null, 'negative cumulative views are rejected'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, current_week) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001201', 0)$$,
  '23514', null, 'week zero is rejected'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, state_version) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001201', -1)$$,
  '23514', null, 'negative state versions are rejected'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, energy) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001201', -1)$$,
  '23514', null, 'negative energy is rejected'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, flame_count) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001201', -1)$$,
  '23514', null, 'negative flame counts are rejected'
);

select lives_ok(
  $$
    insert into public.run_state (run_id, posting_frequency_rule_id)
    values (
      '30000000-0000-4000-8000-000000000003',
      '20000000-0000-4000-8100-000000000003'
    )
  $$,
  'posting-frequency rule-set matching is explicitly deferred to BE-009'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id) values ('30000000-0000-4000-8000-000000000004', '99999999-9999-4999-8999-999999999999')$$,
  '23503', null, 'unknown posting-frequency rules are rejected'
);

insert into public.run_abilities (run_id, ability_code, value)
select '30000000-0000-4000-8000-000000000002', code, 10
from public.ability_definitions;

select is(
  (select count(*)::integer from public.run_abilities where run_id = '30000000-0000-4000-8000-000000000002'),
  6,
  'all six current abilities can be stored as rows'
);

select is(
  (select min(value) = 10 and max(value) = 10 from public.run_abilities where run_id = '30000000-0000-4000-8000-000000000002'),
  true,
  'all six initial ability values can be set to ten'
);

select throws_ok(
  $$insert into public.run_abilities (run_id, ability_code, value) values ('30000000-0000-4000-8000-000000000002', 'planning', 10)$$,
  '23505', null, 'duplicate abilities are rejected for one game run'
);

select throws_ok(
  $$insert into public.run_abilities (run_id, ability_code, value) values ('30000000-0000-4000-8000-000000000003', 'planning', -1)$$,
  '23514', null, 'ability values below zero are rejected'
);

select throws_ok(
  $$insert into public.run_abilities (run_id, ability_code, value) values ('30000000-0000-4000-8000-000000000003', 'planning', 101)$$,
  '23514', null, 'ability values above one hundred are rejected'
);

select throws_ok(
  $$insert into public.run_abilities (run_id, ability_code, value) values ('30000000-0000-4000-8000-000000000003', 'unknown', 10)$$,
  '23503', null, 'unknown abilities are rejected'
);

insert into public.run_equipment (
  run_id, equipment_type_code, equipment_tier_rule_id, acquired_week
)
values (
  '30000000-0000-4000-8000-000000000002',
  'camera',
  '00000000-0000-4000-8100-000000001402',
  1
);

select throws_ok(
  $$insert into public.run_equipment (run_id, equipment_type_code, equipment_tier_rule_id, acquired_week) values ('30000000-0000-4000-8000-000000000002', 'camera', '00000000-0000-4000-8100-000000001403', 2)$$,
  '23505', null, 'one run cannot own duplicate rows for an equipment type'
);

select throws_ok(
  $$insert into public.run_equipment (run_id, equipment_type_code, equipment_tier_rule_id, acquired_week) values ('30000000-0000-4000-8000-000000000003', 'unknown', '00000000-0000-4000-8100-000000001402', 1)$$,
  '23503', null, 'unknown equipment types are rejected'
);

select throws_ok(
  $$insert into public.run_equipment (run_id, equipment_type_code, equipment_tier_rule_id, acquired_week) values ('30000000-0000-4000-8000-000000000003', 'camera', '99999999-9999-4999-8999-999999999999', 1)$$,
  '23503', null, 'unknown equipment tier rules are rejected'
);

select throws_ok(
  $$insert into public.run_equipment (run_id, equipment_type_code, equipment_tier_rule_id, acquired_week) values ('30000000-0000-4000-8000-000000000003', 'camera', '00000000-0000-4000-8100-000000001402', -1)$$,
  '23514', null, 'negative equipment acquisition weeks are rejected'
);

insert into public.run_feature_unlocks (
  run_id, feature_rule_id, unlocked_week, active_from_week
)
values (
  '30000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8100-000000001501',
  10,
  11
);

select throws_ok(
  $$insert into public.run_feature_unlocks (run_id, feature_rule_id, unlocked_week, active_from_week) values ('30000000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001501', 12, 13)$$,
  '23505', null, 'the same feature cannot be unlocked twice'
);

select throws_ok(
  $$insert into public.run_feature_unlocks (run_id, feature_rule_id, unlocked_week, active_from_week) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001502', 10, 9)$$,
  '23514', null, 'features cannot activate before their unlock week'
);

select throws_ok(
  $$insert into public.run_feature_unlocks (run_id, feature_rule_id, unlocked_week, active_from_week) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001502', 0, 1)$$,
  '23514', null, 'feature unlock weeks must be positive'
);

select throws_ok(
  $$insert into public.run_feature_unlocks (run_id, feature_rule_id, unlocked_week, active_from_week) values ('30000000-0000-4000-8000-000000000004', '99999999-9999-4999-8999-999999999999', 1, 1)$$,
  '23503', null, 'unknown feature rules are rejected'
);

insert into public.run_conditions (
  id, run_id, health_risk_rule_id, started_week, duration_weeks,
  unavailable_from_week, unavailable_through_week
)
values
  (
    '40000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8100-000000002102',
    10, 2, 11, 12
  ),
  (
    '40000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8100-000000002103',
    20, 3, 21, 23
  );

select is(
  (select count(*)::integer from public.run_conditions where run_id = '30000000-0000-4000-8000-000000000002'),
  2,
  'one game run can retain multiple condition history rows'
);

select throws_ok(
  $$insert into public.run_conditions (run_id, health_risk_rule_id, started_week, duration_weeks, unavailable_from_week, unavailable_through_week) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000002102', 10, 0, 11, 11)$$,
  '23514', null, 'zero-length conditions are rejected'
);

select throws_ok(
  $$insert into public.run_conditions (run_id, health_risk_rule_id, started_week, duration_weeks, unavailable_from_week, unavailable_through_week) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000002102', 0, 1, 1, 1)$$,
  '23514', null, 'condition start weeks must be positive'
);

select throws_ok(
  $$insert into public.run_conditions (run_id, health_risk_rule_id, started_week, duration_weeks, unavailable_from_week, unavailable_through_week) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000002102', 10, 2, 10, 11)$$,
  '23514', null, 'unavailability must begin after the condition starts'
);

select throws_ok(
  $$insert into public.run_conditions (run_id, health_risk_rule_id, started_week, duration_weeks, unavailable_from_week, unavailable_through_week) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000002102', 10, 2, 11, 13)$$,
  '23514', null, 'unavailability end weeks must match the duration'
);

insert into public.run_goals (
  id, run_id, goal_rule_id, started_week, deadline_week, status
)
values (
  '50000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8100-000000001801',
  1,
  156,
  'active'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, status) values ('30000000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001801', 157, 312, 'failed')$$,
  '23505', null, 'one run cannot reuse the same goal rule'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, status) values ('30000000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001802', 157, 312, 'active')$$,
  '23505', null, 'one game run cannot have two active goals'
);

update public.run_goals
set status = 'achieved', achieved_week = 100
where id = '50000000-0000-4000-8000-000000000001';

insert into public.run_goals (
  id, run_id, goal_rule_id, started_week, deadline_week, status
)
values (
  '50000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8100-000000001802',
  101,
  256,
  'active'
);

select is(
  (select count(*)::integer from public.run_goals where run_id = '30000000-0000-4000-8000-000000000002'),
  2,
  'achieved goals remain alongside the next active goal'
);

update public.run_goals
set status = 'failed'
where id = '50000000-0000-4000-8000-000000000002';

insert into public.run_goals (
  id, run_id, goal_rule_id, started_week, deadline_week, status
)
values (
  '50000000-0000-4000-8000-000000000003',
  '30000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8100-000000001803',
  257,
  412,
  'active'
);

select is(
  (
    select jsonb_build_array(
      count(*) filter (where status = 'achieved'),
      count(*) filter (where status = 'failed'),
      count(*) filter (where status = 'active')
    )
    from public.run_goals
    where run_id = '30000000-0000-4000-8000-000000000002'
  ),
  '[1, 1, 1]'::jsonb,
  'achieved and failed goal history remains beside one active goal'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, status) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001803', 0, 156, 'active')$$,
  '23514', null, 'goal start weeks must be positive'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, status) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001803', 10, 9, 'active')$$,
  '23514', null, 'goal deadlines cannot precede their start'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, status) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001803', 1, 156, 'achieved')$$,
  '23514', null, 'achieved goals require an achieved week'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, achieved_week, status) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001803', 1, 156, 10, 'active')$$,
  '23514', null, 'active goals cannot have an achieved week'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, achieved_week, status) values ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8100-000000001803', 10, 156, 9, 'achieved')$$,
  '23514', null, 'goal achievement weeks cannot precede their start'
);

select lives_ok(
  $$
    do $block$
    begin
      insert into public.game_runs (
        id, user_id, rule_set_id, channel_rule_id, specialty_code, channel_name
      ) values (
        '60000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000010',
        '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8100-000000001002',
        'science',
        'Atomic start'
      );

      insert into public.run_state (run_id, posting_frequency_rule_id)
      values (
        '60000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8100-000000001201'
      );

      insert into public.run_abilities (run_id, ability_code, value)
      select '60000000-0000-4000-8000-000000000001', code, 10
      from public.ability_definitions;

      insert into public.run_goals (
        run_id, goal_rule_id, started_week, deadline_week, status
      ) values (
        '60000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8100-000000001801',
        1,
        156,
        'active'
      );
    end
    $block$
  $$,
  'the complete initial game state can be created in one transaction'
);

select is(
  (select count(*)::integer from public.game_runs where id = '60000000-0000-4000-8000-000000000001'),
  1,
  'initial creation stores one game run'
);

select is(
  (
    select jsonb_build_array(
      current_week, posting_frequency_rule_id::text, cash, energy,
      subscribers, cumulative_views, flame_count, state_version
    )
    from public.run_state
    where run_id = '60000000-0000-4000-8000-000000000001'
  ),
  '[1, "00000000-0000-4000-8100-000000001201", 100000, 100, 0, 0, 0, 0]'::jsonb,
  'initial creation stores the specified current-state values and weekly frequency'
);

select is(
  (
    select jsonb_build_array(count(*), min(value), max(value))
    from public.run_abilities
    where run_id = '60000000-0000-4000-8000-000000000001'
  ),
  '[6, 10, 10]'::jsonb,
  'initial creation stores six abilities at ten'
);

select is(
  (
    select jsonb_build_array(started_week, deadline_week, achieved_week, status)
    from public.run_goals
    where run_id = '60000000-0000-4000-8000-000000000001'
  ),
  '[1, 156, null, "active"]'::jsonb,
  'initial creation stores only the active stage-one goal'
);

select is(
  (select count(*)::integer from public.run_equipment where run_id = '60000000-0000-4000-8000-000000000001'),
  0,
  'initial creation does not create equipment rows'
);

select is(
  (select count(*)::integer from public.run_feature_unlocks where run_id = '60000000-0000-4000-8000-000000000001'),
  0,
  'initial creation does not create feature unlock rows'
);

select is(
  (select count(*)::integer from public.run_conditions where run_id = '60000000-0000-4000-8000-000000000001'),
  0,
  'initial creation does not create condition rows'
);

select lives_ok(
  $$
    do $block$
    begin
      begin
        insert into public.game_runs (
          id, user_id, rule_set_id, channel_rule_id, channel_name
        ) values (
          '60000000-0000-4000-8000-000000000002',
          '10000000-0000-4000-8000-000000000011',
          '00000000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8100-000000001001',
          'Rolled back start'
        );

        insert into public.run_state (run_id, posting_frequency_rule_id)
        values (
          '60000000-0000-4000-8000-000000000002',
          '00000000-0000-4000-8100-000000001201'
        );

        insert into public.run_abilities (run_id, ability_code, value)
        values
          ('60000000-0000-4000-8000-000000000002', 'planning', 10),
          ('60000000-0000-4000-8000-000000000002', 'planning', 10);
      exception
        when unique_violation then null;
      end;
    end
    $block$
  $$,
  'an initial-state transaction can handle an intermediate failure'
);

select is(
  (select count(*)::integer from public.game_runs where id = '60000000-0000-4000-8000-000000000002'),
  0,
  'an intermediate failure rolls back the game run instead of leaving partial state'
);

select is(
  (select count(*)::integer from public.run_state where run_id = '60000000-0000-4000-8000-000000000002'),
  0,
  'an intermediate failure also rolls back the current-state row'
);

select * from finish();

rollback;
