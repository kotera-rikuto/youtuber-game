create table public.profiles (
  user_id uuid primary key,
  display_name text,
  created_at timestamptz not null default statement_timestamp(),
  constraint profiles_user_id_fkey
    foreign key (user_id) references auth.users (id) on update restrict on delete restrict
);

comment on table public.profiles is
  'Optional application profiles keyed by the Supabase Auth user id.';

create table public.game_runs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  user_id uuid not null,
  rule_set_id uuid not null,
  channel_rule_id uuid not null,
  specialty_code text,
  channel_name text not null,
  status text not null default 'playing',
  created_at timestamptz not null default statement_timestamp(),
  completed_at timestamptz,
  constraint game_runs_user_id_fkey
    foreign key (user_id) references auth.users (id) on update restrict on delete restrict,
  constraint game_runs_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint game_runs_rule_set_channel_rule_fkey
    foreign key (rule_set_id, channel_rule_id)
    references public.channel_rules (rule_set_id, id) on update restrict on delete restrict,
  constraint game_runs_rule_set_specialty_fkey
    foreign key (rule_set_id, specialty_code)
    references public.rule_set_specialties (rule_set_id, specialty_code) on update restrict on delete restrict,
  constraint game_runs_channel_name_not_blank_check
    check (btrim(channel_name) <> ''),
  constraint game_runs_status_check
    check (status in ('playing', 'stage_cleared', 'cleared', 'game_over', 'abandoned')),
  constraint game_runs_completion_state_check
    check (
      (status in ('playing', 'stage_cleared') and completed_at is null)
      or (status in ('cleared', 'game_over', 'abandoned') and completed_at is not null)
    ),
  constraint game_runs_completion_time_check
    check (completed_at is null or completed_at >= created_at)
);

create unique index game_runs_one_active_per_user_idx
  on public.game_runs (user_id)
  where status in ('playing', 'stage_cleared');

create index game_runs_user_status_idx
  on public.game_runs (user_id, status);

create index game_runs_rule_set_specialty_idx
  on public.game_runs (rule_set_id, specialty_code);

create function public.validate_game_run_specialty()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  selected_channel_type text;
begin
  select channel_type_code
  into selected_channel_type
  from public.channel_rules
  where rule_set_id = new.rule_set_id
    and id = new.channel_rule_id;

  if selected_channel_type = 'specialized' and new.specialty_code is null then
    raise exception using
      errcode = '23514',
      message = 'Specialized game runs require a specialty';
  end if;

  if selected_channel_type is distinct from 'specialized' and new.specialty_code is not null then
    raise exception using
      errcode = '23514',
      message = 'Only specialized game runs may have a specialty';
  end if;

  return new;
end;
$$;

comment on function public.validate_game_run_specialty() is
  'Enforces the channel-type-dependent specialty rule; the composite foreign key separately validates the selected specialty version.';

create trigger validate_game_run_specialty
before insert or update of rule_set_id, channel_rule_id, specialty_code on public.game_runs
for each row
execute function public.validate_game_run_specialty();

create function public.protect_game_run_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id
    or new.rule_set_id is distinct from old.rule_set_id
    or new.channel_rule_id is distinct from old.channel_rule_id
    or new.specialty_code is distinct from old.specialty_code
  then
    raise exception using
      errcode = '23514',
      message = 'Game run ownership and starting selections are immutable';
  end if;

  return new;
end;
$$;

comment on function public.protect_game_run_identity() is
  'Prevents ownership, rule version, channel type, and specialty reassignment after a game starts.';

create trigger protect_game_run_identity
before update on public.game_runs
for each row
execute function public.protect_game_run_identity();

create table public.run_state (
  run_id uuid primary key,
  current_week integer not null default 1,
  posting_frequency_rule_id uuid not null,
  cash bigint not null default 100000,
  energy smallint not null default 100,
  subscribers bigint not null default 0,
  cumulative_views bigint not null default 0,
  flame_count smallint not null default 0,
  state_version integer not null default 0,
  updated_at timestamptz not null default statement_timestamp(),
  constraint run_state_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint run_state_posting_frequency_rule_id_fkey
    foreign key (posting_frequency_rule_id)
    references public.posting_frequency_rules (id) on update restrict on delete restrict,
  constraint run_state_current_week_positive_check check (current_week >= 1),
  constraint run_state_cash_nonnegative_check check (cash >= 0),
  constraint run_state_energy_nonnegative_check check (energy >= 0),
  constraint run_state_subscribers_nonnegative_check check (subscribers >= 0),
  constraint run_state_cumulative_views_nonnegative_check check (cumulative_views >= 0),
  constraint run_state_flame_count_nonnegative_check check (flame_count >= 0),
  constraint run_state_state_version_nonnegative_check check (state_version >= 0)
);

create index run_state_posting_frequency_rule_idx
  on public.run_state (posting_frequency_rule_id);

comment on column public.run_state.state_version is
  'Optimistic-lock revision. Zero means that no state-changing use case has completed yet.';

comment on column public.run_state.energy is
  'BE-009 will enforce the owning rule set global_rules.energy_max across tables.';

comment on column public.run_state.posting_frequency_rule_id is
  'BE-009 will enforce that this rule belongs to the game run rule set.';

create table public.run_abilities (
  run_id uuid not null,
  ability_code text not null,
  value smallint not null,
  constraint run_abilities_pkey primary key (run_id, ability_code),
  constraint run_abilities_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint run_abilities_ability_code_fkey
    foreign key (ability_code) references public.ability_definitions (code) on update restrict on delete restrict,
  constraint run_abilities_value_range_check check (value between 0 and 100)
);

create index run_abilities_ability_code_idx
  on public.run_abilities (ability_code);

comment on table public.run_abilities is
  'Current ability values stored one row per ability so all rule and allocation tables share ability_code.';

create table public.run_equipment (
  run_id uuid not null,
  equipment_type_code text not null,
  equipment_tier_rule_id uuid not null,
  acquired_week integer not null,
  constraint run_equipment_pkey primary key (run_id, equipment_type_code),
  constraint run_equipment_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint run_equipment_equipment_type_code_fkey
    foreign key (equipment_type_code) references public.equipment_types (code) on update restrict on delete restrict,
  constraint run_equipment_equipment_tier_rule_id_fkey
    foreign key (equipment_tier_rule_id)
    references public.equipment_tier_rules (id) on update restrict on delete restrict,
  constraint run_equipment_acquired_week_nonnegative_check check (acquired_week >= 0)
);

create index run_equipment_tier_rule_idx
  on public.run_equipment (equipment_tier_rule_id);

comment on column public.run_equipment.equipment_tier_rule_id is
  'BE-009 will enforce both the owning rule set and equipment type against the referenced tier rule.';

create table public.run_feature_unlocks (
  run_id uuid not null,
  feature_rule_id uuid not null,
  unlocked_week integer not null,
  active_from_week integer not null,
  constraint run_feature_unlocks_pkey primary key (run_id, feature_rule_id),
  constraint run_feature_unlocks_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint run_feature_unlocks_feature_rule_id_fkey
    foreign key (feature_rule_id) references public.feature_rules (id) on update restrict on delete restrict,
  constraint run_feature_unlocks_week_range_check
    check (unlocked_week >= 1 and active_from_week >= unlocked_week)
);

create index run_feature_unlocks_feature_rule_idx
  on public.run_feature_unlocks (feature_rule_id);

comment on column public.run_feature_unlocks.feature_rule_id is
  'BE-009 will enforce that this rule belongs to the game run rule set and will protect persistent unlock history from deletion.';

create table public.run_conditions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null,
  health_risk_rule_id uuid not null,
  started_week integer not null,
  duration_weeks smallint not null,
  unavailable_from_week integer not null,
  unavailable_through_week integer not null,
  recovered_at timestamptz,
  constraint run_conditions_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint run_conditions_health_risk_rule_id_fkey
    foreign key (health_risk_rule_id) references public.health_risk_rules (id) on update restrict on delete restrict,
  constraint run_conditions_started_week_positive_check check (started_week >= 1),
  constraint run_conditions_duration_weeks_positive_check check (duration_weeks > 0),
  constraint run_conditions_unavailable_period_check
    check (
      unavailable_from_week = started_week + 1
      and unavailable_through_week = unavailable_from_week + duration_weeks - 1
      and unavailable_from_week <= unavailable_through_week
    )
);

create index run_conditions_active_period_idx
  on public.run_conditions (run_id, unavailable_through_week)
  where recovered_at is null;

create index run_conditions_health_risk_rule_idx
  on public.run_conditions (health_risk_rule_id);

comment on column public.run_conditions.health_risk_rule_id is
  'BE-009 will enforce that this rule belongs to the game run rule set.';

create table public.run_goals (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null,
  goal_rule_id uuid not null,
  started_week integer not null,
  deadline_week integer not null,
  achieved_week integer,
  status text not null,
  constraint run_goals_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint run_goals_goal_rule_id_fkey
    foreign key (goal_rule_id) references public.goal_rules (id) on update restrict on delete restrict,
  constraint run_goals_run_goal_rule_key unique (run_id, goal_rule_id),
  constraint run_goals_status_check check (status in ('active', 'achieved', 'failed')),
  constraint run_goals_week_range_check
    check (
      started_week >= 1
      and deadline_week >= started_week
      and (achieved_week is null or achieved_week >= started_week)
    ),
  constraint run_goals_achievement_state_check
    check (
      (status = 'achieved' and achieved_week is not null)
      or (status in ('active', 'failed') and achieved_week is null)
    )
);

create unique index run_goals_one_active_per_run_idx
  on public.run_goals (run_id)
  where status = 'active';

create index run_goals_goal_rule_idx
  on public.run_goals (goal_rule_id);

comment on column public.run_goals.goal_rule_id is
  'BE-009 will enforce that this rule belongs to the game run rule set.';
