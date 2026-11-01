create table public.player_ideas (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null,
  title text not null,
  description text,
  created_week integer not null,
  deleted_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  constraint player_ideas_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint player_ideas_run_id_id_key unique (run_id, id),
  constraint player_ideas_title_length_check
    check (char_length(title) between 1 and 100 and title ~ '[^[:space:]]'),
  constraint player_ideas_created_week_positive_check check (created_week >= 1)
);

create index player_ideas_run_created_week_idx
  on public.player_ideas (run_id, created_week);

create function public.protect_player_idea()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'Player ideas cannot be physically deleted';
  end if;

  if new.id is distinct from old.id
    or new.run_id is distinct from old.run_id
    or new.title is distinct from old.title
    or new.description is distinct from old.description
    or new.created_week is distinct from old.created_week
    or new.created_at is distinct from old.created_at
  then
    raise exception using
      errcode = '23514',
      message = 'Player idea content and creation metadata are immutable';
  end if;

  if old.deleted_at is not null and new.deleted_at is distinct from old.deleted_at then
    raise exception using
      errcode = '23514',
      message = 'Deleted player ideas cannot be restored or deleted again';
  end if;

  return new;
end;
$$;

comment on function public.protect_player_idea() is
  'A trigger is required because CHECK constraints cannot compare old and new rows. It permits only the one-way deleted_at transition from NULL to a timestamp.';

create trigger protect_player_idea
before update or delete on public.player_ideas
for each row
execute function public.protect_player_idea();

create table public.idea_evaluations (
  idea_id uuid primary key,
  score smallint not null,
  evaluation_status text not null,
  model text not null,
  prompt_version text not null,
  evaluated_at timestamptz not null default statement_timestamp(),
  constraint idea_evaluations_idea_id_fkey
    foreign key (idea_id) references public.player_ideas (id) on update restrict on delete restrict,
  constraint idea_evaluations_score_range_check check (score between 0 and 100),
  constraint idea_evaluations_status_check check (evaluation_status in ('completed', 'fallback')),
  constraint idea_evaluations_model_not_blank_check check (model ~ '[^[:space:]]'),
  constraint idea_evaluations_prompt_version_not_blank_check check (prompt_version ~ '[^[:space:]]')
);

create table public.idea_queue_entries (
  idea_id uuid primary key,
  run_id uuid not null,
  position integer not null,
  queued_at timestamptz not null default statement_timestamp(),
  constraint idea_queue_entries_run_idea_fkey
    foreign key (run_id, idea_id)
    references public.player_ideas (run_id, id) on update restrict on delete restrict,
  constraint idea_queue_entries_run_position_key unique (run_id, position),
  constraint idea_queue_entries_position_positive_check check (position >= 1)
);

comment on constraint idea_queue_entries_run_idea_fkey on public.idea_queue_entries is
  'The composite foreign key guarantees that a queue entry belongs to the same game run as its player idea without a synchronization trigger.';

create table public.weekly_actions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null,
  week_number integer not null,
  action_rule_id uuid not null,
  selected_at timestamptz not null default statement_timestamp(),
  locked_at timestamptz,
  constraint weekly_actions_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint weekly_actions_action_rule_id_fkey
    foreign key (action_rule_id) references public.action_rules (id) on update restrict on delete restrict,
  constraint weekly_actions_run_week_key unique (run_id, week_number),
  constraint weekly_actions_week_number_positive_check check (week_number >= 1),
  constraint weekly_actions_lock_time_check check (locked_at is null or locked_at >= selected_at)
);

create index weekly_actions_action_rule_idx
  on public.weekly_actions (action_rule_id);

comment on column public.weekly_actions.action_rule_id is
  'BE-009 will enforce that the action rule belongs to the owning game run rule set.';

create function public.protect_weekly_action()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.locked_at is not null then
    raise exception using
      errcode = '23514',
      message = 'Locked weekly actions cannot be changed or deleted';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.id is distinct from old.id
    or new.run_id is distinct from old.run_id
    or new.week_number is distinct from old.week_number
  then
    raise exception using
      errcode = '23514',
      message = 'Weekly action identity and week are immutable';
  end if;

  return new;
end;
$$;

comment on function public.protect_weekly_action() is
  'A trigger is required because whether UPDATE or DELETE is allowed depends on the previous locked_at value.';

create trigger protect_weekly_action
before update or delete on public.weekly_actions
for each row
execute function public.protect_weekly_action();

create table public.ability_point_grants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null,
  earned_week integer not null,
  available_from_week integer not null,
  amount smallint not null,
  status text not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint ability_point_grants_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint ability_point_grants_run_earned_week_key unique (run_id, earned_week),
  constraint ability_point_grants_week_range_check
    check (earned_week >= 1 and available_from_week >= earned_week),
  constraint ability_point_grants_amount_positive_check check (amount > 0),
  constraint ability_point_grants_status_check
    check (status in ('available', 'held', 'expired', 'consumed'))
);

create table public.ability_allocations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  grant_id uuid not null,
  ability_code text not null,
  points smallint not null,
  allocated_week integer not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint ability_allocations_grant_id_fkey
    foreign key (grant_id) references public.ability_point_grants (id) on update restrict on delete restrict,
  constraint ability_allocations_ability_code_fkey
    foreign key (ability_code) references public.ability_definitions (code) on update restrict on delete restrict,
  constraint ability_allocations_points_positive_check check (points > 0),
  constraint ability_allocations_allocated_week_positive_check check (allocated_week >= 1)
);

create index ability_allocations_grant_idx
  on public.ability_allocations (grant_id);

create index ability_allocations_ability_code_idx
  on public.ability_allocations (ability_code);

comment on table public.ability_allocations is
  'Allocation totals are derived from points. The allocation use case will lock the grant, validate SUM(points) against amount, and update run_abilities in the same transaction.';

create table public.equipment_purchases (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null,
  equipment_type_code text not null,
  from_tier_rule_id uuid,
  to_tier_rule_id uuid not null,
  price_paid bigint not null,
  purchased_week integer not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint equipment_purchases_run_id_fkey
    foreign key (run_id) references public.game_runs (id) on update restrict on delete restrict,
  constraint equipment_purchases_equipment_type_code_fkey
    foreign key (equipment_type_code) references public.equipment_types (code) on update restrict on delete restrict,
  constraint equipment_purchases_from_tier_rule_id_fkey
    foreign key (from_tier_rule_id) references public.equipment_tier_rules (id) on update restrict on delete restrict,
  constraint equipment_purchases_to_tier_rule_id_fkey
    foreign key (to_tier_rule_id) references public.equipment_tier_rules (id) on update restrict on delete restrict,
  constraint equipment_purchases_price_paid_nonnegative_check check (price_paid >= 0),
  constraint equipment_purchases_purchased_week_positive_check check (purchased_week >= 1)
);

create index equipment_purchases_run_type_week_idx
  on public.equipment_purchases (run_id, equipment_type_code, purchased_week);

create index equipment_purchases_from_tier_rule_idx
  on public.equipment_purchases (from_tier_rule_id);

create index equipment_purchases_to_tier_rule_idx
  on public.equipment_purchases (to_tier_rule_id);

comment on table public.equipment_purchases is
  'BE-009 will enforce rule-set and equipment-type agreement across the run and both tier rules. purchaseEquipment will validate first-purchase NULL semantics and reject same/lower tiers while updating cash and run_equipment atomically.';

create function public.reject_immutable_history_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '23514',
    message = format('%s rows are immutable', tg_table_name);
end;
$$;

comment on function public.reject_immutable_history_change() is
  'CHECK constraints cannot prohibit UPDATE or DELETE. This focused guard protects append-only evaluation, allocation, and purchase facts.';

create trigger protect_idea_evaluation_history
before update or delete on public.idea_evaluations
for each row
execute function public.reject_immutable_history_change();

create trigger protect_ability_allocation_history
before update or delete on public.ability_allocations
for each row
execute function public.reject_immutable_history_change();

create trigger protect_equipment_purchase_history
before update or delete on public.equipment_purchases
for each row
execute function public.reject_immutable_history_change();
