create table public.system_idea_templates (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  code text not null unique,
  channel_type_code text not null,
  specialty_code text,
  title text not null,
  description text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default statement_timestamp(),
  constraint system_idea_templates_channel_type_code_fkey
    foreign key (channel_type_code)
    references public.channel_types (code)
    on update restrict
    on delete restrict,
  constraint system_idea_templates_specialty_code_fkey
    foreign key (specialty_code)
    references public.specialty_categories (code)
    on update restrict
    on delete restrict,
  constraint system_idea_templates_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint system_idea_templates_title_not_blank_check
    check (btrim(title) <> ''),
  constraint system_idea_templates_title_length_check
    check (char_length(title) between 1 and 100),
  constraint system_idea_templates_description_not_blank_check
    check (btrim(description) <> ''),
  constraint system_idea_templates_specialty_check
    check ((channel_type_code = 'specialized') = (specialty_code is not null))
);

create index system_idea_templates_enabled_pool_idx
  on public.system_idea_templates (channel_type_code, specialty_code)
  where enabled;

comment on table public.system_idea_templates is
  'Game-provided idea content. BE-011 seeds the JSON catalog; runtime selection reads this table instead of JSON.';

create table public.rule_set_system_ideas (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  system_idea_template_id uuid not null,
  enabled boolean not null default true,
  created_at timestamptz not null default statement_timestamp(),
  constraint rule_set_system_ideas_rule_set_id_fkey
    foreign key (rule_set_id)
    references public.rule_sets (id)
    on update restrict
    on delete restrict,
  constraint rule_set_system_ideas_system_idea_template_id_fkey
    foreign key (system_idea_template_id)
    references public.system_idea_templates (id)
    on update restrict
    on delete restrict,
  constraint rule_set_system_ideas_rule_set_template_key
    unique (rule_set_id, system_idea_template_id)
);

create index rule_set_system_ideas_enabled_rule_set_idx
  on public.rule_set_system_ideas (rule_set_id, system_idea_template_id)
  where enabled;

create index rule_set_system_ideas_template_idx
  on public.rule_set_system_ideas (system_idea_template_id);

create function public.protect_published_system_idea_template()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.code is not distinct from old.code
    and new.channel_type_code is not distinct from old.channel_type_code
    and new.specialty_code is not distinct from old.specialty_code
    and new.title is not distinct from old.title
    and new.description is not distinct from old.description
  then
    return new;
  end if;

  if exists (
    select 1
    from public.rule_set_system_ideas as rule_idea
    join public.rule_sets as rule_set on rule_set.id = rule_idea.rule_set_id
    where rule_idea.system_idea_template_id = old.id
      and (rule_set.status <> 'draft' or rule_set.published_at is not null)
  ) then
    raise exception using
      errcode = '23514',
      message = 'System idea content referenced by a published rule set is immutable';
  end if;

  return new;
end;
$$;

comment on function public.protect_published_system_idea_template() is
  'Preserves published idea content while leaving enabled as the explicit global availability switch. BE-009 owns complete publication validation.';

create function public.protect_rule_set_system_idea_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.rule_set_id is distinct from old.rule_set_id
    or new.system_idea_template_id is distinct from old.system_idea_template_id
  then
    raise exception using
      errcode = '23514',
      message = 'Rule set system idea associations cannot be reassigned';
  end if;

  return new;
end;
$$;

create trigger protect_rule_set_system_idea_identity
before update on public.rule_set_system_ideas
for each row
execute function public.protect_rule_set_system_idea_identity();

create trigger guard_rule_set_system_ideas_draft
before insert or update or delete on public.rule_set_system_ideas
for each row
execute function public.protect_versioned_rule_row();

create trigger protect_system_idea_template_content
before update on public.system_idea_templates
for each row
execute function public.protect_published_system_idea_template();

comment on table public.rule_set_system_ideas is
  'Rule-set-specific availability. Both this enabled flag and the referenced template enabled flag must be true for selection.';

create table public.system_idea_cycles (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null,
  cycle_number integer not null,
  created_week integer not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint system_idea_cycles_run_id_fkey
    foreign key (run_id)
    references public.game_runs (id)
    on update restrict
    on delete restrict,
  constraint system_idea_cycles_cycle_number_positive_check
    check (cycle_number >= 1),
  constraint system_idea_cycles_created_week_positive_check
    check (created_week >= 1),
  constraint system_idea_cycles_run_cycle_key
    unique (run_id, cycle_number)
);

create function public.protect_system_idea_cycle_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.run_id is distinct from old.run_id
    or new.cycle_number is distinct from old.cycle_number
  then
    raise exception using
      errcode = '23514',
      message = 'System idea cycle run and cycle number are immutable';
  end if;

  return new;
end;
$$;

create trigger protect_system_idea_cycle_identity
before update on public.system_idea_cycles
for each row
execute function public.protect_system_idea_cycle_identity();

create table public.system_idea_cycle_entries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  cycle_id uuid not null,
  rule_set_system_idea_id uuid not null,
  position smallint not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint system_idea_cycle_entries_cycle_id_fkey
    foreign key (cycle_id)
    references public.system_idea_cycles (id)
    on update restrict
    on delete restrict,
  constraint system_idea_cycle_entries_rule_set_system_idea_id_fkey
    foreign key (rule_set_system_idea_id)
    references public.rule_set_system_ideas (id)
    on update restrict
    on delete restrict,
  constraint system_idea_cycle_entries_position_check
    check (position between 1 and 50),
  constraint system_idea_cycle_entries_cycle_position_key
    unique (cycle_id, position),
  constraint system_idea_cycle_entries_cycle_rule_set_idea_key
    unique (cycle_id, rule_set_system_idea_id)
);

create index system_idea_cycle_entries_rule_set_idea_idx
  on public.system_idea_cycle_entries (rule_set_system_idea_id);

-- CHECK, foreign keys, and unique constraints cannot compare an entry with the
-- owning run's versioned channel selection or with entries in adjacent cycles.
create function public.validate_system_idea_cycle_entry()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  entry_run_id uuid;
  entry_cycle_number integer;
  run_rule_set_id uuid;
  run_channel_type_code text;
  run_specialty_code text;
  idea_rule_set_id uuid;
  idea_template_id uuid;
  idea_channel_type_code text;
  idea_specialty_code text;
  is_rule_idea_enabled boolean;
  is_template_enabled boolean;
begin
  select cycle.run_id, cycle.cycle_number
  into entry_run_id, entry_cycle_number
  from public.system_idea_cycles as cycle
  where cycle.id = new.cycle_id;

  if entry_run_id is null then
    return new;
  end if;

  -- Locking the common game-run row makes opposite boundary inserts observe one another.
  perform 1
  from public.game_runs
  where id = entry_run_id
  for update;

  select
    game_run.rule_set_id,
    channel_rule.channel_type_code,
    game_run.specialty_code
  into run_rule_set_id, run_channel_type_code, run_specialty_code
  from public.game_runs as game_run
  join public.channel_rules as channel_rule
    on channel_rule.id = game_run.channel_rule_id
   and channel_rule.rule_set_id = game_run.rule_set_id
  where game_run.id = entry_run_id;

  select
    rule_idea.rule_set_id,
    rule_idea.system_idea_template_id,
    rule_idea.enabled,
    template.channel_type_code,
    template.specialty_code,
    template.enabled
  into
    idea_rule_set_id,
    idea_template_id,
    is_rule_idea_enabled,
    idea_channel_type_code,
    idea_specialty_code,
    is_template_enabled
  from public.rule_set_system_ideas as rule_idea
  join public.system_idea_templates as template
    on template.id = rule_idea.system_idea_template_id
  where rule_idea.id = new.rule_set_system_idea_id;

  if idea_rule_set_id is null then
    return new;
  end if;

  if not is_rule_idea_enabled then
    raise exception using
      errcode = '23514',
      message = 'System idea is disabled for the cycle rule set';
  end if;

  if not is_template_enabled then
    raise exception using
      errcode = '23514',
      message = 'System idea template is disabled';
  end if;

  if idea_rule_set_id is distinct from run_rule_set_id then
    raise exception using
      errcode = '23514',
      message = 'System idea rule set does not match the game run';
  end if;

  if idea_channel_type_code is distinct from run_channel_type_code then
    raise exception using
      errcode = '23514',
      message = 'System idea channel type does not match the game run';
  end if;

  if idea_specialty_code is distinct from run_specialty_code then
    raise exception using
      errcode = '23514',
      message = 'System idea specialty does not match the game run';
  end if;

  if new.position = 1 and exists (
    select 1
    from public.system_idea_cycles as adjacent_cycle
    join public.system_idea_cycle_entries as adjacent_entry
      on adjacent_entry.cycle_id = adjacent_cycle.id
     and adjacent_entry.position = 50
    join public.rule_set_system_ideas as adjacent_rule_idea
      on adjacent_rule_idea.id = adjacent_entry.rule_set_system_idea_id
    where adjacent_cycle.run_id = entry_run_id
      and adjacent_cycle.cycle_number = entry_cycle_number - 1
      and adjacent_rule_idea.system_idea_template_id = idea_template_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'Adjacent system idea cycles cannot repeat the same boundary template';
  end if;

  if new.position = 50 and exists (
    select 1
    from public.system_idea_cycles as adjacent_cycle
    join public.system_idea_cycle_entries as adjacent_entry
      on adjacent_entry.cycle_id = adjacent_cycle.id
     and adjacent_entry.position = 1
    join public.rule_set_system_ideas as adjacent_rule_idea
      on adjacent_rule_idea.id = adjacent_entry.rule_set_system_idea_id
    where adjacent_cycle.run_id = entry_run_id
      and adjacent_cycle.cycle_number = entry_cycle_number + 1
      and adjacent_rule_idea.system_idea_template_id = idea_template_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'Adjacent system idea cycles cannot repeat the same boundary template';
  end if;

  return new;
end;
$$;

comment on function public.validate_system_idea_cycle_entry() is
  'Validates the entry against its run pool and rejects equal templates across adjacent cycle boundaries.';

create trigger validate_system_idea_cycle_entry
before insert on public.system_idea_cycle_entries
for each row
execute function public.validate_system_idea_cycle_entry();

create function public.protect_system_idea_cycle_entry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'System idea cycle entries cannot be deleted';
  end if;

  if new.cycle_id is distinct from old.cycle_id
    or new.rule_set_system_idea_id is distinct from old.rule_set_system_idea_id
    or new.position is distinct from old.position
  then
    raise exception using
      errcode = '23514',
      message = 'System idea cycle entry order is immutable';
  end if;

  return new;
end;
$$;

create trigger protect_system_idea_cycle_entry
before update or delete on public.system_idea_cycle_entries
for each row
execute function public.protect_system_idea_cycle_entry();

comment on table public.system_idea_cycles is
  'One persisted shuffle cycle per game run. The application validates that a finalized cycle contains all 50 positions in one transaction.';

comment on table public.system_idea_cycle_entries is
  'Immutable positions in a shuffle cycle. Usage is derived later from videos.system_idea_cycle_entry_id, never stored here.';
