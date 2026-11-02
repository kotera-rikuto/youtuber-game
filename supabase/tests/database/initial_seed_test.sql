begin;

set local search_path = extensions, public, pg_catalog;

select plan(30);

select is(
  (select count(*)::integer from public.rule_sets where version = '1.0.0'),
  1,
  'the initial rule set exists exactly once'
);

select is(
  (select status from public.rule_sets where version = '1.0.0'),
  'active',
  'the initial rule set is active'
);

select isnt(
  (select published_at from public.rule_sets where version = '1.0.0'),
  null,
  'the initial rule set has a publication timestamp'
);

select lives_ok(
  $$select public.validate_rule_set_for_publication('00000000-0000-4000-8000-000000000001')$$,
  'the initial rule set passes publication validation'
);

select is(
  (select count(*)::integer from public.system_idea_templates),
  650,
  '650 system idea templates are seeded'
);

select is(
  (
    select count(*)::integer from public.rule_set_system_ideas
    where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  650,
  'the initial rule set has 650 system idea associations'
);

select is(
  (select count(*)::integer from public.system_idea_templates where channel_type_code = 'mainstream'),
  50,
  'the mainstream pool has 50 ideas'
);

select is(
  (select count(*)::integer from public.system_idea_templates where channel_type_code = 'controversial'),
  50,
  'the controversial pool has 50 ideas'
);

select is(
  (select count(*)::integer from public.system_idea_templates where channel_type_code = 'idol'),
  50,
  'the idol pool has 50 ideas'
);

select is(
  (select count(*)::integer from public.system_idea_templates where channel_type_code = 'specialized'),
  500,
  'the specialized pools have 500 ideas in total'
);

select is(
  (select count(*)::integer from public.system_idea_templates where enabled),
  650,
  'all 650 seeded templates are enabled'
);

select is(
  (
    select count(*)::integer
    from public.rule_set_system_ideas
    where rule_set_id = '00000000-0000-4000-8000-000000000001' and enabled
  ),
  650,
  'all 650 initial associations are enabled'
);

select ok(
  not exists (
    select 1 from public.system_idea_templates
    where channel_type_code <> 'specialized' and specialty_code is not null
  ),
  'non-specialized ideas have no specialty'
);

select ok(
  not exists (
    select 1 from public.system_idea_templates
    where channel_type_code = 'specialized' and specialty_code is null
  ),
  'specialized ideas always have a specialty'
);

select ok(
  not exists (
    select specialty_code
    from public.system_idea_templates
    where channel_type_code = 'specialized' and enabled
    group by specialty_code
    having count(*) <> 50
  ) and (
    select count(distinct specialty_code)
    from public.system_idea_templates
    where channel_type_code = 'specialized' and enabled
  ) = 10,
  'all ten specialized pools have 50 enabled ideas each'
);

select is(
  (
    select jsonb_build_array(code, channel_type_code, specialty_code, title, enabled)
    from public.system_idea_templates where code = 'mainstream_001'
  ),
  '["mainstream_001","mainstream",null,"【予算1万円】一日でどこまで楽しめる？",true]'::jsonb,
  'a representative mainstream idea matches JSON'
);

select is(
  (
    select jsonb_build_array(code, channel_type_code, specialty_code, title, enabled)
    from public.system_idea_templates where code = 'controversial_001'
  ),
  '["controversial_001","controversial",null,"【大炎上】店の商品を勝手に全部並べ替えてみた",true]'::jsonb,
  'a representative controversial idea matches JSON'
);

select is(
  (
    select jsonb_build_array(code, channel_type_code, specialty_code, title, enabled)
    from public.system_idea_templates where code = 'specialized_baseball_001'
  ),
  '["specialized_baseball_001","specialized","baseball","初心者が最初に覚えたい野球の基本ルール10選",true]'::jsonb,
  'a representative specialized idea matches JSON'
);

select is(
  (
    select jsonb_build_array(
      base_views_min, base_views_max, energy_max, unavailable_energy_recovery,
      ideas_per_week, idea_stock_max, flame_subscriber_loss_rate, flame_energy_loss,
      ban_flame_count, ad_revenue_per_view, system_idea_view_multiplier,
      system_idea_subscriber_conversion_rate
    ) from public.global_rules
    where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[0,100000,100,10,3,30,0.05,20,3,0.2,0.6,0.02]'::jsonb,
  'global numeric rules match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(channel_type_code, view_multiplier, weekly_flame_probability) order by channel_type_code)
    from public.channel_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[["controversial",1.5,0.05],["idol",1.0,0.001],["mainstream",1.0,0.001],["specialized",1.0,0.001]]'::jsonb,
  'channel multipliers and flame probabilities match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(videos_per_week, view_multiplier, energy_cost, ability_points_awarded) order by videos_per_week)
    from public.posting_frequency_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[[1,1.2,3,3],[3,1.0,8,7],[7,0.8,25,15]]'::jsonb,
  'posting frequency rules match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(min_score, max_score, view_multiplier, subscriber_conversion_rate) order by min_score)
    from public.idea_score_band_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[[0,39,0.5,0.01],[40,59,0.8,0.02],[60,79,1.0,0.03],[80,89,1.3,0.04],[90,100,1.7,0.05]]'::jsonb,
  'idea score bands match the specification'
);

select is(
  (select count(*)::integer from public.equipment_tier_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  12,
  'all twelve equipment price and bonus rules are seeded'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(feature_code, unlock_subscribers, activation_delay_weeks, is_persistent) order by feature_code)
    from public.feature_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[["ad_revenue",3000,1,true],["collaboration",50000,1,true],["sponsorship",100000,1,true]]'::jsonb,
  'feature unlock rules match the specification'
);

select is(
  (select count(*)::integer from public.sponsorship_reward_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  6,
  'all six sponsorship reward bands are seeded'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(category_code, weekly_probability) order by category_code)
    from public.event_category_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'
  ),
  '[["bad",0.05],["good",0.05]]'::jsonb,
  'random event probabilities match the specification'
);

select is(
  (select count(*)::integer from public.health_risk_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  4,
  'all four health risk bands are seeded'
);

select is(
  (select count(*)::integer from public.goal_rules where rule_set_id = '00000000-0000-4000-8000-000000000001'),
  5,
  'all five stage goals are seeded'
);

select throws_ok(
  $$update public.global_rules set energy_max = 99 where rule_set_id = '00000000-0000-4000-8000-000000000001'$$,
  'P0001',
  'Rules belonging to published rule sets are immutable',
  'published rules cannot be updated'
);

select throws_ok(
  $$delete from public.rule_set_system_ideas where rule_set_id = '00000000-0000-4000-8000-000000000001'$$,
  'P0001',
  'Rules belonging to published rule sets are immutable',
  'published idea associations cannot be deleted'
);

select * from finish();

rollback;
