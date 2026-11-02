begin;

set local search_path = extensions, public, pg_catalog;

select plan(60);

select has_table('public', 'channel_types', 'channel_types exists');
select has_table('public', 'specialty_categories', 'specialty_categories exists');
select has_table('public', 'ability_definitions', 'ability_definitions exists');
select has_table('public', 'equipment_types', 'equipment_types exists');
select has_table('public', 'action_definitions', 'action_definitions exists');
select has_table('public', 'feature_definitions', 'feature_definitions exists');
select has_table('public', 'event_categories', 'event_categories exists');
select has_table('public', 'event_definitions', 'event_definitions exists');
select has_table('public', 'rule_sets', 'rule_sets exists');

select has_pk('public', 'channel_types', 'channel_types has a primary key');
select has_pk('public', 'specialty_categories', 'specialty_categories has a primary key');
select has_pk('public', 'ability_definitions', 'ability_definitions has a primary key');
select has_pk('public', 'equipment_types', 'equipment_types has a primary key');
select has_pk('public', 'action_definitions', 'action_definitions has a primary key');
select has_pk('public', 'feature_definitions', 'feature_definitions has a primary key');
select has_pk('public', 'event_categories', 'event_categories has a primary key');
select has_pk('public', 'event_definitions', 'event_definitions has a primary key');
select has_pk('public', 'rule_sets', 'rule_sets has a primary key');

select throws_ok(
  $$insert into public.channel_types (code, name) values ('mainstream', '重複コード')$$,
  '23505',
  null,
  'catalog primary keys reject duplicate codes'
);

select throws_ok(
  $$insert into public.channel_types (code, name) values ('test_channel', '王道系')$$,
  '23505',
  null,
  'catalog names are unique'
);

select throws_ok(
  $$insert into public.channel_types (code, name) values ('missing_name', null)$$,
  '23502',
  null,
  'required catalog names reject null'
);

select throws_ok(
  $$insert into public.channel_types (code, name) values ('Invalid-Code', '不正コード')$$,
  '23514',
  null,
  'catalog codes reject unstable formats'
);

select throws_ok(
  $$insert into public.channel_types (code, name) values ('blank_name', '   ')$$,
  '23514',
  null,
  'catalog names reject blank strings'
);

select throws_ok(
  $$insert into public.action_definitions (code, name, description) values ('blank_description', '空説明', '   ')$$,
  '23514',
  null,
  'action descriptions reject blank strings'
);

select throws_ok(
  $$insert into public.specialty_categories (code, name, display_order) values ('invalid_order', '不正順', 0)$$,
  '23514',
  null,
  'specialty display_order rejects zero'
);

select throws_ok(
  $$insert into public.ability_definitions (code, name, display_order) values ('invalid_order', '不正順', -1)$$,
  '23514',
  null,
  'ability display_order rejects negative values'
);

select throws_ok(
  $$insert into public.equipment_types (code, name, display_order) values ('invalid_order', '不正順', 0)$$,
  '23514',
  null,
  'equipment display_order rejects zero'
);

select throws_ok(
  $$insert into public.specialty_categories (code, name, display_order) values ('duplicate_order', '重複順', 1)$$,
  '23505',
  null,
  'specialty display_order is unique'
);

select throws_ok(
  $$insert into public.ability_definitions (code, name, display_order) values ('duplicate_order', '重複順', 1)$$,
  '23505',
  null,
  'ability display_order is unique'
);

select throws_ok(
  $$insert into public.equipment_types (code, name, display_order) values ('duplicate_order', '重複順', 1)$$,
  '23505',
  null,
  'equipment display_order is unique'
);

select throws_ok(
  $$insert into public.event_definitions (code, category_code, name) values ('unknown_category', 'unknown', '不正カテゴリ')$$,
  '23503',
  null,
  'event definitions reject unknown categories'
);

select throws_ok(
  $$insert into public.rule_sets (version, status) values ('invalid-status-test', 'invalid')$$,
  '23514',
  null,
  'rule_sets rejects invalid statuses'
);

select throws_ok(
  $$insert into public.rule_sets (version) values ('1.0.0')$$,
  '23505',
  null,
  'rule set versions are unique'
);

select throws_ok(
  $$insert into public.rule_sets (version) values (null)$$,
  '23502',
  null,
  'rule set versions reject null'
);

select throws_ok(
  $$insert into public.rule_sets (version) values ('   ')$$,
  '23514',
  null,
  'rule set versions reject blank strings'
);

select throws_ok(
  $$insert into public.rule_sets (version) values ('invalid version')$$,
  '23514',
  null,
  'rule set versions reject unstable formats'
);

select throws_ok(
  $$insert into public.rule_sets (version, status) values ('active-without-date', 'active')$$,
  '23514',
  null,
  'active rule sets require published_at'
);

select throws_ok(
  $$insert into public.rule_sets (version, status, published_at) values ('draft-with-date', 'draft', statement_timestamp())$$,
  '23514',
  null,
  'draft rule sets cannot have published_at'
);

select throws_ok(
  $$
    insert into public.rule_sets (version, status, created_at, published_at)
    values ('invalid-publication-time', 'active', '2026-01-02 00:00:00+00', '2026-01-01 00:00:00+00')
  $$,
  '23514',
  null,
  'published_at cannot predate created_at'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name) order by code)
    from public.channel_types
  ),
  '[
    ["controversial", "炎上系"],
    ["idol", "アイドル系"],
    ["mainstream", "王道系"],
    ["specialized", "特化系"]
  ]'::jsonb,
  'the four channel types match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name, display_order) order by display_order)
    from public.specialty_categories
  ),
  '[
    ["baseball", "野球", 1],
    ["soccer", "サッカー", 2],
    ["gaming", "ゲーム攻略・検証", 3],
    ["pc_gadgets", "PC・ガジェット", 4],
    ["science", "科学・実験", 5],
    ["history_culture", "歴史・文化", 6],
    ["occult", "心霊・オカルト", 7],
    ["nature", "生き物・自然", 8],
    ["food_culture", "料理・食文化", 9],
    ["outdoor_survival", "アウトドア・サバイバル", 10]
  ]'::jsonb,
  'the ten specialties have the specified codes, names, and order'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name, display_order) order by display_order)
    from public.ability_definitions
  ),
  '[
    ["planning", "企画力", 1],
    ["talking", "トーク力", 2],
    ["expertise", "専門知識", 3],
    ["editing", "編集力", 4],
    ["visual", "ビジュアル", 5],
    ["filming", "撮影技術", 6]
  ]'::jsonb,
  'the six abilities match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name, display_order) order by display_order)
    from public.equipment_types
  ),
  '[
    ["camera", "カメラ", 1],
    ["microphone", "マイク", 2],
    ["editing_pc", "編集PC", 3]
  ]'::jsonb,
  'the three equipment types match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name) order by code)
    from public.action_definitions
  ),
  '[
    ["collaboration", "コラボ"],
    ["part_time_job", "アルバイト"],
    ["rest", "休憩"],
    ["sponsorship", "企業案件"]
  ]'::jsonb,
  'the four weekly actions match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name) order by code)
    from public.feature_definitions
  ),
  '[
    ["ad_revenue", "広告収益"],
    ["collaboration", "コラボ"],
    ["sponsorship", "企業案件"]
  ]'::jsonb,
  'the unlockable features match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, name) order by code)
    from public.event_categories
    where code in ('good', 'bad')
  ),
  '[["bad", "悪いイベント"], ["good", "良いイベント"]]'::jsonb,
  'the good and bad event categories match the specification'
);

select is(
  (
    select jsonb_agg(jsonb_build_array(code, category_code, name) order by code)
    from public.event_definitions
    where category_code in ('good', 'bad')
  ),
  '[
    ["criticized_on_social_media", "bad", "SNSで批判される"],
    ["equipment_trouble", "bad", "機材トラブル"],
    ["featured_in_recommendations", "good", "おすすめに掲載"],
    ["introduced_by_celebrity", "good", "有名人に紹介される"],
    ["poorly_received_video", "bad", "動画が不評"],
    ["temporary_bonus", "good", "臨時ボーナス"]
  ]'::jsonb,
  'the six random events match the specification'
);

select is(
  (
    select jsonb_build_array(id::text, version, status, published_at)
    from public.rule_sets
    where version = '1.0.0'
  ),
  '["00000000-0000-4000-8000-000000000001", "1.0.0", "draft", null]'::jsonb,
  'the initial rule set has a stable id and remains draft'
);

select lives_ok(
  $$
    insert into public.rule_sets (id, version)
    values ('00000000-0000-4000-8000-000000000100', 'lifecycle-test')
  $$,
  'draft rule sets can be created'
);

select lives_ok(
  $$
    update public.rule_sets
    set version = 'lifecycle-test-updated'
    where id = '00000000-0000-4000-8000-000000000100'
  $$,
  'draft rule sets can be edited'
);

insert into public.system_idea_templates (
  code, channel_type_code, specialty_code, title, description
)
select
  'static_publication_' || pool.pool_code || '_' || item_number,
  pool.channel_type_code,
  pool.specialty_code,
  'Publication fixture ' || pool.pool_code || ' ' || item_number,
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
  where rule_set_id = '00000000-0000-4000-8000-000000000001'
) as pool
cross join pg_catalog.generate_series(1, 50) as item_number;

insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id)
select '00000000-0000-4000-8000-000000000001', id
from public.system_idea_templates
where code like 'static_publication_%';

select lives_ok(
  $$
    update public.rule_sets
    set status = 'active', published_at = statement_timestamp()
    where id = '00000000-0000-4000-8000-000000000001'
  $$,
  'complete draft rule sets can be published'
);

select throws_ok(
  $$
    update public.rule_sets
    set version = 'forbidden-published-edit'
    where id = '00000000-0000-4000-8000-000000000001'
  $$,
  'P0001',
  'Published rule set fields are immutable',
  'published rule set fields cannot be changed'
);

select lives_ok(
  $$
    update public.rule_sets
    set status = 'retired'
    where id = '00000000-0000-4000-8000-000000000001'
  $$,
  'active rule sets can be retired'
);

select throws_ok(
  $$
    update public.rule_sets
    set status = 'active'
    where id = '00000000-0000-4000-8000-000000000001'
  $$,
  'P0001',
  'Invalid published rule set status transition: retired to active',
  'retired rule sets cannot be reactivated'
);

select throws_ok(
  $$delete from public.rule_sets where id = '00000000-0000-4000-8000-000000000001'$$,
  'P0001',
  'Published rule sets cannot be deleted',
  'published rule sets cannot be deleted'
);

select lives_ok(
  $$
    insert into public.rule_sets (id, version)
    values ('00000000-0000-4000-8000-000000000101', 'deletable-draft')
  $$,
  'another draft rule set can be created'
);

select lives_ok(
  $$delete from public.rule_sets where id = '00000000-0000-4000-8000-000000000101'$$,
  'draft rule sets can be deleted'
);

select lives_ok(
  $$
    insert into public.rule_sets (id, version, status, published_at)
    values (
      '00000000-0000-4000-8000-000000000102',
      'single-active-test',
      'active',
      statement_timestamp()
    )
  $$,
  'an active rule set can exist when no other version is active'
);

select throws_ok(
  $$
    insert into public.rule_sets (id, version, status, published_at)
    values (
      '00000000-0000-4000-8000-000000000103',
      'second-active-test',
      'active',
      statement_timestamp()
    )
  $$,
  '23505',
  null,
  'only one rule set can be active'
);

select lives_ok(
  $$
    update public.rule_sets
    set status = 'retired'
    where id = '00000000-0000-4000-8000-000000000102'
  $$,
  'the active uniqueness slot is released by retirement'
);

select * from finish();

rollback;
