begin;

set local search_path = extensions, public, pg_catalog;

select plan(78);

create function pg_temp.clone_rule_set(target_rule_set_id uuid, target_version text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into public.rule_sets (id, version) values (target_rule_set_id, target_version);

  insert into public.global_rules
  select target_rule_set_id, base_views_min, base_views_max, energy_max,
    unavailable_energy_recovery, ideas_per_week, idea_stock_max, flame_subscriber_loss_rate,
    flame_energy_loss, ban_flame_count, ad_revenue_per_view, system_idea_view_multiplier,
    system_idea_subscriber_conversion_rate
  from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.channel_rules (rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability)
  select target_rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability
  from public.channel_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.channel_ability_weights (rule_set_id, channel_rule_id, ability_code, weight)
  select target_rule_set_id, target_channel.id, source_weight.ability_code, source_weight.weight
  from public.channel_ability_weights as source_weight
  join public.channel_rules as source_channel on source_channel.id = source_weight.channel_rule_id
  join public.channel_rules as target_channel
    on target_channel.rule_set_id = target_rule_set_id
   and target_channel.channel_type_code = source_channel.channel_type_code
  where source_weight.rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.rule_set_specialties
  select target_rule_set_id, specialty_code
  from public.rule_set_specialties where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.posting_frequency_rules (rule_set_id, videos_per_week, view_multiplier, energy_cost, ability_points_awarded)
  select target_rule_set_id, videos_per_week, view_multiplier, energy_cost, ability_points_awarded
  from public.posting_frequency_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.idea_score_band_rules (rule_set_id, min_score, max_score, view_multiplier, subscriber_conversion_rate)
  select target_rule_set_id, min_score, max_score, view_multiplier, subscriber_conversion_rate
  from public.idea_score_band_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.equipment_tier_rules (rule_set_id, equipment_type_code, tier, purchase_price, view_bonus)
  select target_rule_set_id, equipment_type_code, tier, purchase_price, view_bonus
  from public.equipment_tier_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.feature_rules (rule_set_id, feature_code, unlock_subscribers, activation_delay_weeks, is_persistent)
  select target_rule_set_id, feature_code, unlock_subscribers, activation_delay_weeks, is_persistent
  from public.feature_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.action_rules (rule_set_id, action_code, required_feature_code, cooldown_weeks, fixed_cash_delta, energy_delta, video_view_multiplier)
  select target_rule_set_id, action_code, required_feature_code, cooldown_weeks, fixed_cash_delta, energy_delta, video_view_multiplier
  from public.action_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.sponsorship_reward_rules (rule_set_id, min_subscribers, max_subscribers, reward_amount)
  select target_rule_set_id, min_subscribers, max_subscribers, reward_amount
  from public.sponsorship_reward_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.goal_rules (rule_set_id, stage_number, target_subscribers, duration_weeks, is_final)
  select target_rule_set_id, stage_number, target_subscribers, duration_weeks, is_final
  from public.goal_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.event_category_rules (rule_set_id, category_code, weekly_probability)
  select target_rule_set_id, category_code, weekly_probability
  from public.event_category_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.event_rules (
    rule_set_id, event_definition_code, category_code, selection_weight,
    weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier
  )
  select target_rule_set_id, event_definition_code, category_code, selection_weight,
    weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier
  from public.event_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

  insert into public.health_risk_rules (
    rule_set_id, min_energy, max_energy, occurrence_probability,
    min_unavailable_weeks, max_unavailable_weeks
  )
  select target_rule_set_id, min_energy, max_energy, occurrence_probability,
    min_unavailable_weeks, max_unavailable_weeks
  from public.health_risk_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';
end;
$$;

create function pg_temp.create_system_idea_pools(target_rule_set_id uuid, code_prefix text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into public.system_idea_templates (
    code, channel_type_code, specialty_code, title, description
  )
  select
    code_prefix || '_' || pool.pool_code || '_' || item_number,
    pool.channel_type_code,
    pool.specialty_code,
    'Publication idea ' || pool.pool_code || ' ' || item_number,
    'Temporary BE-009 publication fixture.'
  from (
    select channel_type_code, specialty_code, pool_code
    from (values
      ('mainstream'::text, null::text, 'mainstream'::text),
      ('controversial'::text, null::text, 'controversial'::text),
      ('idol'::text, null::text, 'idol'::text)
    ) as fixed_pool(channel_type_code, specialty_code, pool_code)
    union all
    select 'specialized', specialty_code, 'specialized_' || specialty_code
    from public.rule_set_specialties
    where rule_set_id = target_rule_set_id
  ) as pool
  cross join pg_catalog.generate_series(1, 50) as item_number;

  insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id)
  select target_rule_set_id, id
  from public.system_idea_templates
  where code like code_prefix || '\_%' escape '\';
end;
$$;

select pg_temp.clone_rule_set('90000000-0000-4000-8000-000000000001', 'be009-other');
select pg_temp.clone_rule_set('90000000-0000-4000-8000-000000000002', 'be009-publication');
select pg_temp.create_system_idea_pools('90000000-0000-4000-8000-000000000002', 'be009_publication');

insert into auth.users (id)
select ('91000000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid
from pg_catalog.generate_series(1, 20) as value;

insert into public.game_runs (id, user_id, rule_set_id, channel_rule_id, channel_name)
values
  (
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'Invariant run one'
  ),
  (
    '92000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'Invariant run two'
  ),
  (
    '92000000-0000-4000-8000-000000000003',
    '91000000-0000-4000-8000-000000000003',
    '90000000-0000-4000-8000-000000000001',
    (select id from public.channel_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' and channel_type_code = 'mainstream'),
    'Other version run'
  );

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id) values ('92000000-0000-4000-8000-000000000001', (select id from public.posting_frequency_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' and videos_per_week = 1))$$,
  '23514', null, 'run state rejects a posting frequency from another rule set'
);

select throws_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, energy) values ('92000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001201', 101)$$,
  '23514', null, 'run state rejects energy above the configured maximum'
);

select lives_ok(
  $$insert into public.run_state (run_id, posting_frequency_rule_id, energy) values ('92000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001201', 100)$$,
  'run state accepts energy at the configured maximum'
);

select throws_ok(
  $$delete from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'global rules cannot be removed while current state depends on them'
);

select throws_ok(
  $$insert into public.run_equipment (run_id, equipment_type_code, equipment_tier_rule_id, acquired_week) values ('92000000-0000-4000-8000-000000000001', 'camera', (select id from public.equipment_tier_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' and equipment_type_code = 'camera' and tier = 'beginner'), 1)$$,
  '23514', null, 'run equipment rejects a tier from another rule set'
);

select throws_ok(
  $$insert into public.run_equipment (run_id, equipment_type_code, equipment_tier_rule_id, acquired_week) values ('92000000-0000-4000-8000-000000000001', 'camera', '00000000-0000-4000-8100-000000001406', 1)$$,
  '23514', null, 'run equipment rejects a tier for another equipment type'
);

select throws_ok(
  $$insert into public.run_feature_unlocks (run_id, feature_rule_id, unlocked_week, active_from_week) values ('92000000-0000-4000-8000-000000000001', (select id from public.feature_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' limit 1), 1, 2)$$,
  '23514', null, 'feature unlocks reject another rule set'
);

select throws_ok(
  $$insert into public.run_conditions (run_id, health_risk_rule_id, started_week, duration_weeks, unavailable_from_week, unavailable_through_week) values ('92000000-0000-4000-8000-000000000001', (select id from public.health_risk_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' limit 1), 1, 1, 2, 2)$$,
  '23514', null, 'conditions reject another rule set'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, status) values ('92000000-0000-4000-8000-000000000001', (select id from public.goal_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' and stage_number = 1), 1, 156, 'active')$$,
  '23514', null, 'goals reject another rule set'
);

select throws_ok(
  $$insert into public.weekly_actions (run_id, week_number, action_rule_id) values ('92000000-0000-4000-8000-000000000001', 1, (select id from public.action_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' and action_code = 'rest'))$$,
  '23514', null, 'weekly actions reject another rule set'
);

select throws_ok(
  $$insert into public.equipment_purchases (run_id, equipment_type_code, to_tier_rule_id, price_paid, purchased_week) values ('92000000-0000-4000-8000-000000000001', 'camera', (select id from public.equipment_tier_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' and equipment_type_code = 'camera' and tier = 'beginner'), 1, 1)$$,
  '23514', null, 'equipment purchases reject a target tier from another rule set'
);

select throws_ok(
  $$insert into public.equipment_purchases (run_id, equipment_type_code, to_tier_rule_id, price_paid, purchased_week) values ('92000000-0000-4000-8000-000000000001', 'camera', '00000000-0000-4000-8100-000000001406', 1, 1)$$,
  '23514', null, 'equipment purchases reject a target tier for another equipment type'
);

select throws_ok(
  $$insert into public.equipment_purchases (run_id, equipment_type_code, from_tier_rule_id, to_tier_rule_id, price_paid, purchased_week) values ('92000000-0000-4000-8000-000000000001', 'camera', '00000000-0000-4000-8100-000000001406', '00000000-0000-4000-8100-000000001402', 1, 1)$$,
  '23514', null, 'equipment purchases reject a previous tier for another equipment type'
);

insert into public.ability_point_grants (
  id, run_id, earned_week, available_from_week, amount, status
)
values
  ('93000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 1, 2, 5, 'available'),
  ('93000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001', 2, 3, 5, 'held'),
  ('93000000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000001', 3, 4, 5, 'expired'),
  ('93000000-0000-4000-8000-000000000004', '92000000-0000-4000-8000-000000000001', 4, 5, 5, 'consumed');

select lives_ok(
  $$insert into public.ability_allocations (grant_id, ability_code, points, allocated_week) values ('93000000-0000-4000-8000-000000000001', 'planning', 3, 2)$$,
  'an allocation within the grant amount is accepted'
);

select throws_ok(
  $$insert into public.ability_allocations (grant_id, ability_code, points, allocated_week) values ('93000000-0000-4000-8000-000000000001', 'talking', 3, 2)$$,
  '23514', null, 'allocations cannot exceed the grant amount'
);

select throws_ok(
  $$insert into public.ability_allocations (grant_id, ability_code, points, allocated_week) values ('93000000-0000-4000-8000-000000000001', 'talking', 1, 1)$$,
  '23514', null, 'allocations cannot precede the available week'
);

select throws_ok(
  $$insert into public.ability_allocations (grant_id, ability_code, points, allocated_week) values ('93000000-0000-4000-8000-000000000002', 'planning', 1, 3)$$,
  '23514', null, 'held grants reject allocations'
);

select throws_ok(
  $$insert into public.ability_allocations (grant_id, ability_code, points, allocated_week) values ('93000000-0000-4000-8000-000000000003', 'planning', 1, 4)$$,
  '23514', null, 'expired grants reject allocations'
);

select throws_ok(
  $$insert into public.ability_allocations (grant_id, ability_code, points, allocated_week) values ('93000000-0000-4000-8000-000000000004', 'planning', 1, 5)$$,
  '23514', null, 'consumed grants reject allocations'
);

select throws_ok(
  $$update public.ability_point_grants set amount = 6 where id = '93000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'grant amounts are immutable'
);

select throws_ok(
  $$update public.ability_point_grants set available_from_week = 3 where id = '93000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'grant availability identity is immutable'
);

select throws_ok(
  $$delete from public.ability_point_grants where id = '93000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'grants cannot be physically deleted'
);

insert into public.run_feature_unlocks (
  run_id, feature_rule_id, unlocked_week, active_from_week
) values (
  '92000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001501',
  1,
  2
);

select throws_ok(
  $$update public.run_feature_unlocks set active_from_week = 3 where run_id = '92000000-0000-4000-8000-000000000001' and feature_rule_id = '00000000-0000-4000-8100-000000001501'$$,
  '23514', null, 'feature unlocks cannot be updated'
);

select throws_ok(
  $$delete from public.run_feature_unlocks where run_id = '92000000-0000-4000-8000-000000000001' and feature_rule_id = '00000000-0000-4000-8100-000000001501'$$,
  '23514', null, 'feature unlocks cannot be deleted'
);

insert into public.run_conditions (
  id, run_id, health_risk_rule_id, started_week, duration_weeks,
  unavailable_from_week, unavailable_through_week
) values (
  '94000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000002102',
  1, 2, 2, 3
);

select throws_ok(
  $$update public.run_conditions set started_week = 2 where id = '94000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'condition identity and periods are immutable'
);

select lives_ok(
  $$update public.run_conditions set recovered_at = statement_timestamp() where id = '94000000-0000-4000-8000-000000000001'$$,
  'a condition can be marked recovered once'
);

select throws_ok(
  $$update public.run_conditions set recovered_at = null where id = '94000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'a recovered condition cannot be reopened'
);

select throws_ok(
  $$delete from public.run_conditions where id = '94000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'conditions cannot be physically deleted'
);

insert into public.run_conditions (
  id, run_id, health_risk_rule_id, started_week, duration_weeks,
  unavailable_from_week, unavailable_through_week
) values (
  '94000000-0000-4000-8000-000000000002',
  '92000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000002102',
  4, 1, 5, 5
);

select throws_ok(
  $$insert into public.run_conditions (run_id, health_risk_rule_id, started_week, duration_weeks, unavailable_from_week, unavailable_through_week) values ('92000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000002103', 6, 1, 7, 7)$$,
  '23505', null, 'a run cannot have two unrecovered conditions'
);

insert into public.run_goals (
  id, run_id, goal_rule_id, started_week, deadline_week, status
) values (
  '95000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8100-000000001801',
  1, 156, 'active'
);

select lives_ok(
  $$update public.run_goals set status = 'achieved', achieved_week = 100 where id = '95000000-0000-4000-8000-000000000001'$$,
  'an active goal can transition to achieved'
);

select throws_ok(
  $$update public.run_goals set status = 'active', achieved_week = null where id = '95000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'an achieved goal cannot return to active'
);

select throws_ok(
  $$update public.run_goals set deadline_week = 157 where id = '95000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'goal schedules are immutable'
);

select throws_ok(
  $$delete from public.run_goals where id = '95000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'terminal goals cannot be deleted'
);

select throws_ok(
  $$insert into public.run_goals (run_id, goal_rule_id, started_week, deadline_week, achieved_week, status) values ('92000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001802', 1, 10, 11, 'achieved')$$,
  '23514', null, 'goal achievement cannot occur after the deadline'
);

update public.game_runs
set status = 'abandoned', completed_at = statement_timestamp()
where id = '92000000-0000-4000-8000-000000000003';

select throws_ok(
  $$update public.game_runs set status = 'playing', completed_at = null where id = '92000000-0000-4000-8000-000000000003'$$,
  '23514', null, 'terminal game runs cannot return to playing'
);

select throws_ok(
  $$update public.game_runs set completed_at = completed_at + interval '1 second' where id = '92000000-0000-4000-8000-000000000003'$$,
  '23514', null, 'terminal completion timestamps are immutable'
);

insert into public.weekly_actions (id, run_id, week_number, action_rule_id)
values
  ('96000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000002', 1, '00000000-0000-4000-8100-000000001601'),
  ('96000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001', 6, '00000000-0000-4000-8100-000000001601');

insert into public.advance_week_executions (
  idempotency_key, run_id, attempted_week, expected_state_version, outcome
)
values
  ('96100000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000002', 1, 0, 'week_committed'),
  ('96100000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001', 5, 4, 'week_committed'),
  ('96100000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000002', 2, 1, 'week_committed'),
  ('96100000-0000-4000-8000-000000000004', '92000000-0000-4000-8000-000000000002', 3, 2, 'week_committed'),
  ('96100000-0000-4000-8000-000000000005', '92000000-0000-4000-8000-000000000002', 4, 3, 'fatal_game_over'),
  ('96100000-0000-4000-8000-000000000006', '92000000-0000-4000-8000-000000000002', 5, 4, 'week_committed'),
  ('96100000-0000-4000-8000-000000000007', '92000000-0000-4000-8000-000000000002', 6, 5, 'week_committed');

select lives_ok(
  $$insert into public.week_results (id, execution_id, run_id, week_number, weekly_action_id, posting_frequency_rule_id, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('96200000-0000-4000-8000-000000000001', '96100000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000002', 1, '96000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001201', 10, 10, 0, 1, 1, 100, 97, 100000, 100002, 2, 0, 'playing', 1)$$,
  'a matching normal week result is accepted'
);

select lives_ok(
  $$insert into public.week_results (id, execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('96200000-0000-4000-8000-000000000002', '96100000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001', 5, 0, 0, 0, 0, 0, 50, 60, 100000, 100000, 0, 0, 'playing', 5)$$,
  'a matching unavailable week result is accepted'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('96100000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000001', 2, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 'playing', 2)$$,
  '23514', null, 'week results reject a run different from the execution'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('96100000-0000-4000-8000-000000000004', '92000000-0000-4000-8000-000000000002', 4, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 'playing', 3)$$,
  '23514', null, 'week results reject a week different from the execution'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('96100000-0000-4000-8000-000000000005', '92000000-0000-4000-8000-000000000002', 4, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 'game_over', 4)$$,
  '23514', null, 'fatal executions reject week results'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, weekly_action_id, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('96100000-0000-4000-8000-000000000006', '92000000-0000-4000-8000-000000000002', 5, '96000000-0000-4000-8000-000000000001', 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 'playing', 5)$$,
  '23514', null, 'week results reject only one of action and posting frequency'
);

select throws_ok(
  $$insert into public.week_results (execution_id, run_id, week_number, weekly_action_id, posting_frequency_rule_id, views_before_event, final_views, subscribers_before, max_subscribers_during_week, subscribers_after, energy_before, energy_after, cash_before, cash_after, ad_revenue, flame_count_after, run_status_after, state_version_after) values ('96100000-0000-4000-8000-000000000007', '92000000-0000-4000-8000-000000000002', 6, '96000000-0000-4000-8000-000000000002', '00000000-0000-4000-8100-000000001201', 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 'playing', 6)$$,
  '23514', null, 'week results reject an action from another run'
);

insert into public.player_ideas (id, run_id, title, created_week, deleted_at)
values
  ('96300000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000002', 'Matching idea', 1, null),
  ('96300000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001', 'Other run idea', 1, null),
  ('96300000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000002', 'Deleted idea', 1, statement_timestamp());

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('96200000-0000-4000-8000-000000000001', 1, '96300000-0000-4000-8000-000000000002', 'Wrong run')$$,
  '23514', null, 'videos reject player ideas from another run'
);

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, player_idea_id, title_snapshot) values ('96200000-0000-4000-8000-000000000001', 1, '96300000-0000-4000-8000-000000000003', 'Deleted')$$,
  '23514', null, 'videos reject logically deleted player ideas'
);

insert into public.system_idea_cycles (id, run_id, cycle_number, created_week)
values ('96400000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000001', 1, 1);
insert into public.system_idea_cycle_entries (id, cycle_id, rule_set_system_idea_id, position)
select
  '96400000-0000-4000-8000-000000000004',
  '96400000-0000-4000-8000-000000000003',
  association.id,
  1
from public.rule_set_system_ideas as association
join public.system_idea_templates as template on template.id = association.system_idea_template_id
where association.rule_set_id = '00000000-0000-4000-8000-000000000001'
  and template.code = 'mainstream_001';

select throws_ok(
  $$insert into public.videos (week_result_id, sequence_number, system_idea_cycle_entry_id, title_snapshot) values ('96200000-0000-4000-8000-000000000001', 1, '96400000-0000-4000-8000-000000000004', 'Wrong system run')$$,
  '23514', null, 'videos reject system cycle entries from another run'
);

select lives_ok(
  $$insert into public.videos (id, week_result_id, sequence_number, player_idea_id, title_snapshot) values ('96500000-0000-4000-8000-000000000001', '96200000-0000-4000-8000-000000000001', 1, '96300000-0000-4000-8000-000000000001', 'Matching video')$$,
  'videos accept an idea from the same run'
);

select lives_ok(
  $$insert into public.video_calculations (video_id, base_views, subscriber_multiplier, ability_multiplier, idea_multiplier, posting_frequency_multiplier, channel_multiplier, equipment_multiplier, collaboration_multiplier, views_before_event, event_multiplier, final_views, conversion_rate, subscribers_gained) values ('96500000-0000-4000-8000-000000000001', 10, 1, 1, 1, 1, 1, 1, 1, 10, 1, 10, 0.1, 1)$$,
  'the matching video can receive its immutable calculation snapshot'
);

select throws_ok(
  $$update public.player_ideas set deleted_at = statement_timestamp() where id = '96300000-0000-4000-8000-000000000001'$$,
  '23514', null, 'published player ideas cannot be logically deleted afterward'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, event_rule_id, sequence_number) values ('96200000-0000-4000-8000-000000000001', 'temporary_bonus', '00000000-0000-4000-8100-000000002001', 1)$$,
  '23514', null, 'occurred events reject a rule for another definition'
);

select throws_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, event_rule_id, sequence_number) values ('96200000-0000-4000-8000-000000000001', 'featured_in_recommendations', (select id from public.event_rules where rule_set_id = '90000000-0000-4000-8000-000000000001' and event_definition_code = 'featured_in_recommendations'), 1)$$,
  '23514', null, 'occurred events reject another rule set'
);

select lives_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, event_rule_id, sequence_number) values ('96200000-0000-4000-8000-000000000001', 'featured_in_recommendations', '00000000-0000-4000-8100-000000002001', 1)$$,
  'a matching random event is accepted'
);

select lives_ok(
  $$insert into public.occurred_events (week_result_id, event_definition_code, sequence_number) values ('96200000-0000-4000-8000-000000000001', 'flame', 2)$$,
  'flame remains independent from the weekly random event'
);

insert into public.game_runs (id, user_id, rule_set_id, channel_rule_id, channel_name)
select
  ('97000000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('91000000-0000-4000-8000-' || lpad((value + 3)::text, 12, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8100-000000001001',
  'Termination run ' || value
from pg_catalog.generate_series(1, 5) as value;

insert into public.advance_week_executions (
  idempotency_key, run_id, attempted_week, expected_state_version, outcome
)
values
  ('97100000-0000-4000-8000-000000000001', '97000000-0000-4000-8000-000000000001', 2, 0, 'fatal_game_over'),
  ('97100000-0000-4000-8000-000000000002', '97000000-0000-4000-8000-000000000002', 3, 0, 'week_committed'),
  ('97100000-0000-4000-8000-000000000003', '97000000-0000-4000-8000-000000000003', 4, 0, 'fatal_game_over');

select throws_ok(
  $$insert into public.game_terminations (run_id, execution_id, reason, occurred_week, calculated_energy) values ('97000000-0000-4000-8000-000000000002', '97100000-0000-4000-8000-000000000001', 'death', 2, 0)$$,
  '23514', null, 'fatal terminations reject executions from another run'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, execution_id, reason, occurred_week, calculated_energy) values ('97000000-0000-4000-8000-000000000001', '97100000-0000-4000-8000-000000000001', 'death', 3, 0)$$,
  '23514', null, 'fatal terminations reject an execution week mismatch'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, execution_id, reason, occurred_week, calculated_energy) values ('97000000-0000-4000-8000-000000000002', '97100000-0000-4000-8000-000000000002', 'death', 3, 0)$$,
  '23514', null, 'week-committed executions cannot back fatal terminations'
);

select lives_ok(
  $$insert into public.game_terminations (run_id, execution_id, reason, occurred_week, calculated_energy) values ('97000000-0000-4000-8000-000000000001', '97100000-0000-4000-8000-000000000001', 'death', 2, 0)$$,
  'fatal-game-over executions can back a death termination'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, week_result_id, reason, occurred_week) values ('97000000-0000-4000-8000-000000000004', '96200000-0000-4000-8000-000000000001', 'deadline', 1)$$,
  '23514', null, 'deadline terminations reject week results from another run'
);

select throws_ok(
  $$insert into public.game_terminations (run_id, week_result_id, reason, occurred_week) values ('92000000-0000-4000-8000-000000000002', '96200000-0000-4000-8000-000000000001', 'deadline', 2)$$,
  '23514', null, 'deadline terminations reject a week mismatch'
);

select lives_ok(
  $$insert into public.game_terminations (run_id, week_result_id, reason, occurred_week) values ('92000000-0000-4000-8000-000000000002', '96200000-0000-4000-8000-000000000001', 'deadline', 1)$$,
  'a matching deadline termination is accepted'
);

select lives_ok(
  $$insert into public.game_terminations (run_id, reason, occurred_week) values ('97000000-0000-4000-8000-000000000004', 'abandoned', 1)$$,
  'an abandoned termination needs no execution or week result'
);

select lives_ok(
  $$select public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002')$$,
  'a complete rule set with all 650 ideas passes publication validation'
);

select throws_ok(
  $$do $block$ begin update public.rule_set_system_ideas set enabled = false where id = (select rule_idea.id from public.rule_set_system_ideas as rule_idea join public.system_idea_templates as template on template.id = rule_idea.system_idea_template_id where rule_idea.rule_set_id = '90000000-0000-4000-8000-000000000002' and template.channel_type_code = 'mainstream' limit 1); perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'a 49-item mainstream pool is rejected'
);

select throws_ok(
  $$do $block$ begin insert into public.system_idea_templates (code, channel_type_code, title, description) values ('be009_mainstream_extra', 'mainstream', 'Extra', 'Extra publication fixture'); insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id) select '90000000-0000-4000-8000-000000000002', id from public.system_idea_templates where code = 'be009_mainstream_extra'; perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'a 51-item mainstream pool is rejected'
);

select throws_ok(
  $$do $block$ begin update public.rule_set_system_ideas set enabled = false where id = (select rule_idea.id from public.rule_set_system_ideas as rule_idea join public.system_idea_templates as template on template.id = rule_idea.system_idea_template_id where rule_idea.rule_set_id = '90000000-0000-4000-8000-000000000002' and template.channel_type_code = 'specialized' and template.specialty_code = 'baseball' limit 1); perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'a 49-item specialized pool is rejected'
);

select throws_ok(
  $$do $block$ begin insert into public.system_idea_templates (code, channel_type_code, specialty_code, title, description) values ('be009_baseball_extra', 'specialized', 'baseball', 'Extra', 'Extra publication fixture'); insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id) select '90000000-0000-4000-8000-000000000002', id from public.system_idea_templates where code = 'be009_baseball_extra'; perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'a 51-item specialized pool is rejected'
);

select throws_ok(
  $$do $block$ begin update public.system_idea_templates set enabled = false where id = (select template.id from public.rule_set_system_ideas as rule_idea join public.system_idea_templates as template on template.id = rule_idea.system_idea_template_id where rule_idea.rule_set_id = '90000000-0000-4000-8000-000000000002' limit 1); perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'disabled templates do not count toward a publication pool'
);

insert into public.system_idea_templates (code, channel_type_code, title, description)
values ('be009_other_rule_idea', 'mainstream', 'Other rule idea', 'Belongs only to another rule set.');
insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id)
select '90000000-0000-4000-8000-000000000001', id
from public.system_idea_templates where code = 'be009_other_rule_idea';

select lives_ok(
  $$select public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002')$$,
  'ideas associated only with another rule set are not counted'
);

select throws_ok(
  $$do $block$ begin delete from public.idea_score_band_rules where rule_set_id = '90000000-0000-4000-8000-000000000002' and min_score = 40; perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'publication rejects an idea score gap'
);

select throws_ok(
  $$do $block$ begin update public.channel_ability_weights set weight = 0.4 where id = (select id from public.channel_ability_weights where rule_set_id = '90000000-0000-4000-8000-000000000002' limit 1); perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'publication rejects channel weights that do not total one'
);

select throws_ok(
  $$do $block$ begin update public.event_category_rules set weekly_probability = 0.04 where rule_set_id = '90000000-0000-4000-8000-000000000002' and category_code = 'good'; perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'publication rejects incorrect random-event probabilities'
);

select throws_ok(
  $$do $block$ begin delete from public.health_risk_rules where rule_set_id = '90000000-0000-4000-8000-000000000002' and min_energy = 10; perform public.validate_rule_set_for_publication('90000000-0000-4000-8000-000000000002'); end $block$;$$,
  'P0001', null, 'publication rejects a health-risk coverage gap'
);

-- The seed leaves 1.0.0 active. Retire it only inside this rolled-back test
-- transaction to exercise publication and immutability on a dedicated fixture.
update public.rule_sets
set status = 'retired'
where id = '00000000-0000-4000-8000-000000000001';

select lives_ok(
  $$update public.rule_sets set status = 'active', published_at = statement_timestamp() where id = '90000000-0000-4000-8000-000000000002'$$,
  'the complete rule set can be published'
);

select throws_ok(
  $$update public.global_rules set energy_max = 99 where rule_set_id = '90000000-0000-4000-8000-000000000002'$$,
  'P0001', null, 'published rule rows cannot be changed'
);

select throws_ok(
  $$update public.rule_set_system_ideas set enabled = false where rule_set_id = '90000000-0000-4000-8000-000000000002'$$,
  'P0001', null, 'published system idea associations cannot be changed'
);

select throws_ok(
  $$update public.system_idea_templates set title = 'Changed' where code = 'be009_publication_mainstream_1'$$,
  '23514', null, 'published system idea template content cannot be changed'
);

select lives_ok(
  $$update public.system_idea_templates set enabled = false where code = 'be009_publication_mainstream_1'$$,
  'the published template enabled flag remains an emergency switch'
);

select lives_ok(
  $$update public.global_rules set energy_max = 101 where rule_set_id = '90000000-0000-4000-8000-000000000001'$$,
  'draft rule rows remain editable'
);

select * from finish();

rollback;
