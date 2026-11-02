begin;

set local search_path = extensions, public, pg_catalog;

select plan(95);

select has_table('public', 'global_rules', 'global_rules exists');
select has_table('public', 'channel_rules', 'channel_rules exists');
select has_table('public', 'channel_ability_weights', 'channel_ability_weights exists');
select has_table('public', 'rule_set_specialties', 'rule_set_specialties exists');
select has_table('public', 'posting_frequency_rules', 'posting_frequency_rules exists');
select has_table('public', 'idea_score_band_rules', 'idea_score_band_rules exists');
select has_table('public', 'equipment_tier_rules', 'equipment_tier_rules exists');
select has_table('public', 'action_rules', 'action_rules exists');
select has_table('public', 'sponsorship_reward_rules', 'sponsorship_reward_rules exists');
select has_table('public', 'feature_rules', 'feature_rules exists');
select has_table('public', 'goal_rules', 'goal_rules exists');
select has_table('public', 'event_category_rules', 'event_category_rules exists');
select has_table('public', 'event_rules', 'event_rules exists');
select has_table('public', 'health_risk_rules', 'health_risk_rules exists');

select has_pk('public', 'global_rules', 'global_rules has a primary key');
select has_pk('public', 'channel_rules', 'channel_rules has a primary key');
select has_pk('public', 'channel_ability_weights', 'channel_ability_weights has a primary key');
select has_pk('public', 'rule_set_specialties', 'rule_set_specialties has a primary key');
select has_pk('public', 'posting_frequency_rules', 'posting_frequency_rules has a primary key');
select has_pk('public', 'idea_score_band_rules', 'idea_score_band_rules has a primary key');
select has_pk('public', 'equipment_tier_rules', 'equipment_tier_rules has a primary key');
select has_pk('public', 'action_rules', 'action_rules has a primary key');
select has_pk('public', 'sponsorship_reward_rules', 'sponsorship_reward_rules has a primary key');
select has_pk('public', 'feature_rules', 'feature_rules has a primary key');
select has_pk('public', 'goal_rules', 'goal_rules has a primary key');
select has_pk('public', 'event_category_rules', 'event_category_rules has a primary key');
select has_pk('public', 'event_rules', 'event_rules has a primary key');
select has_pk('public', 'health_risk_rules', 'health_risk_rules has a primary key');

select is(
  (
    select count(*)::integer
    from information_schema.table_constraints
    where constraint_schema = 'public'
      and constraint_type = 'FOREIGN KEY'
      and constraint_name like '%_rule_set_id_fkey'
      and table_name in (
        'global_rules', 'channel_rules', 'channel_ability_weights', 'rule_set_specialties',
        'posting_frequency_rules', 'idea_score_band_rules', 'equipment_tier_rules',
        'action_rules', 'sponsorship_reward_rules', 'feature_rules', 'goal_rules',
        'event_category_rules', 'event_rules', 'health_risk_rules'
      )
  ),
  14,
  'all fourteen rule tables directly reference rule_sets'
);

select ok(
  not exists (
    select 1
    from (values
      ('channel_rules', 'channel_rules_rule_set_channel_type_key'),
      ('channel_ability_weights', 'channel_ability_weights_channel_rule_ability_key'),
      ('posting_frequency_rules', 'posting_frequency_rules_rule_set_videos_key'),
      ('equipment_tier_rules', 'equipment_tier_rules_rule_set_type_tier_key'),
      ('action_rules', 'action_rules_rule_set_action_key'),
      ('feature_rules', 'feature_rules_rule_set_feature_key'),
      ('goal_rules', 'goal_rules_rule_set_stage_key'),
      ('event_category_rules', 'event_category_rules_rule_set_category_key'),
      ('event_rules', 'event_rules_rule_set_event_key')
    ) as expected(table_name, constraint_name)
    where not exists (
      select 1 from information_schema.table_constraints as actual
      where actual.table_schema = 'public'
        and actual.table_name = expected.table_name
        and actual.constraint_name = expected.constraint_name
        and actual.constraint_type = 'UNIQUE'
    )
  ),
  'business-key unique constraints exist'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_constraint
    where connamespace = 'public'::regnamespace
      and conname in (
        'idea_score_band_rules_score_overlap_excl',
        'sponsorship_reward_rules_subscriber_overlap_excl',
        'health_risk_rules_energy_overlap_excl'
      )
      and contype = 'x'
  ),
  3,
  'all three range exclusion constraints exist'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_trigger
    where not tgisinternal
      and tgname like 'protect_published_%'
  ),
  14,
  'the shared published-rule guard is attached to all fourteen tables'
);

select is((select count(*)::integer from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 1, 'one global rule is seeded');
select is((select count(*)::integer from public.channel_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 4, 'four channel rules are seeded');
select is((select count(*)::integer from public.channel_ability_weights where rule_set_id = '00000000-0000-4000-8000-000000000001'), 8, 'eight channel ability weights are seeded');
select is((select count(*)::integer from public.rule_set_specialties where rule_set_id = '00000000-0000-4000-8000-000000000001'), 10, 'ten specialties are seeded');
select is((select count(*)::integer from public.posting_frequency_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 3, 'three posting frequency rules are seeded');
select is((select count(*)::integer from public.idea_score_band_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 5, 'five idea score bands are seeded');
select is((select count(*)::integer from public.equipment_tier_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 12, 'twelve equipment tiers are seeded');
select is((select count(*)::integer from public.action_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 4, 'four action rules are seeded');
select is((select count(*)::integer from public.sponsorship_reward_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 6, 'six sponsorship reward bands are seeded');
select is((select count(*)::integer from public.feature_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 3, 'three feature rules are seeded');
select is((select count(*)::integer from public.goal_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 5, 'five goal rules are seeded');
select is((select count(*)::integer from public.event_category_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 2, 'two event category rules are seeded');
select is((select count(*)::integer from public.event_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 6, 'six event rules are seeded');
select is((select count(*)::integer from public.health_risk_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'), 4, 'four health risk bands are seeded');

select is(
  (select status from public.rule_sets where id = '00000000-0000-4000-8000-000000000001'),
  'draft',
  'the initial rule set remains draft'
);

select is(
  (
    select jsonb_build_array(
      base_views_min, base_views_max, energy_max, unavailable_energy_recovery,
      ideas_per_week, idea_stock_max, flame_subscriber_loss_rate, flame_energy_loss,
      ban_flame_count, ad_revenue_per_view, system_idea_view_multiplier,
      system_idea_subscriber_conversion_rate
    )
    from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[0, 100000, 100, 10, 3, 30, 0.05, 20, 3, 0.2, 0.6, 0.02]'::jsonb,
  'global rules match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(channel_type_code, view_multiplier, weekly_flame_probability) order by channel_type_code) from public.channel_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[["controversial", 1.5, 0.05], ["idol", 1.0, 0.001], ["mainstream", 1.0, 0.001], ["specialized", 1.0, 0.001]]'::jsonb,
  'channel multipliers and flame probabilities match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(channel_type_code, ability_code, weight) order by channel_type_code, ability_code)
    from public.channel_ability_weights join public.channel_rules on channel_rules.id = channel_ability_weights.channel_rule_id
    where channel_ability_weights.rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[["controversial", "planning", 0.5], ["controversial", "talking", 0.5], ["idol", "filming", 0.5], ["idol", "visual", 0.5], ["mainstream", "planning", 0.5], ["mainstream", "talking", 0.5], ["specialized", "editing", 0.5], ["specialized", "expertise", 0.5]]'::jsonb,
  'channel ability weights match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(videos_per_week, view_multiplier, energy_cost, ability_points_awarded) order by videos_per_week) from public.posting_frequency_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[[1, 1.2, 3, 3], [3, 1.0, 8, 7], [7, 0.8, 25, 15]]'::jsonb,
  'posting frequency rules match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(min_score, max_score, view_multiplier, subscriber_conversion_rate) order by min_score) from public.idea_score_band_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[[0, 39, 0.5, 0.01], [40, 59, 0.8, 0.02], [60, 79, 1.0, 0.03], [80, 89, 1.3, 0.04], [90, 100, 1.7, 0.05]]'::jsonb,
  'idea score bands match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(equipment_type_code, tier, purchase_price, view_bonus) order by equipment_type_code, array_position(array['none', 'beginner', 'intermediate', 'advanced'], tier)) from public.equipment_tier_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[["camera", "none", 0, 0.00], ["camera", "beginner", 30000, 0.05], ["camera", "intermediate", 150000, 0.10], ["camera", "advanced", 500000, 0.15], ["editing_pc", "none", 0, 0.00], ["editing_pc", "beginner", 50000, 0.05], ["editing_pc", "intermediate", 200000, 0.10], ["editing_pc", "advanced", 500000, 0.15], ["microphone", "none", 0, 0.00], ["microphone", "beginner", 5000, 0.05], ["microphone", "intermediate", 30000, 0.10], ["microphone", "advanced", 100000, 0.15]]'::jsonb,
  'equipment prices and bonuses match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(action_code, required_feature_code, cooldown_weeks, fixed_cash_delta, energy_delta, video_view_multiplier) order by action_code) from public.action_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[["collaboration", "collaboration", 2, 0, -10, 1.5], ["part_time_job", null, 0, 10000, -10, 1.0], ["rest", null, 0, 0, 50, 1.0], ["sponsorship", "sponsorship", 4, 0, -5, 1.0]]'::jsonb,
  'action rules match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(min_subscribers, max_subscribers, reward_amount) order by min_subscribers) from public.sponsorship_reward_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[[100000, 299999, 100000], [300000, 499999, 200000], [500000, 999999, 400000], [1000000, 4999999, 800000], [5000000, 9999999, 1200000], [10000000, null, 2000000]]'::jsonb,
  'sponsorship reward bands match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(feature_code, unlock_subscribers, activation_delay_weeks, is_persistent) order by feature_code) from public.feature_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[["ad_revenue", 3000, 1, true], ["collaboration", 50000, 1, true], ["sponsorship", 100000, 1, true]]'::jsonb,
  'feature unlock rules match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(stage_number, target_subscribers, duration_weeks, is_final) order by stage_number) from public.goal_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[[1, 100000, 156, false], [2, 500000, 156, false], [3, 1000000, 156, false], [4, 3000000, 156, false], [5, 10000000, 156, true]]'::jsonb,
  'goal rules match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(category_code, weekly_probability) order by category_code) from public.event_category_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[["bad", 0.05], ["good", 0.05]]'::jsonb,
  'event category probabilities match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(event_definition_code, category_code, selection_weight, weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier) order by event_definition_code) from public.event_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[["criticized_on_social_media", "bad", 1, 1.0, 0, 0, 0.97], ["equipment_trouble", "bad", 1, 1.0, -30000, 0, 1.0], ["featured_in_recommendations", "good", 1, 2.0, 0, 0, 1.0], ["introduced_by_celebrity", "good", 1, 1.0, 0, 5000, 1.0], ["poorly_received_video", "bad", 1, 0.5, 0, 0, 1.0], ["temporary_bonus", "good", 1, 1.0, 50000, 0, 1.0]]'::jsonb,
  'event effects match the specification'
);

select is(
  (select jsonb_agg(jsonb_build_array(min_energy, max_energy, occurrence_probability, min_unavailable_weeks, max_unavailable_weeks) order by min_energy) from public.health_risk_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '[[1, 9, 0.30, 8, 12], [10, 29, 0.15, 3, 6], [30, 49, 0.05, 1, 2], [50, 100, 0.00, 0, 0]]'::jsonb,
  'health risk bands match the specification'
);

select is(
  (select id::text from public.channel_rules where channel_type_code = 'mainstream' and rule_set_id = '00000000-0000-4000-8000-000000000001'),
  '00000000-0000-4000-8100-000000001001',
  'seeded rule rows have stable identifiers'
);

insert into public.rule_sets (id, version)
values ('00000000-0000-4000-8000-000000000900', 'invalid-rule-tests');

select throws_ok(
  $$insert into public.channel_rules (rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability) values ('00000000-0000-4000-8000-000000000900', 'mainstream', 1, -0.01)$$,
  '23514', null, 'negative probabilities are rejected'
);

select throws_ok(
  $$insert into public.event_category_rules (rule_set_id, category_code, weekly_probability) values ('00000000-0000-4000-8000-000000000900', 'good', 1.01)$$,
  '23514', null, 'probabilities above one are rejected'
);

select throws_ok(
  $$insert into public.channel_rules (rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability) values ('00000000-0000-4000-8000-000000000900', 'mainstream', -0.1, 0.01)$$,
  '23514', null, 'negative multipliers are rejected'
);

select throws_ok(
  $$insert into public.equipment_tier_rules (rule_set_id, equipment_type_code, tier, purchase_price, view_bonus) values ('00000000-0000-4000-8000-000000000900', 'camera', 'beginner', -1, 0.05)$$,
  '23514', null, 'negative equipment prices are rejected'
);

select throws_ok(
  $$insert into public.idea_score_band_rules (rule_set_id, min_score, max_score, view_multiplier, subscriber_conversion_rate) values ('00000000-0000-4000-8000-000000000900', 80, 79, 1, 0.03)$$,
  '23514', null, 'ranges whose minimum exceeds their maximum are rejected'
);

select throws_ok(
  $$insert into public.equipment_tier_rules (rule_set_id, equipment_type_code, tier, purchase_price, view_bonus) values ('00000000-0000-4000-8000-000000000900', 'unknown', 'beginner', 1, 0.05)$$,
  '23503', null, 'unknown catalog codes are rejected'
);

select throws_ok(
  $$insert into public.channel_ability_weights (rule_set_id, channel_rule_id, ability_code, weight) values ('00000000-0000-4000-8000-000000000900', '00000000-0000-4000-8100-000000001001', 'expertise', 0.5)$$,
  '23503', null, 'channel ability weights cannot mix rule sets'
);

select throws_ok(
  $$insert into public.idea_score_band_rules (rule_set_id, min_score, max_score, view_multiplier, subscriber_conversion_rate) values ('00000000-0000-4000-8000-000000000001', 30, 40, 1, 0.03)$$,
  '23P01', null, 'overlapping idea score bands are rejected'
);

select throws_ok(
  $$insert into public.sponsorship_reward_rules (rule_set_id, min_subscribers, max_subscribers, reward_amount) values ('00000000-0000-4000-8000-000000000001', 200000, 400000, 1)$$,
  '23P01', null, 'overlapping sponsorship reward bands are rejected'
);

select throws_ok(
  $$insert into public.health_risk_rules (rule_set_id, min_energy, max_energy, occurrence_probability, min_unavailable_weeks, max_unavailable_weeks) values ('00000000-0000-4000-8000-000000000001', 40, 60, 0.1, 1, 2)$$,
  '23P01', null, 'overlapping health risk bands are rejected'
);

insert into public.event_category_rules (rule_set_id, category_code, weekly_probability)
values
  ('00000000-0000-4000-8000-000000000900', 'good', 0.05),
  ('00000000-0000-4000-8000-000000000900', 'bad', 0.05);

select throws_ok(
  $$insert into public.event_rules (rule_set_id, event_definition_code, category_code, selection_weight, weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier) values ('00000000-0000-4000-8000-000000000900', 'featured_in_recommendations', 'bad', 1, 1, 0, 0, 1)$$,
  '23503', null, 'event rules cannot contradict their static event category'
);

select throws_ok(
  $$insert into public.event_rules (rule_set_id, event_definition_code, category_code, selection_weight, weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier) values ('00000000-0000-4000-8000-000000000900', 'temporary_bonus', 'good', 1, 1, -1, 0, 1)$$,
  '23514', null, 'good events cannot contain negative effects'
);

select throws_ok(
  $$insert into public.channel_rules (rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability) values ('00000000-0000-4000-8000-000000000001', 'mainstream', 1, 0.001)$$,
  '23505', null, 'duplicate channel rules are rejected'
);

select throws_ok(
  $$insert into public.rule_set_specialties (rule_set_id, specialty_code) values ('00000000-0000-4000-8000-000000000001', 'baseball')$$,
  '23505', null, 'duplicate rule-set specialties are rejected'
);

select throws_ok(
  $$insert into public.health_risk_rules (rule_set_id, min_energy, max_energy, occurrence_probability, min_unavailable_weeks, max_unavailable_weeks) values ('00000000-0000-4000-8000-000000000900', 1, 9, 0.1, 5, 4)$$,
  '23514', null, 'invalid unavailable-week ranges are rejected'
);

insert into public.rule_sets (id, version)
values ('00000000-0000-4000-8000-000000000901', 'incomplete-publication-test');

select throws_ok(
  $$update public.rule_sets set status = 'active', published_at = statement_timestamp() where id = '00000000-0000-4000-8000-000000000901'$$,
  'P0001', 'Rule set must contain exactly one global rule', 'incomplete rule sets cannot be published'
);

insert into public.rule_sets (id, version)
values ('00000000-0000-4000-8000-000000000902', 'complete-publication-test');

insert into public.global_rules
select '00000000-0000-4000-8000-000000000902', base_views_min, base_views_max, energy_max,
  unavailable_energy_recovery, ideas_per_week, idea_stock_max, flame_subscriber_loss_rate,
  flame_energy_loss, ban_flame_count, ad_revenue_per_view, system_idea_view_multiplier,
  system_idea_subscriber_conversion_rate
from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.channel_rules (rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability)
select '00000000-0000-4000-8000-000000000902', channel_type_code, view_multiplier, weekly_flame_probability
from public.channel_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.channel_ability_weights (rule_set_id, channel_rule_id, ability_code, weight)
select '00000000-0000-4000-8000-000000000902', target_channel.id, source_weight.ability_code, source_weight.weight
from public.channel_ability_weights as source_weight
join public.channel_rules as source_channel on source_channel.id = source_weight.channel_rule_id
join public.channel_rules as target_channel
  on target_channel.rule_set_id = '00000000-0000-4000-8000-000000000902'
  and target_channel.channel_type_code = source_channel.channel_type_code
where source_weight.rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.rule_set_specialties
select '00000000-0000-4000-8000-000000000902', specialty_code
from public.rule_set_specialties where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.posting_frequency_rules (rule_set_id, videos_per_week, view_multiplier, energy_cost, ability_points_awarded)
select '00000000-0000-4000-8000-000000000902', videos_per_week, view_multiplier, energy_cost, ability_points_awarded
from public.posting_frequency_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.idea_score_band_rules (rule_set_id, min_score, max_score, view_multiplier, subscriber_conversion_rate)
select '00000000-0000-4000-8000-000000000902', min_score, max_score, view_multiplier, subscriber_conversion_rate
from public.idea_score_band_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.equipment_tier_rules (rule_set_id, equipment_type_code, tier, purchase_price, view_bonus)
select '00000000-0000-4000-8000-000000000902', equipment_type_code, tier, purchase_price, view_bonus
from public.equipment_tier_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.feature_rules (rule_set_id, feature_code, unlock_subscribers, activation_delay_weeks, is_persistent)
select '00000000-0000-4000-8000-000000000902', feature_code, unlock_subscribers, activation_delay_weeks, is_persistent
from public.feature_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.action_rules (rule_set_id, action_code, required_feature_code, cooldown_weeks, fixed_cash_delta, energy_delta, video_view_multiplier)
select '00000000-0000-4000-8000-000000000902', action_code, required_feature_code, cooldown_weeks, fixed_cash_delta, energy_delta, video_view_multiplier
from public.action_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.sponsorship_reward_rules (rule_set_id, min_subscribers, max_subscribers, reward_amount)
select '00000000-0000-4000-8000-000000000902', min_subscribers, max_subscribers, reward_amount
from public.sponsorship_reward_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.goal_rules (rule_set_id, stage_number, target_subscribers, duration_weeks, is_final)
select '00000000-0000-4000-8000-000000000902', stage_number, target_subscribers, duration_weeks, is_final
from public.goal_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.event_category_rules (rule_set_id, category_code, weekly_probability)
select '00000000-0000-4000-8000-000000000902', category_code, weekly_probability
from public.event_category_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.event_rules (
  rule_set_id, event_definition_code, category_code, selection_weight,
  weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier
)
select '00000000-0000-4000-8000-000000000902', event_definition_code, category_code, selection_weight,
  weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier
from public.event_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.health_risk_rules (
  rule_set_id, min_energy, max_energy, occurrence_probability, min_unavailable_weeks, max_unavailable_weeks
)
select '00000000-0000-4000-8000-000000000902', min_energy, max_energy, occurrence_probability,
  min_unavailable_weeks, max_unavailable_weeks
from public.health_risk_rules where rule_set_id = '00000000-0000-4000-8000-000000000001';

insert into public.system_idea_templates (
  code, channel_type_code, specialty_code, title, description
)
select
  'rules_publication_' || pool.pool_code || '_' || item_number,
  pool.channel_type_code,
  pool.specialty_code,
  'Rules publication fixture ' || pool.pool_code || ' ' || item_number,
  'Temporary publication-validation fixture.'
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
  where rule_set_id = '00000000-0000-4000-8000-000000000902'
) as pool
cross join pg_catalog.generate_series(1, 50) as item_number;

insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id)
select '00000000-0000-4000-8000-000000000902', id
from public.system_idea_templates
where code like 'rules_publication_%';

select lives_ok(
  $$select public.validate_rule_set_for_publication('00000000-0000-4000-8000-000000000902')$$,
  'complete rule sets pass publication validation'
);

select lives_ok(
  $$update public.rule_sets set status = 'active', published_at = statement_timestamp() where id = '00000000-0000-4000-8000-000000000902'$$,
  'a complete rule set can be activated'
);

select throws_ok(
  $$insert into public.channel_rules (rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability) values ('00000000-0000-4000-8000-000000000902', 'mainstream', 1, 0.001)$$,
  'P0001', 'Rules can only be written under draft rule sets', 'inserts under active rule sets are rejected'
);

select throws_ok(
  $$update public.global_rules set energy_max = 99 where rule_set_id = '00000000-0000-4000-8000-000000000902'$$,
  'P0001', 'Rules belonging to published rule sets are immutable', 'updates under active rule sets are rejected'
);

select throws_ok(
  $$delete from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000902'$$,
  'P0001', 'Rules belonging to published rule sets are immutable', 'deletes under active rule sets are rejected'
);

select lives_ok(
  $$update public.rule_sets set status = 'retired' where id = '00000000-0000-4000-8000-000000000902'$$,
  'active rule sets can be retired'
);

select throws_ok(
  $$insert into public.channel_rules (rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability) values ('00000000-0000-4000-8000-000000000902', 'mainstream', 1, 0.001)$$,
  'P0001', 'Rules can only be written under draft rule sets', 'inserts under retired rule sets are rejected'
);

select throws_ok(
  $$update public.global_rules set energy_max = 99 where rule_set_id = '00000000-0000-4000-8000-000000000902'$$,
  'P0001', 'Rules belonging to published rule sets are immutable', 'updates under retired rule sets are rejected'
);

select throws_ok(
  $$delete from public.global_rules where rule_set_id = '00000000-0000-4000-8000-000000000902'$$,
  'P0001', 'Rules belonging to published rule sets are immutable', 'deletes under retired rule sets are rejected'
);

select lives_ok(
  $$insert into public.channel_rules (id, rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability) values ('00000000-0000-4000-8100-000000009001', '00000000-0000-4000-8000-000000000901', 'mainstream', 1, 0.001)$$,
  'valid rows can be inserted under draft rule sets'
);

select lives_ok(
  $$update public.channel_rules set view_multiplier = 1.1 where id = '00000000-0000-4000-8100-000000009001'$$,
  'rows under draft rule sets can be updated'
);

select lives_ok(
  $$delete from public.channel_rules where id = '00000000-0000-4000-8100-000000009001'$$,
  'rows under draft rule sets can be deleted'
);

select ok(
  pg_catalog.to_regprocedure('public.validate_rule_set_for_publication(uuid)') is not null
    and pg_catalog.to_regprocedure('public.validate_rule_set_before_publish()') is not null,
  'publication validation functions exist'
);

select is(
  (
    select data_type from information_schema.columns
    where table_schema = 'public' and table_name = 'global_rules' and column_name = 'base_views_max'
  ),
  'bigint',
  'potentially large view counts use bigint'
);

select ok(
  exists (
    select 1 from public.sponsorship_reward_rules
    where rule_set_id = '00000000-0000-4000-8000-000000000001'
      and min_subscribers = 10000000 and max_subscribers is null
  ),
  'the final sponsorship band safely represents an unbounded maximum'
);

select is(
  (select sum(weekly_probability) from public.event_category_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  0.10::numeric,
  'weekly random-event probability totals ten percent'
);

select ok(
  not exists (
    select 1 from public.channel_ability_weights
    where rule_set_id = '00000000-0000-4000-8000-000000000001'
    group by channel_rule_id
    having count(*) <> 2 or sum(weight) <> 1
  ),
  'each seeded channel has two ability weights totaling one'
);

select is(
  (select status from public.rule_sets where id = '00000000-0000-4000-8000-000000000001'),
  'draft',
  'publication-control tests do not publish the initial rule set'
);

select * from finish();

rollback;
