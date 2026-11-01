create table public.channel_types (
  code text primary key,
  name text not null unique,
  constraint channel_types_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint channel_types_name_not_blank_check
    check (btrim(name) <> '')
);

create table public.specialty_categories (
  code text primary key,
  name text not null unique,
  display_order smallint not null unique,
  constraint specialty_categories_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint specialty_categories_name_not_blank_check
    check (btrim(name) <> ''),
  constraint specialty_categories_display_order_positive_check
    check (display_order >= 1)
);

create table public.ability_definitions (
  code text primary key,
  name text not null unique,
  display_order smallint not null unique,
  constraint ability_definitions_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint ability_definitions_name_not_blank_check
    check (btrim(name) <> ''),
  constraint ability_definitions_display_order_positive_check
    check (display_order >= 1)
);

create table public.equipment_types (
  code text primary key,
  name text not null unique,
  display_order smallint not null unique,
  constraint equipment_types_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint equipment_types_name_not_blank_check
    check (btrim(name) <> ''),
  constraint equipment_types_display_order_positive_check
    check (display_order >= 1)
);

create table public.action_definitions (
  code text primary key,
  name text not null unique,
  description text not null,
  constraint action_definitions_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint action_definitions_name_not_blank_check
    check (btrim(name) <> ''),
  constraint action_definitions_description_not_blank_check
    check (btrim(description) <> '')
);

create table public.feature_definitions (
  code text primary key,
  name text not null unique,
  constraint feature_definitions_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint feature_definitions_name_not_blank_check
    check (btrim(name) <> '')
);

create table public.event_categories (
  code text primary key,
  name text not null unique,
  constraint event_categories_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint event_categories_name_not_blank_check
    check (btrim(name) <> '')
);

create table public.event_definitions (
  code text primary key,
  category_code text not null,
  name text not null unique,
  constraint event_definitions_code_format_check
    check (code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint event_definitions_name_not_blank_check
    check (btrim(name) <> ''),
  constraint event_definitions_category_code_fkey
    foreign key (category_code)
    references public.event_categories (code)
    on update restrict
    on delete restrict
);

create table public.rule_sets (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  version text not null unique,
  status text not null default 'draft',
  published_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  constraint rule_sets_version_not_blank_check
    check (btrim(version) <> ''),
  constraint rule_sets_version_format_check
    check (version ~ '^[a-zA-Z0-9]+(?:[._-][a-zA-Z0-9]+)*$'),
  constraint rule_sets_status_check
    check (status in ('draft', 'active', 'retired')),
  constraint rule_sets_publication_state_check
    check (
      (status = 'draft' and published_at is null)
      or (status in ('active', 'retired') and published_at is not null)
    ),
  constraint rule_sets_publication_time_check
    check (published_at is null or published_at >= created_at)
);

create unique index rule_sets_single_active_idx
  on public.rule_sets ((status))
  where status = 'active';

comment on table public.rule_sets is
  'Version roots for typed game rules. Balance changes create a new rule set instead of overwriting a published version.';

create function public.protect_rule_set_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' or old.published_at is not null then
      raise exception 'Published rule sets cannot be deleted';
    end if;

    return old;
  end if;

  if old.status = 'draft' and old.published_at is null then
    if new.status = 'retired' then
      raise exception 'Draft rule sets must be activated before they can be retired';
    end if;

    return new;
  end if;

  if new.id is distinct from old.id
    or new.version is distinct from old.version
    or new.published_at is distinct from old.published_at
    or new.created_at is distinct from old.created_at
  then
    raise exception 'Published rule set fields are immutable';
  end if;

  if old.status = 'active' and new.status = 'retired' then
    return new;
  end if;

  if new.status is distinct from old.status then
    raise exception 'Invalid published rule set status transition: % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

comment on function public.protect_rule_set_lifecycle() is
  'Draft rows may be edited, published, or deleted. Published fields are immutable; only active-to-retired status transitions remain valid.';

create trigger protect_rule_set_lifecycle
before update or delete on public.rule_sets
for each row
execute function public.protect_rule_set_lifecycle();
