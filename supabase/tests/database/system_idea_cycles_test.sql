begin;

set local search_path = extensions, public, pg_catalog;

select plan(53);

select has_table('public', 'system_idea_templates', 'system_idea_templates exists');
select has_table('public', 'rule_set_system_ideas', 'rule_set_system_ideas exists');
select has_table('public', 'system_idea_cycles', 'system_idea_cycles exists');
select has_table('public', 'system_idea_cycle_entries', 'system_idea_cycle_entries exists');

select ok(
  not exists (
    select 1
    from (values
      ('system_idea_templates_code_format_check'),
      ('system_idea_templates_specialty_check'),
      ('rule_set_system_ideas_rule_set_template_key'),
      ('system_idea_cycles_run_cycle_key'),
      ('system_idea_cycle_entries_position_check'),
      ('system_idea_cycle_entries_cycle_position_key'),
      ('system_idea_cycle_entries_cycle_rule_set_idea_key')
    ) as expected(constraint_name)
    where not exists (
      select 1
      from pg_catalog.pg_constraint
      where connamespace = 'public'::regnamespace
        and conname = expected.constraint_name
    )
  ),
  'required check and unique constraints exist'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'system_idea_cycle_entries'
      and column_name in ('used', 'is_used', 'consumed', 'used_week', 'published')
  ),
  'cycle entries do not duplicate derived usage state'
);

select lives_ok(
  $$
    insert into public.system_idea_templates (
      id, code, channel_type_code, title, description
    ) values (
      '41000000-0000-4000-8000-000000000001',
      'test_mainstream_a',
      'mainstream',
      'Mainstream A',
      'A valid mainstream system idea.'
    )
  $$,
  'a non-specialized template can be created without a specialty'
);

select lives_ok(
  $$
    insert into public.system_idea_templates (
      id, code, channel_type_code, specialty_code, title, description
    ) values (
      '41000000-0000-4000-8000-000000000004',
      'test_specialized_baseball',
      'specialized',
      'baseball',
      'Baseball idea',
      'A valid specialized baseball system idea.'
    )
  $$,
  'a specialized template can be created with a specialty'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, title, description) values ('test_specialized_missing', 'specialized', 'Missing specialty', 'Description')$$,
  '23514', null, 'specialized templates require a specialty'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, specialty_code, title, description) values ('test_mainstream_specialty', 'mainstream', 'baseball', 'Unexpected specialty', 'Description')$$,
  '23514', null, 'non-specialized templates reject specialties'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, title, description) values ('test_unknown_channel', 'unknown', 'Unknown channel', 'Description')$$,
  '23503', null, 'unknown channel types are rejected'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, specialty_code, title, description) values ('test_unknown_specialty', 'specialized', 'unknown', 'Unknown specialty', 'Description')$$,
  '23503', null, 'unknown specialties are rejected'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, title, description) values ('test_mainstream_a', 'mainstream', 'Duplicate code', 'Description')$$,
  '23505', null, 'template codes are unique'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, title, description) values ('Invalid-Code', 'mainstream', 'Invalid code', 'Description')$$,
  '23514', null, 'template codes use snake_case'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, title, description) values ('test_blank_title', 'mainstream', '   ', 'Description')$$,
  '23514', null, 'blank titles are rejected'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, title, description) values ('test_long_title', 'mainstream', repeat('a', 101), 'Description')$$,
  '23514', null, 'titles longer than 100 characters are rejected'
);

select throws_ok(
  $$insert into public.system_idea_templates (code, channel_type_code, title, description) values ('test_blank_description', 'mainstream', 'Blank description', '   ')$$,
  '23514', null, 'blank descriptions are rejected'
);

insert into public.system_idea_templates (
  id, code, channel_type_code, specialty_code, title, description, enabled
) values
  ('41000000-0000-4000-8000-000000000002', 'test_mainstream_b', 'mainstream', null, 'Mainstream B', 'A second mainstream idea.', true),
  ('41000000-0000-4000-8000-000000000003', 'test_controversial', 'controversial', null, 'Controversial', 'A controversial idea.', true),
  ('41000000-0000-4000-8000-000000000005', 'test_specialized_soccer', 'specialized', 'soccer', 'Soccer idea', 'A specialized soccer idea.', true),
  ('41000000-0000-4000-8000-000000000006', 'test_disabled_template', 'mainstream', null, 'Disabled template', 'A globally disabled idea.', false),
  ('41000000-0000-4000-8000-000000000007', 'test_disabled_rule_idea', 'mainstream', null, 'Disabled association', 'An idea disabled in one rule set.', true),
  ('41000000-0000-4000-8000-000000000008', 'test_publish_guard', 'mainstream', null, 'Publish guard', 'A template used to test publication protection.', true);

insert into public.rule_sets (id, version)
values ('42000000-0000-4000-8000-000000000001', 'be007-other-rule-set');

insert into public.channel_rules (
  id, rule_set_id, channel_type_code, view_multiplier, weekly_flame_probability
) values (
  '42000000-0000-4000-8100-000000000001',
  '42000000-0000-4000-8000-000000000001',
  'mainstream',
  1,
  0.001
);

select lives_ok(
  $$
    insert into public.rule_set_system_ideas (
      id, rule_set_id, system_idea_template_id
    ) values (
      '43000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000001',
      '41000000-0000-4000-8000-000000000001'
    )
  $$,
  'a rule set can be associated with a system idea'
);

select throws_ok(
  $$insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id) values ('00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000001')$$,
  '23505', null, 'a rule set cannot contain the same template twice'
);

select throws_ok(
  $$insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id) values ('42000000-0000-4000-8000-999999999999', '41000000-0000-4000-8000-000000000001')$$,
  'P0001', 'Rules can only be written under draft rule sets',
  'associations require an existing writable rule set'
);

select throws_ok(
  $$insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id) values ('00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-999999999999')$$,
  '23503', null, 'associations require an existing template'
);

insert into public.rule_set_system_ideas (
  id, rule_set_id, system_idea_template_id, enabled
) values
  ('43000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000002', true),
  ('43000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000003', true),
  ('43000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000004', true),
  ('43000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000005', true),
  ('43000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000006', true),
  ('43000000-0000-4000-8000-000000000007', '00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000007', false),
  ('43000000-0000-4000-8000-000000000008', '42000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000001', true),
  ('43000000-0000-4000-8000-000000000009', '00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000008', true);

select throws_ok(
  $$update public.rule_set_system_ideas set rule_set_id = '42000000-0000-4000-8000-000000000001' where id = '43000000-0000-4000-8000-000000000001'$$,
  '23514', 'Rule set system idea associations cannot be reassigned',
  'an association rule set cannot be replaced'
);

select throws_ok(
  $$update public.rule_set_system_ideas set system_idea_template_id = '41000000-0000-4000-8000-000000000002' where id = '43000000-0000-4000-8000-000000000001'$$,
  '23514', 'Rule set system idea associations cannot be reassigned',
  'an associated template cannot be replaced'
);

insert into auth.users (id)
values
  ('44000000-0000-4000-8000-000000000001'),
  ('44000000-0000-4000-8000-000000000002'),
  ('44000000-0000-4000-8000-000000000003'),
  ('44000000-0000-4000-8000-000000000004');

insert into public.game_runs (
  id, user_id, rule_set_id, channel_rule_id, specialty_code, channel_name
) values
  ('45000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001001', null, 'Mainstream run'),
  ('45000000-0000-4000-8000-000000000002', '44000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001001', null, 'Other mainstream run'),
  ('45000000-0000-4000-8000-000000000003', '44000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8100-000000001002', 'baseball', 'Baseball run'),
  ('45000000-0000-4000-8000-000000000004', '44000000-0000-4000-8000-000000000004', '42000000-0000-4000-8000-000000000001', '42000000-0000-4000-8100-000000000001', null, 'Other rule-set run');

select lives_ok(
  $$insert into public.system_idea_cycles (id, run_id, cycle_number, created_week) values ('46000000-0000-4000-8000-000000000001', '45000000-0000-4000-8000-000000000001', 1, 1)$$,
  'a first cycle can be created for a game run'
);

select throws_ok(
  $$insert into public.system_idea_cycles (run_id, cycle_number, created_week) values ('45000000-0000-4000-8000-000000000001', 1, 2)$$,
  '23505', null, 'cycle numbers are unique within a game run'
);

select lives_ok(
  $$insert into public.system_idea_cycles (id, run_id, cycle_number, created_week) values ('46000000-0000-4000-8000-000000000005', '45000000-0000-4000-8000-000000000002', 1, 1)$$,
  'different game runs can use the same cycle number'
);

select throws_ok(
  $$insert into public.system_idea_cycles (run_id, cycle_number, created_week) values ('45000000-0000-4000-8000-000000000001', 0, 1)$$,
  '23514', null, 'cycle zero is rejected'
);

select throws_ok(
  $$insert into public.system_idea_cycles (run_id, cycle_number, created_week) values ('45000000-0000-4000-8000-000000000001', 5, 0)$$,
  '23514', null, 'created week zero is rejected'
);

insert into public.system_idea_cycles (id, run_id, cycle_number, created_week)
values
  ('46000000-0000-4000-8000-000000000002', '45000000-0000-4000-8000-000000000001', 2, 2),
  ('46000000-0000-4000-8000-000000000003', '45000000-0000-4000-8000-000000000001', 3, 3),
  ('46000000-0000-4000-8000-000000000004', '45000000-0000-4000-8000-000000000001', 4, 4),
  ('46000000-0000-4000-8000-000000000006', '45000000-0000-4000-8000-000000000003', 1, 1);

select throws_ok(
  $$update public.system_idea_cycles set run_id = '45000000-0000-4000-8000-000000000002' where id = '46000000-0000-4000-8000-000000000001'$$,
  '23514', 'System idea cycle run and cycle number are immutable',
  'a cycle cannot be reassigned to another game run'
);

select throws_ok(
  $$update public.system_idea_cycles set cycle_number = 2 where id = '46000000-0000-4000-8000-000000000001'$$,
  '23514', 'System idea cycle run and cycle number are immutable',
  'a cycle number cannot be changed'
);

select lives_ok(
  $$insert into public.system_idea_cycle_entries (id, cycle_id, rule_set_system_idea_id, position) values ('47000000-0000-4000-8000-000000000001', '46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000001', 1)$$,
  'a matching rule set and channel idea can be added to a cycle'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000002', 1)$$,
  '23505', null, 'positions cannot repeat within a cycle'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000001', 2)$$,
  '23505', null, 'ideas cannot repeat within a cycle'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000002', 0)$$,
  '23514', null, 'position zero is rejected'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000002', 51)$$,
  '23514', null, 'positions above 50 are rejected'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000008', 2)$$,
  '23514', 'System idea rule set does not match the game run',
  'ideas from another rule set are rejected'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000003', 2)$$,
  '23514', 'System idea channel type does not match the game run',
  'ideas from another channel type are rejected'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000006', '43000000-0000-4000-8000-000000000005', 1)$$,
  '23514', 'System idea specialty does not match the game run',
  'ideas from another specialty are rejected'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000006', 2)$$,
  '23514', 'System idea template is disabled',
  'globally disabled templates are rejected'
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000007', 2)$$,
  '23514', 'System idea is disabled for the cycle rule set',
  'ideas disabled in the rule set are rejected'
);

select lives_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000006', '43000000-0000-4000-8000-000000000004', 1)$$,
  'a matching specialized idea can be added to a cycle'
);

select throws_ok(
  $$update public.system_idea_cycle_entries set position = 2 where id = '47000000-0000-4000-8000-000000000001'$$,
  '23514', 'System idea cycle entry order is immutable',
  'an entry position cannot be changed'
);

select throws_ok(
  $$update public.system_idea_cycle_entries set cycle_id = '46000000-0000-4000-8000-000000000002' where id = '47000000-0000-4000-8000-000000000001'$$,
  '23514', 'System idea cycle entry order is immutable',
  'an entry cycle cannot be changed'
);

select throws_ok(
  $$update public.system_idea_cycle_entries set rule_set_system_idea_id = '43000000-0000-4000-8000-000000000002' where id = '47000000-0000-4000-8000-000000000001'$$,
  '23514', 'System idea cycle entry order is immutable',
  'an entry idea cannot be changed'
);

select throws_ok(
  $$delete from public.system_idea_cycle_entries where id = '47000000-0000-4000-8000-000000000001'$$,
  '23514', 'System idea cycle entries cannot be deleted',
  'created entries cannot be deleted'
);

insert into public.system_idea_cycle_entries (
  cycle_id, rule_set_system_idea_id, position
) values (
  '46000000-0000-4000-8000-000000000001',
  '43000000-0000-4000-8000-000000000002',
  50
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000002', '43000000-0000-4000-8000-000000000002', 1)$$,
  '23514', 'Adjacent system idea cycles cannot repeat the same boundary template',
  'the next cycle first entry cannot repeat the previous last template'
);

insert into public.system_idea_cycle_entries (
  cycle_id, rule_set_system_idea_id, position
) values (
  '46000000-0000-4000-8000-000000000004',
  '43000000-0000-4000-8000-000000000001',
  1
);

select throws_ok(
  $$insert into public.system_idea_cycle_entries (cycle_id, rule_set_system_idea_id, position) values ('46000000-0000-4000-8000-000000000003', '43000000-0000-4000-8000-000000000001', 50)$$,
  '23514', 'Adjacent system idea cycles cannot repeat the same boundary template',
  'boundary duplication is rejected when the previous last entry is inserted second'
);

select lives_ok(
  $$update public.rule_sets set status = 'active', published_at = statement_timestamp() where id = '00000000-0000-4000-8000-000000000001'$$,
  'the complete initial rule set can be published for immutability checks'
);

select throws_ok(
  $$update public.system_idea_templates set title = 'Changed published title' where id = '41000000-0000-4000-8000-000000000008'$$,
  '23514', 'System idea content referenced by a published rule set is immutable',
  'content referenced by a published rule set cannot be changed'
);

select lives_ok(
  $$update public.system_idea_templates set enabled = false where id = '41000000-0000-4000-8000-000000000008'$$,
  'the global availability switch remains operational after publication'
);

select throws_ok(
  $$update public.rule_set_system_ideas set enabled = false where id = '43000000-0000-4000-8000-000000000009'$$,
  'P0001', 'Rules belonging to published rule sets are immutable',
  'published rule-set associations cannot be changed'
);

select throws_ok(
  $$delete from public.rule_set_system_ideas where id = '43000000-0000-4000-8000-000000000009'$$,
  'P0001', 'Rules belonging to published rule sets are immutable',
  'published rule-set associations cannot be deleted'
);

select throws_ok(
  $$insert into public.rule_set_system_ideas (rule_set_id, system_idea_template_id) values ('00000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000002')$$,
  'P0001', 'Rules can only be written under draft rule sets',
  'published rule sets reject new associations'
);

select * from finish();

rollback;
