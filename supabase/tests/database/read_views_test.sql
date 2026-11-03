begin;

set local search_path = extensions, public, pg_catalog;

select plan(36);

select has_view('public', 'current_game_view', 'current_game_view exists');
select has_view('public', 'idea_stock_view', 'idea_stock_view exists');
select has_view('public', 'week_history_view', 'week_history_view exists');
select has_view('public', 'video_result_view', 'video_result_view exists');

select ok(
  not exists (
    select 1
    from (values
      ('current_game_view'),
      ('idea_stock_view'),
      ('week_history_view'),
      ('video_result_view')
    ) as expected(view_name)
    join pg_catalog.pg_class as view_relation
      on view_relation.relnamespace = 'public'::regnamespace
     and view_relation.relname = expected.view_name
    where not coalesce(view_relation.reloptions, '{}'::text[]) @> array['security_invoker=true']
  ),
  'all read views use security_invoker'
);

select ok(
  not exists (
    select 1
    from (values
      ('current_game_view'),
      ('idea_stock_view'),
      ('week_history_view'),
      ('video_result_view')
    ) as expected(view_name)
    where not pg_catalog.has_table_privilege(
      'authenticated',
      pg_catalog.format('public.%I', expected.view_name),
      'SELECT'
    )
  ),
  'authenticated has SELECT on every read view'
);

select ok(
  not exists (
    select 1
    from (values
      ('current_game_view'),
      ('idea_stock_view'),
      ('week_history_view'),
      ('video_result_view')
    ) as expected(view_name)
    where pg_catalog.has_table_privilege(
      'anon',
      pg_catalog.format('public.%I', expected.view_name),
      'SELECT'
    )
  ),
  'anon has no SELECT on read views'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'current_game_view',
        'idea_stock_view',
        'week_history_view',
        'video_result_view'
      )
      and column_name in ('score', 'evaluation_status', 'model', 'prompt_version', 'evaluated_at')
  ),
  'client read views do not expose AI evaluation data'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'current_game_view',
        'idea_stock_view',
        'week_history_view',
        'video_result_view'
      )
      and (column_name = 'rule_set_id' or column_name like '%\_rule\_id' escape '\')
  ),
  'client read views do not expose internal rule identifiers'
);

select ok(
  not exists (
    select 1
    from (values
      ('current_game_view'),
      ('idea_stock_view'),
      ('week_history_view'),
      ('video_result_view')
    ) as expected(view_name)
    where pg_catalog.has_table_privilege(
      'authenticated',
      pg_catalog.format('public.%I', expected.view_name),
      'INSERT'
    )
    or pg_catalog.has_table_privilege(
      'authenticated',
      pg_catalog.format('public.%I', expected.view_name),
      'UPDATE'
    )
    or pg_catalog.has_table_privilege(
      'authenticated',
      pg_catalog.format('public.%I', expected.view_name),
      'DELETE'
    )
  ),
  'authenticated has no write privilege on read views'
);

select ok(
  not exists (
    select 1
    from (values
      ('current_game_view'),
      ('idea_stock_view'),
      ('week_history_view'),
      ('video_result_view')
    ) as expected(view_name)
    where pg_catalog.has_table_privilege(
      'anon',
      pg_catalog.format('public.%I', expected.view_name),
      'INSERT'
    )
    or pg_catalog.has_table_privilege(
      'anon',
      pg_catalog.format('public.%I', expected.view_name),
      'UPDATE'
    )
    or pg_catalog.has_table_privilege(
      'anon',
      pg_catalog.format('public.%I', expected.view_name),
      'DELETE'
    )
  ),
  'anon has no write privilege on read views'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class as view_relation
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        view_relation.relacl,
        pg_catalog.acldefault('r', view_relation.relowner)
      )
    ) as view_acl
    where view_relation.relnamespace = 'public'::regnamespace
      and view_relation.relname in (
        'current_game_view',
        'idea_stock_view',
        'week_history_view',
        'video_result_view'
      )
      and view_acl.grantee = 0
  ),
  'PUBLIC has no privilege on read views'
);

select ok(
  not exists (
    select 1
    from (values
      ('channel_type_code'),
      ('channel_type_name'),
      ('specialty_code'),
      ('specialty_name')
    ) as required(column_name)
    where not exists (
      select 1
      from information_schema.columns as view_column
      where view_column.table_schema = 'public'
        and view_column.table_name = 'current_game_view'
        and view_column.column_name = required.column_name
    )
  ),
  'current_game_view exposes channel type and specialty columns'
);

insert into auth.users (id)
values
  ('a1200000-0000-4000-8000-000000000001'),
  ('b1200000-0000-4000-8000-000000000002');

set local session_replication_role = replica;

insert into public.game_runs (
  id, user_id, rule_set_id, channel_rule_id, specialty_code, channel_name
)
values
  (
    'a1210000-0000-4000-8000-000000000001',
    'a1200000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001002',
    'baseball',
    'User A channel'
  ),
  (
    'b1210000-0000-4000-8000-000000000002',
    'b1200000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    null,
    'User B channel'
  );

insert into public.run_state (
  run_id, posting_frequency_rule_id, subscribers, cumulative_views
)
values
  ('a1210000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001201', 120, 1000),
  ('b1210000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001201', 50, 500);

insert into public.run_abilities (run_id, ability_code, value)
select
  'a1210000-0000-4000-8000-000000000001',
  ability.code,
  10 + ability.display_order
from public.ability_definitions as ability;

insert into public.run_equipment (
  run_id, equipment_type_code, equipment_tier_rule_id, acquired_week
)
values (
  'a1210000-0000-4000-8000-000000000001',
  'camera',
  '00000000-0000-4000-8100-000000001402',
  1
);

insert into public.run_feature_unlocks (
  run_id, feature_rule_id, unlocked_week, active_from_week
)
values (
  'a1210000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001501',
  1,
  2
);

insert into public.run_goals (
  id, run_id, goal_rule_id, started_week, deadline_week, status
)
values (
  'a1220000-0000-4000-8000-000000000001',
  'a1210000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001801',
  1,
  156,
  'active'
);

insert into public.run_conditions (
  id, run_id, health_risk_rule_id, started_week, duration_weeks,
  unavailable_from_week, unavailable_through_week
)
values (
  'a1220000-0000-4000-8000-000000000011',
  'a1210000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000002102',
  1,
  1,
  2,
  2
);

insert into public.player_ideas (id, run_id, title, created_week)
values
  ('a1230000-0000-4000-8000-000000000001', 'a1210000-0000-4000-8000-000000000001', 'User A queued idea', 1),
  ('a1230000-0000-4000-8000-000000000011', 'a1210000-0000-4000-8000-000000000001', 'User A published idea', 1),
  ('b1230000-0000-4000-8000-000000000002', 'b1210000-0000-4000-8000-000000000002', 'User B queued idea', 1),
  ('b1230000-0000-4000-8000-000000000012', 'b1210000-0000-4000-8000-000000000002', 'User B published idea', 1);

insert into public.idea_evaluations (
  idea_id, score, evaluation_status, model, prompt_version
)
values
  ('a1230000-0000-4000-8000-000000000001', 98, 'completed', 'secret-model', 'secret-prompt'),
  ('b1230000-0000-4000-8000-000000000002', 12, 'completed', 'secret-model', 'secret-prompt');

insert into public.idea_queue_entries (idea_id, run_id, position)
values
  ('a1230000-0000-4000-8000-000000000001', 'a1210000-0000-4000-8000-000000000001', 1),
  ('b1230000-0000-4000-8000-000000000002', 'b1210000-0000-4000-8000-000000000002', 1);

insert into public.weekly_actions (id, run_id, week_number, action_rule_id)
values
  ('a1240000-0000-4000-8000-000000000001', 'a1210000-0000-4000-8000-000000000001', 1, '00000000-0000-4000-8100-000000001602'),
  ('b1240000-0000-4000-8000-000000000002', 'b1210000-0000-4000-8000-000000000002', 1, '00000000-0000-4000-8100-000000001602');

insert into public.advance_week_executions (
  idempotency_key, run_id, attempted_week, expected_state_version, outcome
)
values
  ('a1250000-0000-4000-8000-000000000001', 'a1210000-0000-4000-8000-000000000001', 1, 0, 'week_committed'),
  ('b1250000-0000-4000-8000-000000000002', 'b1210000-0000-4000-8000-000000000002', 1, 0, 'week_committed');

insert into public.week_results (
  id, execution_id, run_id, week_number, weekly_action_id,
  posting_frequency_rule_id, views_before_event, final_views,
  subscribers_before, max_subscribers_during_week, subscribers_after,
  energy_before, energy_after, cash_before, cash_after, ad_revenue,
  flame_count_after, run_status_after, state_version_after
)
values
  (
    'a1260000-0000-4000-8000-000000000001',
    'a1250000-0000-4000-8000-000000000001',
    'a1210000-0000-4000-8000-000000000001', 1,
    'a1240000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001201',
    100, 200, 10, 30, 25, 100, 90, 100000, 100500, 40, 1, 'playing', 1
  ),
  (
    'b1260000-0000-4000-8000-000000000002',
    'b1250000-0000-4000-8000-000000000002',
    'b1210000-0000-4000-8000-000000000002', 1,
    'b1240000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8100-000000001201',
    50, 50, 5, 6, 6, 100, 90, 100000, 100000, 10, 0, 'playing', 1
  );

insert into public.occurred_events (
  id, week_result_id, event_definition_code, event_rule_id,
  sequence_number, display_metadata
)
values (
  'a1270000-0000-4000-8000-000000000001',
  'a1260000-0000-4000-8000-000000000001',
  'featured_in_recommendations',
  '00000000-0000-4000-8100-000000002001',
  1,
  '{"label":"double views"}'::jsonb
), (
  'a1270000-0000-4000-8000-000000000011',
  'a1260000-0000-4000-8000-000000000001',
  'flame',
  null,
  2,
  '{}'::jsonb
);

insert into public.videos (
  id, week_result_id, sequence_number, player_idea_id, title_snapshot
)
values
  ('a1280000-0000-4000-8000-000000000001', 'a1260000-0000-4000-8000-000000000001', 1, 'a1230000-0000-4000-8000-000000000011', 'User A video'),
  ('b1280000-0000-4000-8000-000000000002', 'b1260000-0000-4000-8000-000000000002', 1, 'b1230000-0000-4000-8000-000000000012', 'User B video');

insert into public.video_calculations (
  video_id, base_views, subscriber_multiplier, ability_multiplier,
  idea_multiplier, posting_frequency_multiplier, channel_multiplier,
  equipment_multiplier, collaboration_multiplier, views_before_event,
  event_multiplier, final_views, conversion_rate, subscribers_gained
)
values
  ('a1280000-0000-4000-8000-000000000001', 50, 1, 1, 1, 1, 1, 1, 2, 100, 2, 200, 0.1, 20),
  ('b1280000-0000-4000-8000-000000000002', 50, 1, 1, 1, 1, 1, 1, 1, 50, 1, 50, 0.02, 1);

set local session_replication_role = origin;

set local role authenticated;
set local request.jwt.claim.sub = 'a1200000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.current_game_view),
  1,
  'current_game_view returns only the current user game'
);

select is(
  (select specialty_name from public.current_game_view),
  '野球',
  'current_game_view resolves the selected specialty name'
);

select is(
  (select jsonb_array_length(abilities) from public.current_game_view),
  6,
  'current_game_view aggregates all six abilities'
);

select is(
  (select equipment #>> '{0,tier}' from public.current_game_view),
  'beginner',
  'current_game_view aggregates current equipment details'
);

select is(
  (select current_stage_number from public.current_game_view),
  1::smallint,
  'current_game_view includes the active goal'
);

select is(
  (select feature_unlocks #>> '{0,code}' from public.current_game_view),
  'ad_revenue',
  'current_game_view includes feature unlocks'
);

select is(
  (select count(*)::integer from public.idea_stock_view),
  1,
  'idea_stock_view returns only the current user queue'
);

select is(
  (select title from public.idea_stock_view),
  'User A queued idea',
  'idea_stock_view exposes the queued idea without evaluation data'
);

select is(
  (select idea_source from public.idea_stock_view),
  'player',
  'idea_stock_view identifies player ideas'
);

select ok(
  (select stock_status = 'queued' and is_pending from public.idea_stock_view),
  'idea_stock_view exposes only pending queued stock'
);

select is(
  (select count(*)::integer from public.week_history_view),
  1,
  'week_history_view returns only the current user history'
);

select is(
  (select subscriber_change from public.week_history_view),
  15::bigint,
  'week_history_view calculates subscriber change'
);

select is(
  (select action_name from public.week_history_view),
  '休憩',
  'week_history_view resolves the selected action name'
);

select is(
  (select stage_number from public.week_history_view),
  1::smallint,
  'week_history_view resolves the stage for the completed week'
);

select is(
  (select posted_video_count from public.week_history_view),
  1::smallint,
  'week_history_view reports the actual number of posted videos'
);

select ok(
  (select had_flame and flame_count_change = 1 from public.week_history_view),
  'week_history_view exposes the confirmed flame result'
);

select ok(
  (select health_condition_started
    and health_condition_duration_weeks = 1
    and not was_activity_unavailable
   from public.week_history_view),
  'week_history_view exposes the confirmed health outcome'
);

select is(
  (select events #>> '{0,code}' from public.week_history_view),
  'featured_in_recommendations',
  'week_history_view includes ordered event summaries'
);

select is(
  (select count(*)::integer from public.video_result_view),
  1,
  'video_result_view returns only the current user videos'
);

select is(
  (select collaboration_multiplier from public.video_result_view),
  2::numeric,
  'video_result_view exposes calculation multipliers'
);

select is(
  (select idea_source from public.video_result_view),
  'player',
  'video_result_view identifies the idea source without exposing rule identifiers'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '';

select is(
  (select count(*)::integer from public.current_game_view),
  0,
  'authenticated without a JWT subject sees no current game'
);

reset role;
set local role anon;

select throws_ok(
  $$select * from public.current_game_view$$,
  '42501',
  null,
  'anon cannot query read views'
);

reset role;

select * from finish();

rollback;
