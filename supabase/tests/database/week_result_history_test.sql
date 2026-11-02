begin;

set local search_path = extensions, public, pg_catalog;

select plan(81);

select has_table('public', 'advance_week_executions', 'advance_week_executions exists');
select has_table('public', 'week_results', 'week_results exists');
select has_table('public', 'videos', 'videos exists');
select has_table('public', 'video_calculations', 'video_calculations exists');
select has_table('public', 'occurred_events', 'occurred_events exists');
select has_table('public', 'game_terminations', 'game_terminations exists');

select is(
  (select name from public.event_categories where code = 'system'),
  'システムイベント',
  'the system event category is seeded'
);

select is(
  (select category_code from public.event_definitions where code = 'flame'),
  'system',
  'flame is seeded as a system event'
);

select is(
  (select count(*)::integer from public.event_rules where event_definition_code = 'flame'),
  0,
  'flame is not part of the random-event rule pool'
);

insert into auth.users (id)
select ('81000000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid
from pg_catalog.generate_series(1, 8) as value;

insert into public.game_runs (
  id, user_id, rule_set_id, channel_rule_id, channel_name
)
select
  ('82000000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('81000000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001001',
  'BE-008 channel ' || value
from pg_catalog.generate_series(1, 8) as value;

select lives_ok(
  $$
    insert into public.advance_week_executions (
      idempotency_key, run_id, attempted_week, expected_state_version, outcome
    ) values (
      '83000000-0000-4000-8000-000000000001',
      '82000000-0000-4000-8000-000000000001',
      1,
      0,
      'week_committed'
    )
  $$,
  'a committed-week execution can be created'
);

select lives_ok(
  $$
    insert into public.advance_week_executions (
      idempotency_key, run_id, attempted_week, expected_state_version, outcome
    ) values (
      '83000000-0000-4000-8000-000000000002',
      '82000000-0000-4000-8000-000000000002',
      1,
      0,
      'fatal_game_over'
    )
  $$,
  'a fatal-game-over execution can be created'
);

select throws_ok(
  $$insert into public.advance_week_executions (idempotency_key, run_id, attempted_week, expected_state_version, outcome) values ('83000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', 1, 0, 'week_committed')$$,
  '23505', null, 'idempotency keys cannot be reused'
);

select throws_ok(
  $$insert into public.advance_week_executions (idempotency_key, run_id, attempted_week, expected_state_version, outcome) values ('83000000-0000-4000-8000-000000000090', '82000000-0000-4000-8000-000000000001', 0, 0, 'week_committed')$$,
  '23514', null, 'attempted weeks must be positive'
);

select throws_ok(
  $$insert into public.advance_week_executions (idempotency_key, run_id, attempted_week, expected_state_version, outcome) values ('83000000-0000-4000-8000-000000000091', '82000000-0000-4000-8000-000000000001', 1, -1, 'week_committed')$$,
  '23514', null, 'expected state versions cannot be negative'
);

select throws_ok(
  $$insert into public.advance_week_executions (idempotency_key, run_id, attempted_week, expected_state_version, outcome) values ('83000000-0000-4000-8000-000000000092', '82000000-0000-4000-8000-000000000001', 1, 0, 'failed')$$,
  '23514', null, 'unknown execution outcomes are rejected'
);

select throws_ok(
  $$update public.advance_week_executions set attempted_week = 2 where idempotency_key = '83000000-0000-4000-8000-000000000002'$$,
  '23514', null, 'execution history cannot be updated'
);

select throws_ok(
  $$delete from public.advance_week_executions where idempotency_key = '83000000-0000-4000-8000-000000000002'$$,
  '23514', null, 'execution history cannot be deleted'
);

insert into public.advance_week_executions (
  idempotency_key, run_id, attempted_week, expected_state_version, outcome
) values
  ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, 1, 'week_committed'),
  ('83000000-0000-4000-8000-000000000004', '82000000-0000-4000-8000-000000000002', 1, 0, 'week_committed'),
  ('83000000-0000-4000-8000-000000000005', '82000000-0000-4000-8000-000000000003', 1, 0, 'fatal_game_over'),
  ('83000000-0000-4000-8000-000000000006', '82000000-0000-4000-8000-000000000004', 1, 0, 'fatal_game_over'),
  ('83000000-0000-4000-8000-000000000007', '82000000-0000-4000-8000-000000000005', 1, 0, 'fatal_game_over'),
  ('83000000-0000-4000-8000-000000000008', '82000000-0000-4000-8000-000000000006', 1, 0, 'week_committed'),
  ('83000000-0000-4000-8000-000000000009', '82000000-0000-4000-8000-000000000008', 1, 0, 'fatal_game_over');

insert into public.weekly_actions (
  id, run_id, week_number, action_rule_id
) values
  (
    '84000000-0000-4000-8000-000000000001',
    '82000000-0000-4000-8000-000000000001',
    1,
    '00000000-0000-4000-8100-000000001601'
  ),
  (
    '84000000-0000-4000-8000-000000000002',
    '82000000-0000-4000-8000-000000000002',
    1,
    '00000000-0000-4000-8100-000000001601'
  ),
  (
    '84000000-0000-4000-8000-000000000006',
    '82000000-0000-4000-8000-000000000006',
    1,
    '00000000-0000-4000-8100-000000001601'
  );

select lives_ok(
  $$
    insert into public.week_results (
      id, execution_id, run_id, week_number, weekly_action_id, posting_frequency_rule_id,
      views_before_event, final_views, subscribers_before, max_subscribers_during_week,
      subscribers_after, energy_before, energy_after, cash_before, cash_after,
      ad_revenue, flame_count_after, run_status_after, state_version_after
    ) values (
      '85000000-0000-4000-8000-000000000001',
      '83000000-0000-4000-8000-000000000001',
      '82000000-0000-4000-8000-000000000001',
      1,
      '84000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8100-000000001201',
      1000, 2000, 100, 120, 115, 100, 90, 100000, 100400, 400, 0, 'playing', 1
    )
  $$,
  'a normal week result can be created'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002', 2, 0, 0, 0, 0, 0, 100, 100, 100000, 100000, 0, 0, 'playing', 1)$$,
  '23514', 'Week result run does not match its execution',
  'an execution cannot be reused by another run result'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 1, 0, 0, 0, 0, 0, 100, 100, 100000, 100000, 0, 0, 'playing', 2)$$,
  '23514', 'Week result week does not match its execution',
  'a result week must match the execution attempted week'
);

select lives_ok(
  $$insert into public.week_results (id, execution_id, run_id, week_number, weekly_action_id, posting_frequency_rule_id, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('85000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000004', '82000000-0000-4000-8000-000000000002', 1, '84000000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001201', 0, 0, 0, 0, 0, 100, 100, 100000, 100000, 0, 0, 'playing', 1)$$,
  'different runs may use the same week number'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, -1, 0, 0, 0, 0, 100, 100, 100000, 100000, 0, 0, 'playing', 2)$$,
  '23514', null, 'negative view counts are rejected'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, 0, 0, -1, 0, 0, 100, 100, 100000, 100000, 0, 0, 'playing', 2)$$,
  '23514', null, 'negative subscriber counts are rejected'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, 0, 0, 100, 99, 101, 100, 100, 100000, 100000, 0, 0, 'playing', 2)$$,
  '23514', null, 'maximum weekly subscribers cannot be below before or after values'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, 0, 0, 0, 0, 0, 100, 100, -1, 0, 0, 0, 'playing', 2)$$,
  '23514', null, 'negative cash is rejected'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, 0, 0, 0, 0, 0, 100, 100, 0, 0, -1, 0, 'playing', 2)$$,
  '23514', null, 'negative ad revenue is rejected'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, 0, 0, 0, 0, 0, 100, 100, 0, 0, 0, 0, 'paused', 2)$$,
  '23514', null, 'unknown post-week run statuses are rejected'
);

insert into public.run_conditions (
  run_id, health_risk_rule_id, started_week, duration_weeks,
  unavailable_from_week, unavailable_through_week
) values (
  '82000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000002102',
  1, 1, 2, 2
);

select lives_ok(
  $$insert into public.week_results (id, execution_id, run_id, week_number, weekly_action_id, posting_frequency_rule_id, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('85000000-0000-4000-8000-000000000003', '83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000001', 2, null, null, 0, 0, 115, 115, 115, 90, 100, 100400, 100400, 0, 0, 'playing', 2)$$,
  'an unavailable week can omit action and posting-frequency references'
);

select throws_ok(
  $$update public.week_results set final_views = 3 where id = '85000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'week results cannot be updated'
);

select throws_ok(
  $$delete from public.week_results where id = '85000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'week results cannot be deleted'
);

insert into public.player_ideas (id, run_id, title, created_week)
values
  ('86000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', 'Player idea one', 1),
  ('86000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000001', 'Player idea two', 1);

insert into public.system_idea_cycles (id, run_id, cycle_number, created_week)
values (
  '86300000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000001',
  1,
  1
);

insert into public.system_idea_cycle_entries (
  id, cycle_id, rule_set_system_idea_id, position
)
select
  '86400000-0000-4000-8000-000000000001',
  '86300000-0000-4000-8000-000000000001',
  association.id,
  1
from public.rule_set_system_ideas as association
join public.system_idea_templates as template on template.id = association.system_idea_template_id
where association.rule_set_id = '00000000-0000-4000-8000-000000000001'
  and template.code = 'mainstream_001';

select lives_ok(
  $$insert into public.videos (id, week_result_id, sequence_number, player_idea_id, title_snapshot) values ('87000000-0000-4000-8000-000000000001', '85000000-0000-4000-8000-000000000001', 1, '86000000-0000-4000-8000-000000000001', 'Player video')$$,
  'a player-idea video can be created'
);

select lives_ok(
  $$insert into public.videos (id, week_result_id, sequence_number, system_idea_cycle_entry_id, title_snapshot) values ('87000000-0000-4000-8000-000000000002', '85000000-0000-4000-8000-000000000001', 2, '86400000-0000-4000-8000-000000000001', 'System video')$$,
  'a system-idea video can be created'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 3, 'No source')$$,
  '23514', null, 'videos require an idea source'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, system_idea_cycle_entry_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 3, '86000000-0000-4000-8000-000000000002', '86400000-0000-4000-8000-000000000001', 'Two sources')$$,
  '23514', null, 'videos reject two idea sources'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 3, '86000000-0000-4000-8000-000000000001', 'Reused player idea')$$,
  '23505', null, 'player ideas cannot be reused'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, system_idea_cycle_entry_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 3, '86400000-0000-4000-8000-000000000001', 'Reused system idea')$$,
  '23505', null, 'system idea entries cannot be reused'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 1, '86000000-0000-4000-8000-000000000002', 'Duplicate sequence')$$,
  '23505', null, 'video sequence numbers are unique within a week'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 0, '86000000-0000-4000-8000-000000000002', 'Sequence zero')$$,
  '23514', null, 'video sequence zero is rejected'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 8, '86000000-0000-4000-8000-000000000002', 'Sequence eight')$$,
  '23514', null, 'video sequence eight is rejected'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 3, '86000000-0000-4000-8000-000000000002', '   ')$$,
  '23514', null, 'blank video titles are rejected'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('85000000-0000-4000-8000-000000000001', 3, '86000000-0000-4000-8000-000000000002', repeat('a', 101))$$,
  '23514', null, 'video titles longer than 100 characters are rejected'
);

select throws_ok(
  $$update public.videos set title_snapshot = 'Changed' where id = '87000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'videos cannot be updated'
);

select throws_ok(
  $$delete from public.videos where id = '87000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'videos cannot be deleted'
);

select lives_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000001', 100, 1, 1, 1, 1.2, 1, 1, 1, 120, 2, 240, 0.03, 7)$$,
  'a video calculation snapshot can be created'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000001', 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0)$$,
  '23505', null, 'each video has at most one calculation snapshot'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000099', 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0)$$,
  '23503', null, 'calculations require an existing video'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000002', -1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0)$$,
  '23514', null, 'negative base views are rejected'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000002', 0, 1, -1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0)$$,
  '23514', null, 'negative multipliers are rejected'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000002', 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, -0.01, 0)$$,
  '23514', null, 'negative conversion rates are rejected'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000002', 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1.01, 0)$$,
  '23514', null, 'conversion rates above one are rejected'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000002', 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, -1, 0, 0)$$,
  '23514', null, 'negative final views are rejected'
);

select throws_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('87000000-0000-4000-8000-000000000002', 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, -1)$$,
  '23514', null, 'negative subscriber gains are rejected'
);

select throws_ok(
  $$update public.video_calculations set final_views = 1 where video_id = '87000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'video calculations cannot be updated'
);

select throws_ok(
  $$delete from public.video_calculations where video_id = '87000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'video calculations cannot be deleted'
);

select lives_ok(
  $$insert into public.occurred_events (id, week_result_id, event_definition_code, event_rule_id, sequence_number, display_metadata) values ('88000000-0000-4000-8000-000000000001', '85000000-0000-4000-8000-000000000001', 'featured_in_recommendations', '00000000-0000-4000-8100-000000002001', 1, '{"headline":"featured"}')$$,
  'a random event can be stored with its event rule'
);

select lives_ok(
  $$insert into public.occurred_events (id, week_result_id, event_definition_code, event_rule_id, sequence_number) values ('88000000-0000-4000-8000-000000000002', '85000000-0000-4000-8000-000000000001', 'flame', null, 2)$$,
  'flame can be stored without an event rule'
);

select is(
  (select count(*)::integer from public.occurred_events where week_result_id = '85000000-0000-4000-8000-000000000001'),
  2,
  'one random event and flame can coexist in the same week'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, event_rule_id, sequence_number) values ('85000000-0000-4000-8000-000000000001', 'temporary_bonus', '00000000-0000-4000-8100-000000002003', 3)$$,
  '23505', null, 'a week cannot contain two random events'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, sequence_number) values ('85000000-0000-4000-8000-000000000001', 'flame', 3)$$,
  '23505', null, 'a week cannot contain two flame events'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, event_rule_id, sequence_number) values ('85000000-0000-4000-8000-000000000003', 'temporary_bonus', null, 1)$$,
  '23514', null, 'random events require an event rule'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, event_rule_id, sequence_number) values ('85000000-0000-4000-8000-000000000003', 'flame', '00000000-0000-4000-8100-000000002001', 1)$$,
  '23514', null, 'flame rejects an event rule'
);

insert into public.occurred_events (
  id, week_result_id, event_definition_code, event_rule_id, sequence_number
) values (
  '88000000-0000-4000-8000-000000000003',
  '85000000-0000-4000-8000-000000000003',
  'temporary_bonus',
  '00000000-0000-4000-8100-000000002003',
  1
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, sequence_number) values ('85000000-0000-4000-8000-000000000003', 'flame', 1)$$,
  '23505', null, 'event sequence numbers are unique within a week'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, sequence_number, display_metadata) values ('85000000-0000-4000-8000-000000000003', 'flame', 2, '[]')$$,
  '23514', null, 'array display metadata is rejected'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, sequence_number, display_metadata) values ('85000000-0000-4000-8000-000000000003', 'flame', 2, '1')$$,
  '23514', null, 'numeric display metadata is rejected'
);

select throws_ok(
  $$update public.occurred_events set sequence_number = 3 where id = '88000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'occurred events cannot be updated'
);

select throws_ok(
  $$delete from public.occurred_events where id = '88000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'occurred events cannot be deleted'
);

insert into public.week_results (
  id, execution_id, run_id, week_number, weekly_action_id, posting_frequency_rule_id,
  views_before_event, final_views,
  subscribers_before, max_subscribers_during_week, subscribers_after,
  energy_before, energy_after, cash_before, cash_after, ad_revenue,
  flame_count_after, run_status_after, state_version_after
) values (
  '85000000-0000-4000-8000-000000000006',
  '83000000-0000-4000-8000-000000000008',
  '82000000-0000-4000-8000-000000000006',
  1,
  '84000000-0000-4000-8000-000000000006',
  '00000000-0000-4000-8100-000000001201',
  0, 0, 0, 0, 0, 100, 100, 100000, 100000, 0, 0, 'game_over', 1
);

select lives_ok(
  $$insert into public.game_terminations (id, run_id, execution_id, reason, occurred_week, calculated_energy, calculated_flame_count) values ('89000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000003', '83000000-0000-4000-8000-000000000005', 'death', 1, 0, 2)$$,
  'a death termination can be stored'
);

select lives_ok(
  $$insert into public.game_terminations (id, run_id, execution_id, reason, occurred_week, calculated_flame_count) values ('89000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000004', '83000000-0000-4000-8000-000000000006', 'flame_ban', 1, 3)$$,
  'a flame-ban termination can be stored'
);

select lives_ok(
  $$insert into public.game_terminations (id, run_id, execution_id, reason, occurred_week, calculated_energy, calculated_flame_count) values ('89000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000005', '83000000-0000-4000-8000-000000000007', 'flame_ban', 1, -10, 3)$$,
  'flame ban can store a simultaneous death threshold while retaining ban priority'
);

select lives_ok(
  $$insert into public.game_terminations (id, run_id, week_result_id, reason, occurred_week) values ('89000000-0000-4000-8000-000000000004', '82000000-0000-4000-8000-000000000006', '85000000-0000-4000-8000-000000000006', 'deadline', 1)$$,
  'a deadline termination can reference its committed week'
);

select lives_ok(
  $$insert into public.game_terminations (id, run_id, reason, occurred_week) values ('89000000-0000-4000-8000-000000000005', '82000000-0000-4000-8000-000000000007', 'abandoned', 1)$$,
  'an abandoned termination can be stored without result references'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, reason, occurred_week) values ('82000000-0000-4000-8000-000000000003', 'abandoned', 2)$$,
  '23505', null, 'each run can have only one termination'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, reason, occurred_week) values ('82000000-0000-4000-8000-000000000008', 'timeout', 1)$$,
  '23514', null, 'unknown termination reasons are rejected'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, execution_id, week_result_id, reason, occurred_week, calculated_energy) values ('82000000-0000-4000-8000-000000000008', '83000000-0000-4000-8000-000000000009', '85000000-0000-4000-8000-000000000006', 'death', 1, 0)$$,
  '23514', null, 'death cannot reference a normal week result'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, execution_id, reason, occurred_week, calculated_energy) values ('82000000-0000-4000-8000-000000000008', '83000000-0000-4000-8000-000000000009', 'death', 1, 1)$$,
  '23514', null, 'death requires nonpositive calculated energy'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, execution_id, reason, occurred_week, calculated_flame_count) values ('82000000-0000-4000-8000-000000000008', '83000000-0000-4000-8000-000000000009', 'flame_ban', 1, 2)$$,
  '23514', null, 'flame ban requires at least three flames'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, reason, occurred_week) values ('82000000-0000-4000-8000-000000000008', 'deadline', 1)$$,
  '23514', null, 'deadline requires a week result'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, execution_id, reason, occurred_week) values ('82000000-0000-4000-8000-000000000008', '83000000-0000-4000-8000-000000000009', 'abandoned', 1)$$,
  '23514', null, 'abandoned termination rejects an execution reference'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, reason, occurred_week) values ('82000000-0000-4000-8000-000000000008', 'abandoned', 0)$$,
  '23514', null, 'termination weeks must be positive'
);

select throws_ok(
  $$update public.game_terminations set occurred_week = 2 where id = '89000000-0000-4000-8000-000000000005'$$,
  '23514', null, 'terminations cannot be updated'
);

select throws_ok(
  $$delete from public.game_terminations where id = '89000000-0000-4000-8000-000000000005'$$,
  '23514', null, 'terminations cannot be deleted'
);

select * from finish();

rollback;
