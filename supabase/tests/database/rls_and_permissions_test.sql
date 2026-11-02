begin;

set local search_path = extensions, public, pg_catalog;

select plan(40);

select ok(
  not exists (
    select 1
    from (values
      ('profiles'), ('game_runs'), ('run_state'), ('run_abilities'),
      ('run_equipment'), ('run_feature_unlocks'), ('run_conditions'), ('run_goals'),
      ('player_ideas'), ('idea_evaluations'), ('idea_queue_entries'), ('weekly_actions'),
      ('ability_point_grants'), ('ability_allocations'), ('equipment_purchases'),
      ('system_idea_cycles'), ('system_idea_cycle_entries'), ('advance_week_executions'),
      ('week_results'), ('videos'), ('video_calculations'), ('occurred_events'),
      ('game_terminations')
    ) as expected(table_name)
    join pg_catalog.pg_class as protected_table
      on protected_table.relnamespace = 'public'::regnamespace
     and protected_table.relname = expected.table_name
    where not protected_table.relrowsecurity
  ),
  'RLS is enabled on every user-data table'
);

select ok(
  not pg_catalog.has_table_privilege('anon', 'public.game_runs', 'SELECT'),
  'anon has no game data SELECT privilege'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class as public_table
    where public_table.relnamespace = 'public'::regnamespace
      and public_table.relkind in ('r', 'p')
      and (
        pg_catalog.has_table_privilege('anon', public_table.oid, 'SELECT')
        or pg_catalog.has_table_privilege('anon', public_table.oid, 'INSERT')
        or pg_catalog.has_table_privilege('anon', public_table.oid, 'UPDATE')
        or pg_catalog.has_table_privilege('anon', public_table.oid, 'DELETE')
      )
  ),
  'anon has no privileges on public schema tables'
);

select ok(
  pg_catalog.has_table_privilege('authenticated', 'public.game_runs', 'SELECT'),
  'authenticated may select owned game runs through RLS'
);

select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.game_runs', 'INSERT')
  and not pg_catalog.has_table_privilege('authenticated', 'public.game_runs', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.game_runs', 'DELETE'),
  'authenticated cannot directly mutate game runs'
);

select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.idea_evaluations', 'SELECT'),
  'AI evaluations are not granted to authenticated'
);

select ok(
  not exists (
    select 1
    from (values
      ('channel_types'), ('specialty_categories'), ('ability_definitions'),
      ('equipment_types'), ('action_definitions'), ('feature_definitions'),
      ('event_categories'), ('event_definitions'), ('rule_sets'), ('global_rules'),
      ('channel_rules'), ('channel_ability_weights'), ('rule_set_specialties'),
      ('posting_frequency_rules'), ('idea_score_band_rules'),
      ('equipment_tier_rules'), ('feature_rules'), ('action_rules'),
      ('sponsorship_reward_rules'), ('goal_rules'), ('event_category_rules'),
      ('event_rules'), ('health_risk_rules'), ('system_idea_templates'),
      ('rule_set_system_ideas')
    ) as protected(table_name)
    where pg_catalog.has_table_privilege(
      'authenticated',
      pg_catalog.format('public.%I', protected.table_name),
      'INSERT'
    )
      or pg_catalog.has_table_privilege(
        'authenticated',
        pg_catalog.format('public.%I', protected.table_name),
        'UPDATE'
      )
      or pg_catalog.has_table_privilege(
        'authenticated',
        pg_catalog.format('public.%I', protected.table_name),
        'DELETE'
      )
  ),
  'authenticated has no write privileges on catalogs or rules'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as internal_function
    where internal_function.pronamespace = 'public'::regnamespace
      and (
        pg_catalog.has_function_privilege('anon', internal_function.oid, 'EXECUTE')
        or pg_catalog.has_function_privilege('authenticated', internal_function.oid, 'EXECUTE')
      )
  ),
  'anon and authenticated cannot execute public schema functions directly'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as server_function
    where server_function.pronamespace = 'public'::regnamespace
      and not pg_catalog.has_function_privilege('service_role', server_function.oid, 'EXECUTE')
  ),
  'service_role retains execute access to server functions'
);

insert into auth.users (id)
values
  ('a1000000-0000-4000-8000-000000000001'),
  ('b1000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000003');

-- Fixtures are created as the database owner. Replica mode skips the business
-- triggers whose behavior has dedicated tests while preserving table checks.
set local session_replication_role = replica;

insert into public.profiles (user_id, display_name)
values ('b1000000-0000-4000-8000-000000000002', 'User B');

insert into public.rule_sets (id, version, status, published_at)
values (
  'd1000000-0000-4000-8000-000000000001',
  'rls-published',
  'retired',
  statement_timestamp()
);

insert into public.global_rules (
  rule_set_id, base_views_min, base_views_max, energy_max,
  unavailable_energy_recovery, ideas_per_week, idea_stock_max,
  flame_subscriber_loss_rate, flame_energy_loss, ban_flame_count,
  ad_revenue_per_view, system_idea_view_multiplier,
  system_idea_subscriber_conversion_rate
)
values (
  'd1000000-0000-4000-8000-000000000001', 0, 100, 100,
  10, 3, 30, 0.05, 20, 3, 0.2, 0.6, 0.02
);

insert into public.system_idea_templates (
  id, code, channel_type_code, title, description
)
values
  (
    'e1000000-0000-4000-8000-000000000001',
    'rls_published_idea',
    'mainstream',
    'Published system idea',
    'Visible through a published rule set.'
  ),
  (
    'e1000000-0000-4000-8000-000000000002',
    'rls_draft_idea',
    'mainstream',
    'Draft system idea',
    'Must remain hidden with its draft rule set.'
  );

insert into public.rule_set_system_ideas (
  rule_set_id, system_idea_template_id
)
values
  ('d1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000002');

insert into public.game_runs (
  id, user_id, rule_set_id, channel_rule_id, channel_name
)
values
  (
    'a2000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'User A channel'
  ),
  (
    'b2000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'User B channel'
  );

insert into public.run_state (run_id, posting_frequency_rule_id)
values
  ('a2000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001201'),
  ('b2000000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001201');

insert into public.player_ideas (id, run_id, title, created_week)
values
  ('a3000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'User A idea', 1),
  ('b3000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002', 'User B idea', 1);

insert into public.idea_evaluations (
  idea_id, score, evaluation_status, model, prompt_version
)
values
  ('a3000000-0000-4000-8000-000000000001', 80, 'completed', 'test-model', 'v1'),
  ('b3000000-0000-4000-8000-000000000002', 20, 'completed', 'test-model', 'v1');

insert into public.ability_point_grants (
  id, run_id, earned_week, available_from_week, amount, status
)
values
  ('a4000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 1, 1, 5, 'available'),
  ('b4000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002', 1, 1, 5, 'available');

insert into public.ability_allocations (grant_id, ability_code, points, allocated_week)
values
  ('a4000000-0000-4000-8000-000000000001', 'planning', 1, 1),
  ('b4000000-0000-4000-8000-000000000002', 'planning', 1, 1);

insert into public.weekly_actions (id, run_id, week_number, action_rule_id)
values
  ('a5000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 1, '00000000-0000-4000-8100-000000001801'),
  ('b5000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002', 1, '00000000-0000-4000-8100-000000001801');

insert into public.advance_week_executions (
  idempotency_key, run_id, attempted_week, expected_state_version, outcome
)
values
  ('a6000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 1, 0, 'week_committed'),
  ('b6000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002', 1, 0, 'week_committed');

insert into public.week_results (
  id, execution_id, run_id, week_number, weekly_action_id,
  posting_frequency_rule_id, views_before_event, final_views,
  subscribers_before, max_subscribers_during_week, subscribers_after,
  energy_before, energy_after, cash_before, cash_after, ad_revenue,
  flame_count_after, run_status_after, state_version_after
)
values
  (
    'a7000000-0000-4000-8000-000000000001',
    'a6000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000001', 1,
    'a5000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001201',
    10, 10, 0, 1, 1, 100, 90, 100000, 100000, 0, 0, 'playing', 1
  ),
  (
    'b7000000-0000-4000-8000-000000000002',
    'b6000000-0000-4000-8000-000000000002',
    'b2000000-0000-4000-8000-000000000002', 1,
    'b5000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8100-000000001201',
    10, 10, 0, 1, 1, 100, 90, 100000, 100000, 0, 0, 'playing', 1
  );

insert into public.videos (
  id, week_result_id, sequence_number, player_idea_id, title_snapshot
)
values
  ('a8000000-0000-4000-8000-000000000001', 'a7000000-0000-4000-8000-000000000001', 1, 'a3000000-0000-4000-8000-000000000001', 'User A video'),
  ('b8000000-0000-4000-8000-000000000002', 'b7000000-0000-4000-8000-000000000002', 1, 'b3000000-0000-4000-8000-000000000002', 'User B video');

insert into public.video_calculations (
  video_id, base_views, subscriber_multiplier, ability_multiplier,
  idea_multiplier, posting_frequency_multiplier, channel_multiplier,
  equipment_multiplier, collaboration_multiplier, views_before_event,
  event_multiplier, final_views, conversion_rate, subscribers_gained
)
values
  ('a8000000-0000-4000-8000-000000000001', 10, 1, 1, 1, 1, 1, 1, 1, 10, 1, 10, 0.1, 1),
  ('b8000000-0000-4000-8000-000000000002', 10, 1, 1, 1, 1, 1, 1, 1, 10, 1, 10, 0.1, 1);

set local session_replication_role = origin;

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.game_runs),
  1,
  'user A can select only their own game run'
);

select is(
  (select channel_name from public.game_runs),
  'User A channel',
  'user B game run is hidden from user A'
);

select is(
  (select count(*)::integer from public.run_state),
  1,
  'direct child ownership follows the game run'
);

select is(
  (select count(*)::integer from public.ability_allocations),
  1,
  'ownership follows ability allocations through grants'
);

select is(
  (select count(*)::integer from public.video_calculations),
  1,
  'deep video calculation ownership follows videos and week results'
);

select lives_ok(
  $$insert into public.profiles (user_id, display_name) values ('a1000000-0000-4000-8000-000000000001', 'User A')$$,
  'user A can insert their own profile'
);

select lives_ok(
  $$update public.profiles set display_name = 'Updated A' where user_id = 'a1000000-0000-4000-8000-000000000001'$$,
  'user A can update their own profile'
);

select throws_ok(
  $$insert into public.profiles (user_id, display_name) values ('c1000000-0000-4000-8000-000000000003', 'Not A')$$,
  '42501',
  null,
  'user A cannot insert another user profile'
);

select lives_ok(
  $$update public.profiles set display_name = 'Stolen' where user_id = 'b1000000-0000-4000-8000-000000000002'$$,
  'user A cannot update another user profile'
);

select lives_ok(
  $$delete from public.profiles where user_id = 'b1000000-0000-4000-8000-000000000002'$$,
  'user A cannot delete another user profile'
);

select throws_ok(
  $$insert into public.game_runs (user_id, rule_set_id, channel_rule_id, channel_name) values ('b1000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001001', 'Blocked')$$,
  '42501',
  null,
  'authenticated cannot directly insert game runs for another user'
);

select throws_ok(
  $$update public.game_runs set channel_name = 'Blocked' where id = 'b2000000-0000-4000-8000-000000000002'$$,
  '42501',
  null,
  'authenticated cannot directly update game runs'
);

select throws_ok(
  $$delete from public.game_runs where id = 'b2000000-0000-4000-8000-000000000002'$$,
  '42501',
  null,
  'authenticated cannot directly delete game runs'
);

select throws_ok(
  $$select score from public.idea_evaluations where idea_id = 'a3000000-0000-4000-8000-000000000001'$$,
  '42501',
  null,
  'the owner cannot directly read their AI evaluation score'
);

select is(
  (select count(*)::integer from public.rule_sets where id = 'd1000000-0000-4000-8000-000000000001'),
  1,
  'authenticated can read a published rule set'
);

select is(
  (select count(*)::integer from public.global_rules where rule_set_id = 'd1000000-0000-4000-8000-000000000001'),
  1,
  'authenticated can read rules belonging to a published rule set'
);

select is(
  (select count(*)::integer from public.rule_sets where id = '00000000-0000-4000-8000-000000000001'),
  0,
  'authenticated cannot read a draft rule set'
);

select is(
  (select count(*)::integer from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  0,
  'authenticated cannot read rules belonging to a draft rule set'
);

select is(
  (select count(*)::integer from public.rule_set_system_ideas),
  1,
  'authenticated sees only system-idea associations for published rules'
);

select is(
  (select title from public.system_idea_templates),
  'Published system idea',
  'system idea templates linked only to draft rules remain hidden'
);

select ok(
  (select count(*) > 0 from public.channel_types),
  'authenticated can read static catalogs'
);

select throws_ok(
  $$insert into public.channel_types (code, name) values ('blocked', 'Blocked')$$,
  '42501',
  null,
  'authenticated cannot insert static catalog rows'
);

select throws_ok(
  $$update public.rule_sets set version = 'blocked' where id = 'd1000000-0000-4000-8000-000000000001'$$,
  '42501',
  null,
  'authenticated cannot update rules'
);

select throws_ok(
  $$delete from public.global_rules where rule_set_id = 'd1000000-0000-4000-8000-000000000001'$$,
  '42501',
  null,
  'authenticated cannot delete rules'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '';

select is(
  (select count(*)::integer from public.game_runs),
  0,
  'authenticated without a JWT subject cannot read game data'
);

reset role;
set local role anon;

select throws_ok(
  $$select * from public.game_runs$$,
  '42501',
  null,
  'anon cannot read game data'
);

select throws_ok(
  $$select * from public.channel_types$$,
  '42501',
  null,
  'anon cannot read static catalogs before Anonymous Sign-In'
);

reset role;

select is(
  (select display_name from public.profiles where user_id = 'b1000000-0000-4000-8000-000000000002'),
  'User B',
  'RLS prevented user A from changing user B profile'
);

select is(
  (select count(*)::integer from public.profiles where user_id = 'b1000000-0000-4000-8000-000000000002'),
  1,
  'RLS prevented user A from deleting user B profile'
);

select throws_ok(
  $$insert into public.game_runs (user_id, rule_set_id, channel_rule_id, specialty_code, channel_name) values ('c1000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001001', 'gaming', 'Invalid specialty')$$,
  '23514',
  null,
  'constraint triggers still execute after direct EXECUTE is revoked'
);

select lives_ok(
  $$insert into public.game_runs (user_id, rule_set_id, channel_rule_id, channel_name) values ('c1000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001001', 'Valid run')$$,
  'postgres can still perform server-side writes'
);

select * from finish();

rollback;
