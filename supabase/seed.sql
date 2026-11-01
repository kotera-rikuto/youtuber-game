begin;

insert into public.channel_types (code, name)
values
  ('mainstream', '王道系'),
  ('specialized', '特化系'),
  ('controversial', '炎上系'),
  ('idol', 'アイドル系')
on conflict do nothing;

insert into public.specialty_categories (code, name, display_order)
values
  ('baseball', '野球', 1),
  ('soccer', 'サッカー', 2),
  ('gaming', 'ゲーム攻略・検証', 3),
  ('pc_gadgets', 'PC・ガジェット', 4),
  ('science', '科学・実験', 5),
  ('history_culture', '歴史・文化', 6),
  ('occult', '心霊・オカルト', 7),
  ('nature', '生き物・自然', 8),
  ('food_culture', '料理・食文化', 9),
  ('outdoor_survival', 'アウトドア・サバイバル', 10)
on conflict do nothing;

insert into public.ability_definitions (code, name, display_order)
values
  ('planning', '企画力', 1),
  ('talking', 'トーク力', 2),
  ('expertise', '専門知識', 3),
  ('editing', '編集力', 4),
  ('visual', 'ビジュアル', 5),
  ('filming', '撮影技術', 6)
on conflict do nothing;

insert into public.equipment_types (code, name, display_order)
values
  ('camera', 'カメラ', 1),
  ('microphone', 'マイク', 2),
  ('editing_pc', '編集PC', 3)
on conflict do nothing;

insert into public.action_definitions (code, name, description)
values
  ('part_time_job', 'アルバイト', '所持金を稼ぐ'),
  ('rest', '休憩', '体力を回復する'),
  ('collaboration', 'コラボ', 'コラボ動画を投稿する'),
  ('sponsorship', '企業案件', '企業案件を受ける')
on conflict do nothing;

insert into public.feature_definitions (code, name)
values
  ('ad_revenue', '広告収益'),
  ('collaboration', 'コラボ'),
  ('sponsorship', '企業案件')
on conflict do nothing;

insert into public.event_categories (code, name)
values
  ('good', '良いイベント'),
  ('bad', '悪いイベント')
on conflict do nothing;

insert into public.event_definitions (code, category_code, name)
values
  ('featured_in_recommendations', 'good', 'おすすめに掲載'),
  ('introduced_by_celebrity', 'good', '有名人に紹介される'),
  ('temporary_bonus', 'good', '臨時ボーナス'),
  ('poorly_received_video', 'bad', '動画が不評'),
  ('equipment_trouble', 'bad', '機材トラブル'),
  ('criticized_on_social_media', 'bad', 'SNSで批判される')
on conflict do nothing;

-- Numeric rules are added by later tickets, so this version must not be
-- published until those rules and publication checks are complete.
insert into public.rule_sets (id, version, status)
values ('00000000-0000-4000-8000-000000000001', '1.0.0', 'draft')
on conflict do nothing;

insert into public.global_rules (
  rule_set_id,
  base_views_min,
  base_views_max,
  energy_max,
  unavailable_energy_recovery,
  ideas_per_week,
  idea_stock_max,
  flame_subscriber_loss_rate,
  flame_energy_loss,
  ban_flame_count,
  ad_revenue_per_view,
  system_idea_view_multiplier,
  system_idea_subscriber_conversion_rate
)
select
  '00000000-0000-4000-8000-000000000001',
  0,
  100000,
  100,
  10,
  3,
  30,
  0.05,
  20,
  3,
  0.2,
  0.6,
  0.02
where exists (
  select 1 from public.rule_sets
  where id = '00000000-0000-4000-8000-000000000001' and status = 'draft'
)
on conflict do nothing;

insert into public.channel_rules (id, rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability)
select * from (values
  ('00000000-0000-4000-8100-000000001001'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'mainstream', 1.0, 0.001),
  ('00000000-0000-4000-8100-000000001002'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'specialized', 1.0, 0.001),
  ('00000000-0000-4000-8100-000000001003'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'controversial', 1.5, 0.05),
  ('00000000-0000-4000-8100-000000001004'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'idol', 1.0, 0.001)
) as seed(id, rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.channel_ability_weights (id, rule_set_id, channel_rule_id, ability_code, weight)
select * from (values
  ('00000000-0000-4000-8100-000000001101'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001001'::uuid, 'planning', 0.5),
  ('00000000-0000-4000-8100-000000001102'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001001'::uuid, 'talking', 0.5),
  ('00000000-0000-4000-8100-000000001103'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001002'::uuid, 'expertise', 0.5),
  ('00000000-0000-4000-8100-000000001104'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001002'::uuid, 'editing', 0.5),
  ('00000000-0000-4000-8100-000000001105'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001003'::uuid, 'talking', 0.5),
  ('00000000-0000-4000-8100-000000001106'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001003'::uuid, 'planning', 0.5),
  ('00000000-0000-4000-8100-000000001107'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001004'::uuid, 'visual', 0.5),
  ('00000000-0000-4000-8100-000000001108'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, '00000000-0000-4000-8100-000000001004'::uuid, 'filming', 0.5)
) as seed(id, rule_set_id, channel_rule_id, ability_code, weight)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.rule_set_specialties (rule_set_id, specialty_code)
select * from (values
  ('00000000-0000-4000-8000-000000000001'::uuid, 'baseball'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'soccer'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'gaming'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'pc_gadgets'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'science'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'history_culture'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'occult'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'nature'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'food_culture'),
  ('00000000-0000-4000-8000-000000000001'::uuid, 'outdoor_survival')
) as seed(rule_set_id, specialty_code)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.posting_frequency_rules (
  id, rule_set_id, videos_per_week, view_multiplier, energy_cost, ability_points_awarded
)
select * from (values
  ('00000000-0000-4000-8100-000000001201'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 1, 1.2, 3, 3),
  ('00000000-0000-4000-8100-000000001202'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 3, 1.0, 8, 7),
  ('00000000-0000-4000-8100-000000001203'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 7, 0.8, 25, 15)
) as seed(id, rule_set_id, videos_per_week, view_multiplier, energy_cost, ability_points_awarded)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.idea_score_band_rules (
  id, rule_set_id, min_score, max_score, view_multiplier, subscriber_conversion_rate
)
select * from (values
  ('00000000-0000-4000-8100-000000001301'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 0, 39, 0.5, 0.01),
  ('00000000-0000-4000-8100-000000001302'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 40, 59, 0.8, 0.02),
  ('00000000-0000-4000-8100-000000001303'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 60, 79, 1.0, 0.03),
  ('00000000-0000-4000-8100-000000001304'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 80, 89, 1.3, 0.04),
  ('00000000-0000-4000-8100-000000001305'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 90, 100, 1.7, 0.05)
) as seed(id, rule_set_id, min_score, max_score, view_multiplier, subscriber_conversion_rate)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.equipment_tier_rules (
  id, rule_set_id, equipment_type_code, tier, purchase_price, view_bonus
)
select * from (values
  ('00000000-0000-4000-8100-000000001401'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'camera', 'none', 0::bigint, 0.00),
  ('00000000-0000-4000-8100-000000001402'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'camera', 'beginner', 30000::bigint, 0.05),
  ('00000000-0000-4000-8100-000000001403'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'camera', 'intermediate', 150000::bigint, 0.10),
  ('00000000-0000-4000-8100-000000001404'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'camera', 'advanced', 500000::bigint, 0.15),
  ('00000000-0000-4000-8100-000000001405'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'microphone', 'none', 0::bigint, 0.00),
  ('00000000-0000-4000-8100-000000001406'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'microphone', 'beginner', 5000::bigint, 0.05),
  ('00000000-0000-4000-8100-000000001407'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'microphone', 'intermediate', 30000::bigint, 0.10),
  ('00000000-0000-4000-8100-000000001408'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'microphone', 'advanced', 100000::bigint, 0.15),
  ('00000000-0000-4000-8100-000000001409'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'editing_pc', 'none', 0::bigint, 0.00),
  ('00000000-0000-4000-8100-000000001410'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'editing_pc', 'beginner', 50000::bigint, 0.05),
  ('00000000-0000-4000-8100-000000001411'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'editing_pc', 'intermediate', 200000::bigint, 0.10),
  ('00000000-0000-4000-8100-000000001412'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'editing_pc', 'advanced', 500000::bigint, 0.15)
) as seed(id, rule_set_id, equipment_type_code, tier, purchase_price, view_bonus)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.feature_rules (
  id, rule_set_id, feature_code, unlock_subscribers, activation_delay_weeks, is_persistent
)
select * from (values
  ('00000000-0000-4000-8100-000000001501'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'ad_revenue', 3000::bigint, 1, true),
  ('00000000-0000-4000-8100-000000001502'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'collaboration', 50000::bigint, 1, true),
  ('00000000-0000-4000-8100-000000001503'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'sponsorship', 100000::bigint, 1, true)
) as seed(id, rule_set_id, feature_code, unlock_subscribers, activation_delay_weeks, is_persistent)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.action_rules (
  id, rule_set_id, action_code, required_feature_code, cooldown_weeks, fixed_cash_delta, energy_delta, video_view_multiplier
)
select * from (values
  ('00000000-0000-4000-8100-000000001601'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'part_time_job', null::text, 0, 10000::bigint, -10, 1.0),
  ('00000000-0000-4000-8100-000000001602'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'rest', null::text, 0, 0::bigint, 50, 1.0),
  ('00000000-0000-4000-8100-000000001603'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'collaboration', 'collaboration', 2, 0::bigint, -10, 1.5),
  ('00000000-0000-4000-8100-000000001604'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'sponsorship', 'sponsorship', 4, 0::bigint, -5, 1.0)
) as seed(id, rule_set_id, action_code, required_feature_code, cooldown_weeks, fixed_cash_delta, energy_delta, video_view_multiplier)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.sponsorship_reward_rules (
  id, rule_set_id, min_subscribers, max_subscribers, reward_amount
)
select * from (values
  ('00000000-0000-4000-8100-000000001701'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 100000::bigint, 299999::bigint, 100000::bigint),
  ('00000000-0000-4000-8100-000000001702'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 300000::bigint, 499999::bigint, 200000::bigint),
  ('00000000-0000-4000-8100-000000001703'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 500000::bigint, 999999::bigint, 400000::bigint),
  ('00000000-0000-4000-8100-000000001704'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 1000000::bigint, 4999999::bigint, 800000::bigint),
  ('00000000-0000-4000-8100-000000001705'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 5000000::bigint, 9999999::bigint, 1200000::bigint),
  ('00000000-0000-4000-8100-000000001706'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 10000000::bigint, null::bigint, 2000000::bigint)
) as seed(id, rule_set_id, min_subscribers, max_subscribers, reward_amount)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.goal_rules (id, rule_set_id, stage_number, target_subscribers, duration_weeks, is_final)
select * from (values
  ('00000000-0000-4000-8100-000000001801'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 1, 100000::bigint, 156, false),
  ('00000000-0000-4000-8100-000000001802'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 2, 500000::bigint, 156, false),
  ('00000000-0000-4000-8100-000000001803'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 3, 1000000::bigint, 156, false),
  ('00000000-0000-4000-8100-000000001804'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 4, 3000000::bigint, 156, false),
  ('00000000-0000-4000-8100-000000001805'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 5, 10000000::bigint, 156, true)
) as seed(id, rule_set_id, stage_number, target_subscribers, duration_weeks, is_final)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.event_category_rules (id, rule_set_id, category_code, weekly_probability)
select * from (values
  ('00000000-0000-4000-8100-000000001901'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'good', 0.05),
  ('00000000-0000-4000-8100-000000001902'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'bad', 0.05)
) as seed(id, rule_set_id, category_code, weekly_probability)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.event_rules (
  id, rule_set_id, event_definition_code, category_code, selection_weight,
  weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier
)
select * from (values
  ('00000000-0000-4000-8100-000000002001'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'featured_in_recommendations', 'good', 1, 2.0, 0::bigint, 0::bigint, 1.0),
  ('00000000-0000-4000-8100-000000002002'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'introduced_by_celebrity', 'good', 1, 1.0, 0::bigint, 5000::bigint, 1.0),
  ('00000000-0000-4000-8100-000000002003'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'temporary_bonus', 'good', 1, 1.0, 50000::bigint, 0::bigint, 1.0),
  ('00000000-0000-4000-8100-000000002004'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'poorly_received_video', 'bad', 1, 0.5, 0::bigint, 0::bigint, 1.0),
  ('00000000-0000-4000-8100-000000002005'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'equipment_trouble', 'bad', 1, 1.0, -30000::bigint, 0::bigint, 1.0),
  ('00000000-0000-4000-8100-000000002006'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 'criticized_on_social_media', 'bad', 1, 1.0, 0::bigint, 0::bigint, 0.97)
) as seed(
  id, rule_set_id, event_definition_code, category_code, selection_weight,
  weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier
)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

insert into public.health_risk_rules (
  id, rule_set_id, min_energy, max_energy, occurrence_probability, min_unavailable_weeks, max_unavailable_weeks
)
select * from (values
  ('00000000-0000-4000-8100-000000002101'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 50, 100, 0.00, 0, 0),
  ('00000000-0000-4000-8100-000000002102'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 30, 49, 0.05, 1, 2),
  ('00000000-0000-4000-8100-000000002103'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 10, 29, 0.15, 3, 6),
  ('00000000-0000-4000-8100-000000002104'::uuid, '00000000-0000-4000-8000-000000000001'::uuid, 1, 9, 0.30, 8, 12)
) as seed(id, rule_set_id, min_energy, max_energy, occurrence_probability, min_unavailable_weeks, max_unavailable_weeks)
where exists (select 1 from public.rule_sets where id = seed.rule_set_id and status = 'draft')
on conflict do nothing;

commit;
