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

commit;
