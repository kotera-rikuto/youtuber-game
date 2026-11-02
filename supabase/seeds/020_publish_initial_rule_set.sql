-- Validates and publishes the initial rule set after all catalog and idea seeds.
-- Re-running this file validates active 1.0.0 without writing to published rows.

begin;

do $publish_initial_rule_set$
declare
  initial_rule_set_id constant uuid := '00000000-0000-4000-8000-000000000001';
  initial_status text;
begin
  select status into initial_status
  from public.rule_sets
  where id = initial_rule_set_id
    and version = '1.0.0';

  if initial_status is null then
    raise exception 'Initial rule set 1.0.0 is missing or has an unexpected identifier';
  end if;

  if initial_status = 'retired' then
    raise exception 'Initial rule set 1.0.0 is retired and cannot be reactivated';
  end if;

  if exists (
    select 1
    from (values
      ('mainstream', '王道系'),
      ('specialized', '特化系'),
      ('controversial', '炎上系'),
      ('idol', 'アイドル系')
    ) as expected(code, name)
    where not exists (
      select 1 from public.channel_types as actual
      where actual.code = expected.code and actual.name = expected.name
    )
  ) then raise exception 'Channel type catalog does not match the initial seed'; end if;

  if exists (
    select 1
    from (values
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
    ) as expected(code, name, display_order)
    where not exists (
      select 1 from public.specialty_categories as actual
      where actual.code = expected.code
        and actual.name = expected.name
        and actual.display_order = expected.display_order
    )
  ) then raise exception 'Specialty catalog does not match the initial seed'; end if;

  if exists (
    select 1
    from (values
      ('planning', '企画力', 1),
      ('talking', 'トーク力', 2),
      ('expertise', '専門知識', 3),
      ('editing', '編集力', 4),
      ('visual', 'ビジュアル', 5),
      ('filming', '撮影技術', 6)
    ) as expected(code, name, display_order)
    where not exists (
      select 1 from public.ability_definitions as actual
      where actual.code = expected.code
        and actual.name = expected.name
        and actual.display_order = expected.display_order
    )
  ) then raise exception 'Ability catalog does not match the initial seed'; end if;

  if exists (
    select 1
    from (values
      ('camera', 'カメラ', 1),
      ('microphone', 'マイク', 2),
      ('editing_pc', '編集PC', 3)
    ) as expected(code, name, display_order)
    where not exists (
      select 1 from public.equipment_types as actual
      where actual.code = expected.code
        and actual.name = expected.name
        and actual.display_order = expected.display_order
    )
  ) then raise exception 'Equipment catalog does not match the initial seed'; end if;

  if exists (
    select 1
    from (values
      ('part_time_job', 'アルバイト', '所持金を稼ぐ'),
      ('rest', '休憩', '体力を回復する'),
      ('collaboration', 'コラボ', 'コラボ動画を投稿する'),
      ('sponsorship', '企業案件', '企業案件を受ける')
    ) as expected(code, name, description)
    where not exists (
      select 1 from public.action_definitions as actual
      where actual.code = expected.code
        and actual.name = expected.name
        and actual.description = expected.description
    )
  ) then raise exception 'Action catalog does not match the initial seed'; end if;

  if exists (
    select 1
    from (values
      ('ad_revenue', '広告収益'),
      ('collaboration', 'コラボ'),
      ('sponsorship', '企業案件')
    ) as expected(code, name)
    where not exists (
      select 1 from public.feature_definitions as actual
      where actual.code = expected.code and actual.name = expected.name
    )
  ) then raise exception 'Feature catalog does not match the initial seed'; end if;

  if exists (
    select 1
    from (values
      ('good', '良いイベント'),
      ('bad', '悪いイベント'),
      ('system', 'システムイベント')
    ) as expected(code, name)
    where not exists (
      select 1 from public.event_categories as actual
      where actual.code = expected.code and actual.name = expected.name
    )
  ) then raise exception 'Event category catalog does not match the initial seed'; end if;

  if exists (
    select 1
    from (values
      ('featured_in_recommendations', 'good', 'おすすめに掲載'),
      ('introduced_by_celebrity', 'good', '有名人に紹介される'),
      ('temporary_bonus', 'good', '臨時ボーナス'),
      ('poorly_received_video', 'bad', '動画が不評'),
      ('equipment_trouble', 'bad', '機材トラブル'),
      ('criticized_on_social_media', 'bad', 'SNSで批判される'),
      ('flame', 'system', '炎上')
    ) as expected(code, category_code, name)
    where not exists (
      select 1 from public.event_definitions as actual
      where actual.code = expected.code
        and actual.category_code = expected.category_code
        and actual.name = expected.name
    )
  ) then raise exception 'Event definition catalog does not match the initial seed'; end if;

  if (
    select jsonb_build_array(
      base_views_min, base_views_max, energy_max, unavailable_energy_recovery,
      ideas_per_week, idea_stock_max, flame_subscriber_loss_rate,
      flame_energy_loss, ban_flame_count, ad_revenue_per_view,
      system_idea_view_multiplier, system_idea_subscriber_conversion_rate
    )
    from public.global_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[0,100000,100,10,3,30,0.05,20,3,0.2,0.6,0.02]'::jsonb
  then raise exception 'Global rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(channel_type_code, view_multiplier, weekly_flame_probability)
      order by channel_type_code
    ) from public.channel_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    ["controversial",1.5,0.05], ["idol",1.0,0.001],
    ["mainstream",1.0,0.001], ["specialized",1.0,0.001]
  ]'::jsonb
  then raise exception 'Channel rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(channel_rule.channel_type_code, ability_weight.ability_code, ability_weight.weight)
      order by channel_rule.channel_type_code, ability_weight.ability_code
    )
    from public.channel_ability_weights as ability_weight
    join public.channel_rules as channel_rule on channel_rule.id = ability_weight.channel_rule_id
    where ability_weight.rule_set_id = initial_rule_set_id
  ) is distinct from '[
    ["controversial","planning",0.5], ["controversial","talking",0.5],
    ["idol","filming",0.5], ["idol","visual",0.5],
    ["mainstream","planning",0.5], ["mainstream","talking",0.5],
    ["specialized","editing",0.5], ["specialized","expertise",0.5]
  ]'::jsonb
  then raise exception 'Channel ability weights do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(videos_per_week, view_multiplier, energy_cost, ability_points_awarded)
      order by videos_per_week
    ) from public.posting_frequency_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[[1,1.2,3,3],[3,1.0,8,7],[7,0.8,25,15]]'::jsonb
  then raise exception 'Posting frequency rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(min_score, max_score, view_multiplier, subscriber_conversion_rate)
      order by min_score
    ) from public.idea_score_band_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    [0,39,0.5,0.01], [40,59,0.8,0.02], [60,79,1.0,0.03],
    [80,89,1.3,0.04], [90,100,1.7,0.05]
  ]'::jsonb
  then raise exception 'Idea score bands do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(equipment_type_code, tier, purchase_price, view_bonus)
      order by equipment_type_code, array_position(array['none', 'beginner', 'intermediate', 'advanced'], tier)
    ) from public.equipment_tier_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    ["camera","none",0,0.00], ["camera","beginner",30000,0.05],
    ["camera","intermediate",150000,0.10], ["camera","advanced",500000,0.15],
    ["editing_pc","none",0,0.00], ["editing_pc","beginner",50000,0.05],
    ["editing_pc","intermediate",200000,0.10], ["editing_pc","advanced",500000,0.15],
    ["microphone","none",0,0.00], ["microphone","beginner",5000,0.05],
    ["microphone","intermediate",30000,0.10], ["microphone","advanced",100000,0.15]
  ]'::jsonb
  then raise exception 'Equipment tier rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(feature_code, unlock_subscribers, activation_delay_weeks, is_persistent)
      order by feature_code
    ) from public.feature_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    ["ad_revenue",3000,1,true], ["collaboration",50000,1,true],
    ["sponsorship",100000,1,true]
  ]'::jsonb
  then raise exception 'Feature rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(
        action_code, required_feature_code, cooldown_weeks,
        fixed_cash_delta, energy_delta, video_view_multiplier
      ) order by action_code
    ) from public.action_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    ["collaboration","collaboration",2,0,-10,1.5],
    ["part_time_job",null,0,10000,-10,1.0],
    ["rest",null,0,0,50,1.0],
    ["sponsorship","sponsorship",4,0,-5,1.0]
  ]'::jsonb
  then raise exception 'Action rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(min_subscribers, max_subscribers, reward_amount)
      order by min_subscribers
    ) from public.sponsorship_reward_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    [100000,299999,100000], [300000,499999,200000],
    [500000,999999,400000], [1000000,4999999,800000],
    [5000000,9999999,1200000], [10000000,null,2000000]
  ]'::jsonb
  then raise exception 'Sponsorship reward rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(stage_number, target_subscribers, duration_weeks, is_final)
      order by stage_number
    ) from public.goal_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    [1,100000,156,false], [2,500000,156,false], [3,1000000,156,false],
    [4,3000000,156,false], [5,10000000,156,true]
  ]'::jsonb
  then raise exception 'Goal rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(jsonb_build_array(category_code, weekly_probability) order by category_code)
    from public.event_category_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[["bad",0.05],["good",0.05]]'::jsonb
  then raise exception 'Event category rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(
        event_definition_code, category_code, selection_weight,
        weekly_view_multiplier, fixed_cash_delta, fixed_subscriber_delta, subscriber_multiplier
      ) order by event_definition_code
    ) from public.event_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    ["criticized_on_social_media","bad",1,1.0,0,0,0.97],
    ["equipment_trouble","bad",1,1.0,-30000,0,1.0],
    ["featured_in_recommendations","good",1,2.0,0,0,1.0],
    ["introduced_by_celebrity","good",1,1.0,0,5000,1.0],
    ["poorly_received_video","bad",1,0.5,0,0,1.0],
    ["temporary_bonus","good",1,1.0,50000,0,1.0]
  ]'::jsonb
  then raise exception 'Event rules do not match the initial seed'; end if;

  if (
    select jsonb_agg(
      jsonb_build_array(
        min_energy, max_energy, occurrence_probability,
        min_unavailable_weeks, max_unavailable_weeks
      ) order by min_energy
    ) from public.health_risk_rules where rule_set_id = initial_rule_set_id
  ) is distinct from '[
    [1,9,0.30,8,12], [10,29,0.15,3,6],
    [30,49,0.05,1,2], [50,100,0.00,0,0]
  ]'::jsonb
  then raise exception 'Health risk rules do not match the initial seed'; end if;

  perform public.validate_rule_set_for_publication(initial_rule_set_id);

  if initial_status = 'draft' then
    update public.rule_sets
    set status = 'active', published_at = statement_timestamp()
    where id = initial_rule_set_id;
  end if;
end;
$publish_initial_rule_set$;

commit;
