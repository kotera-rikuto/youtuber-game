-- Cross-table invariants intentionally remain in one additive migration so the
-- guarantees introduced by BE-009 can be reviewed as a single boundary.

alter table public.week_results
  add constraint week_results_action_frequency_shape_check
    check ((weekly_action_id is null) = (posting_frequency_rule_id is null));

alter table public.run_goals
  add constraint run_goals_achieved_before_deadline_check
    check (achieved_week is null or achieved_week <= deadline_week);

create unique index run_conditions_one_active_per_run_idx
  on public.run_conditions (run_id)
  where recovered_at is null;

create function public.assert_rule_set_matches_run(
  target_run_id uuid,
  referenced_rule_set_id uuid,
  reference_name text
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  run_rule_set_id uuid;
begin
  select rule_set_id
  into run_rule_set_id
  from public.game_runs
  where id = target_run_id;

  if run_rule_set_id is not null
    and referenced_rule_set_id is not null
    and referenced_rule_set_id is distinct from run_rule_set_id
  then
    raise exception using
      errcode = '23514',
      message = format('%s rule set does not match the game run', reference_name);
  end if;
end;
$$;

comment on function public.assert_rule_set_matches_run(uuid, uuid, text) is
  'Shared assertion for versioned rule references whose game-run rule set is reached through another table.';

-- A rule row belongs to one version for its entire lifetime. Draft rules remain
-- editable, but re-parenting an existing identifier would invalidate indirect
-- references that intentionally do not duplicate rule_set_id.
create or replace function public.protect_versioned_rule_row()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_rule_set_id uuid;
  new_rule_set_id uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    old_rule_set_id := old.rule_set_id;

    if not exists (
      select 1
      from public.rule_sets
      where id = old_rule_set_id
        and status = 'draft'
        and published_at is null
    ) then
      raise exception 'Rules belonging to published rule sets are immutable';
    end if;
  end if;

  if tg_op = 'UPDATE'
    and tg_table_name <> 'rule_set_system_ideas'
    and new.rule_set_id is distinct from old.rule_set_id
  then
    raise exception using
      errcode = '23514',
      message = 'Versioned rule rows cannot be moved between rule sets';
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    new_rule_set_id := new.rule_set_id;

    if not exists (
      select 1
      from public.rule_sets
      where id = new_rule_set_id
        and status = 'draft'
        and published_at is null
    ) then
      raise exception 'Rules can only be written under draft rule sets';
    end if;

    return new;
  end if;

  return old;
end;
$$;

create function public.validate_run_state_invariants()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  run_rule_set_id uuid;
  frequency_rule_set_id uuid;
  configured_energy_max smallint;
begin
  select game_run.rule_set_id, global_rule.energy_max
  into run_rule_set_id, configured_energy_max
  from public.game_runs as game_run
  left join public.global_rules as global_rule
    on global_rule.rule_set_id = game_run.rule_set_id
  where game_run.id = new.run_id;

  select rule_set_id
  into frequency_rule_set_id
  from public.posting_frequency_rules
  where id = new.posting_frequency_rule_id;

  perform public.assert_rule_set_matches_run(
    new.run_id,
    frequency_rule_set_id,
    'Posting frequency'
  );

  if run_rule_set_id is not null and configured_energy_max is null then
    raise exception using
      errcode = '23514',
      message = 'Game run rule set must contain global rules';
  end if;

  if configured_energy_max is not null and new.energy > configured_energy_max then
    raise exception using
      errcode = '23514',
      message = 'Run energy exceeds the configured maximum';
  end if;

  return new;
end;
$$;

create trigger validate_run_state_invariants
before insert or update on public.run_state
for each row
execute function public.validate_run_state_invariants();

create function public.prevent_energy_max_below_current_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if exists (
      select 1
      from public.game_runs as game_run
      join public.run_state as state on state.run_id = game_run.id
      where game_run.rule_set_id = old.rule_set_id
    ) then
      raise exception using
        errcode = '23514',
        message = 'Global rules referenced by current run state cannot be deleted';
    end if;

    return old;
  end if;

  if new.energy_max < old.energy_max and exists (
    select 1
    from public.game_runs as game_run
    join public.run_state as state on state.run_id = game_run.id
    where game_run.rule_set_id = new.rule_set_id
      and state.energy > new.energy_max
  ) then
    raise exception using
      errcode = '23514',
      message = 'Energy maximum cannot be lowered below an existing run state';
  end if;

  return new;
end;
$$;

create trigger prevent_energy_max_below_current_state
before update of energy_max on public.global_rules
for each row
execute function public.prevent_energy_max_below_current_state();

create trigger prevent_referenced_global_rules_deletion
before delete on public.global_rules
for each row
execute function public.prevent_energy_max_below_current_state();

create function public.validate_run_equipment_rule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  tier_rule_set_id uuid;
  tier_equipment_type_code text;
begin
  select rule_set_id, equipment_type_code
  into tier_rule_set_id, tier_equipment_type_code
  from public.equipment_tier_rules
  where id = new.equipment_tier_rule_id;

  perform public.assert_rule_set_matches_run(new.run_id, tier_rule_set_id, 'Equipment tier');

  if exists (
    select 1 from public.equipment_types where code = new.equipment_type_code
  )
    and tier_equipment_type_code is not null
    and tier_equipment_type_code is distinct from new.equipment_type_code
  then
    raise exception using
      errcode = '23514',
      message = 'Equipment tier type does not match the owned equipment type';
  end if;

  return new;
end;
$$;

create trigger validate_run_equipment_rule
before insert or update on public.run_equipment
for each row
execute function public.validate_run_equipment_rule();

create function public.validate_run_feature_rule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  referenced_rule_set_id uuid;
begin
  select rule_set_id into referenced_rule_set_id
  from public.feature_rules where id = new.feature_rule_id;

  perform public.assert_rule_set_matches_run(new.run_id, referenced_rule_set_id, 'Feature');
  return new;
end;
$$;

create trigger validate_run_feature_rule
before insert on public.run_feature_unlocks
for each row
execute function public.validate_run_feature_rule();

create function public.protect_run_feature_unlock()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'Feature unlocks are permanent';
end;
$$;

create trigger protect_run_feature_unlock
before update or delete on public.run_feature_unlocks
for each row
execute function public.protect_run_feature_unlock();

create function public.validate_run_condition_rule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  referenced_rule_set_id uuid;
begin
  select rule_set_id into referenced_rule_set_id
  from public.health_risk_rules where id = new.health_risk_rule_id;

  perform public.assert_rule_set_matches_run(new.run_id, referenced_rule_set_id, 'Health risk');
  return new;
end;
$$;

create trigger validate_run_condition_rule
before insert on public.run_conditions
for each row
execute function public.validate_run_condition_rule();

create function public.protect_run_condition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'Run conditions cannot be physically deleted';
  end if;

  if new.id is distinct from old.id
    or new.run_id is distinct from old.run_id
    or new.health_risk_rule_id is distinct from old.health_risk_rule_id
    or new.started_week is distinct from old.started_week
    or new.duration_weeks is distinct from old.duration_weeks
    or new.unavailable_from_week is distinct from old.unavailable_from_week
    or new.unavailable_through_week is distinct from old.unavailable_through_week
  then
    raise exception using
      errcode = '23514',
      message = 'Run condition identity and unavailable period are immutable';
  end if;

  if old.recovered_at is not null
    and new.recovered_at is distinct from old.recovered_at
  then
    raise exception using
      errcode = '23514',
      message = 'Recovered conditions cannot be reopened or rewritten';
  end if;

  return new;
end;
$$;

create trigger protect_run_condition
before update or delete on public.run_conditions
for each row
execute function public.protect_run_condition();

create function public.validate_run_goal_rule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  referenced_rule_set_id uuid;
begin
  select rule_set_id into referenced_rule_set_id
  from public.goal_rules where id = new.goal_rule_id;

  perform public.assert_rule_set_matches_run(new.run_id, referenced_rule_set_id, 'Goal');
  return new;
end;
$$;

create trigger validate_run_goal_rule
before insert on public.run_goals
for each row
execute function public.validate_run_goal_rule();

create function public.protect_run_goal()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'active' then
      raise exception using
        errcode = '23514',
        message = 'Terminal goals cannot be deleted';
    end if;
    return old;
  end if;

  if new.id is distinct from old.id
    or new.run_id is distinct from old.run_id
    or new.goal_rule_id is distinct from old.goal_rule_id
    or new.started_week is distinct from old.started_week
    or new.deadline_week is distinct from old.deadline_week
  then
    raise exception using
      errcode = '23514',
      message = 'Goal identity and schedule are immutable';
  end if;

  if old.status <> 'active'
    and (new.status is distinct from old.status
      or new.achieved_week is distinct from old.achieved_week)
  then
    raise exception using
      errcode = '23514',
      message = 'Terminal goals cannot be changed';
  end if;

  return new;
end;
$$;

create trigger protect_run_goal
before update or delete on public.run_goals
for each row
execute function public.protect_run_goal();

create function public.protect_terminal_game_run()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('cleared', 'game_over', 'abandoned')
    and new.status is distinct from old.status
  then
    raise exception using
      errcode = '23514',
      message = 'Terminal game runs cannot change status';
  end if;

  if old.completed_at is not null
    and new.completed_at is distinct from old.completed_at
  then
    raise exception using
      errcode = '23514',
      message = 'Game run completion time is immutable once set';
  end if;

  return new;
end;
$$;

create trigger protect_terminal_game_run
before update on public.game_runs
for each row
execute function public.protect_terminal_game_run();

create function public.validate_weekly_action_rule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  referenced_rule_set_id uuid;
begin
  select rule_set_id into referenced_rule_set_id
  from public.action_rules where id = new.action_rule_id;

  perform public.assert_rule_set_matches_run(new.run_id, referenced_rule_set_id, 'Weekly action');
  return new;
end;
$$;

create trigger validate_weekly_action_rule
before insert or update of action_rule_id on public.weekly_actions
for each row
execute function public.validate_weekly_action_rule();

create function public.protect_ability_point_grant()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'Ability point grants cannot be physically deleted';
  end if;

  if new.id is distinct from old.id
    or new.run_id is distinct from old.run_id
    or new.earned_week is distinct from old.earned_week
    or new.available_from_week is distinct from old.available_from_week
    or new.amount is distinct from old.amount
    or new.created_at is distinct from old.created_at
  then
    raise exception using
      errcode = '23514',
      message = 'Ability point grant identity and amount are immutable';
  end if;

  if old.status in ('expired', 'consumed')
    and new.status is distinct from old.status
  then
    raise exception using
      errcode = '23514',
      message = 'Terminal ability point grant statuses cannot change';
  end if;

  return new;
end;
$$;

create trigger protect_ability_point_grant
before update or delete on public.ability_point_grants
for each row
execute function public.protect_ability_point_grant();

create function public.validate_ability_allocation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  locked_grant public.ability_point_grants%rowtype;
  allocated_points integer;
begin
  select * into locked_grant
  from public.ability_point_grants
  where id = new.grant_id
  for update;

  if not found then return new; end if;

  if locked_grant.status <> 'available' then
    raise exception using
      errcode = '23514',
      message = 'Ability points can only be allocated from available grants';
  end if;

  if new.allocated_week < locked_grant.available_from_week then
    raise exception using
      errcode = '23514',
      message = 'Ability points cannot be allocated before the available week';
  end if;

  select coalesce(sum(points), 0) into allocated_points
  from public.ability_allocations
  where grant_id = new.grant_id;

  if allocated_points + new.points > locked_grant.amount then
    raise exception using
      errcode = '23514',
      message = 'Ability point allocation exceeds the grant amount';
  end if;

  return new;
end;
$$;

create trigger validate_ability_allocation
before insert on public.ability_allocations
for each row
execute function public.validate_ability_allocation();

create function public.validate_equipment_purchase_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  from_rule_set_id uuid;
  from_equipment_type_code text;
  to_rule_set_id uuid;
  to_equipment_type_code text;
begin
  if new.from_tier_rule_id is not null then
    select rule_set_id, equipment_type_code
    into from_rule_set_id, from_equipment_type_code
    from public.equipment_tier_rules
    where id = new.from_tier_rule_id;

    perform public.assert_rule_set_matches_run(new.run_id, from_rule_set_id, 'Previous equipment tier');

    if from_equipment_type_code is not null
      and from_equipment_type_code is distinct from new.equipment_type_code
    then
      raise exception using
        errcode = '23514',
        message = 'Previous equipment tier type does not match the purchase type';
    end if;
  end if;

  select rule_set_id, equipment_type_code
  into to_rule_set_id, to_equipment_type_code
  from public.equipment_tier_rules
  where id = new.to_tier_rule_id;

  perform public.assert_rule_set_matches_run(new.run_id, to_rule_set_id, 'Purchased equipment tier');

  if to_equipment_type_code is not null
    and to_equipment_type_code is distinct from new.equipment_type_code
  then
    raise exception using
      errcode = '23514',
      message = 'Purchased equipment tier type does not match the purchase type';
  end if;

  return new;
end;
$$;

create trigger validate_equipment_purchase_rules
before insert on public.equipment_purchases
for each row
execute function public.validate_equipment_purchase_rules();

create function public.validate_week_result_invariants()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  execution_run_id uuid;
  execution_week integer;
  execution_expected_version integer;
  execution_outcome text;
  run_rule_set_id uuid;
  action_run_id uuid;
  action_week integer;
  action_rule_set_id uuid;
  frequency_rule_set_id uuid;
begin
  select run_id, attempted_week, expected_state_version, outcome
  into execution_run_id, execution_week, execution_expected_version, execution_outcome
  from public.advance_week_executions
  where idempotency_key = new.execution_id;

  if execution_run_id is not null then
    if execution_run_id is distinct from new.run_id then
      raise exception using errcode = '23514', message = 'Week result run does not match its execution';
    end if;
    if execution_week is distinct from new.week_number then
      raise exception using errcode = '23514', message = 'Week result week does not match its execution';
    end if;
    if execution_outcome <> 'week_committed' then
      raise exception using errcode = '23514', message = 'Only committed-week executions can have week results';
    end if;
    if new.state_version_after <= execution_expected_version then
      raise exception using
        errcode = '23514',
        message = 'Week result state version must advance beyond the expected version';
    end if;
  end if;

  select rule_set_id into run_rule_set_id
  from public.game_runs where id = new.run_id;

  if new.weekly_action_id is not null then
    select weekly_action.run_id, weekly_action.week_number, action_rule.rule_set_id
    into action_run_id, action_week, action_rule_set_id
    from public.weekly_actions as weekly_action
    join public.action_rules as action_rule on action_rule.id = weekly_action.action_rule_id
    where weekly_action.id = new.weekly_action_id;

    if action_run_id is not null and (
      action_run_id is distinct from new.run_id
      or action_week is distinct from new.week_number
    ) then
      raise exception using
        errcode = '23514',
        message = 'Week result action must belong to the same run and week';
    end if;

    if action_rule_set_id is not null
      and action_rule_set_id is distinct from run_rule_set_id
    then
      raise exception using
        errcode = '23514',
        message = 'Week result action rule set does not match the game run';
    end if;

    select rule_set_id into frequency_rule_set_id
    from public.posting_frequency_rules
    where id = new.posting_frequency_rule_id;

    if frequency_rule_set_id is not null
      and frequency_rule_set_id is distinct from run_rule_set_id
    then
      raise exception using
        errcode = '23514',
        message = 'Week result posting frequency rule set does not match the game run';
    end if;
  elsif not exists (
    select 1
    from public.run_conditions
    where run_id = new.run_id
      and new.week_number between unavailable_from_week and unavailable_through_week
  ) then
    raise exception using
      errcode = '23514',
      message = 'Action-free week results require a matching unavailable period';
  end if;

  return new;
end;
$$;

create trigger validate_week_result_invariants
before insert on public.week_results
for each row
execute function public.validate_week_result_invariants();

create function public.validate_video_idea_source()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  result_run_id uuid;
  result_is_unavailable boolean;
  idea_run_id uuid;
  idea_deleted_at timestamptz;
begin
  select run_id, weekly_action_id is null
  into result_run_id, result_is_unavailable
  from public.week_results
  where id = new.week_result_id;

  if result_is_unavailable then
    raise exception using
      errcode = '23514',
      message = 'Unavailable week results cannot contain videos';
  end if;

  if new.player_idea_id is not null then
    select run_id, deleted_at into idea_run_id, idea_deleted_at
    from public.player_ideas where id = new.player_idea_id;

    if idea_run_id is not null and idea_run_id is distinct from result_run_id then
      raise exception using
        errcode = '23514',
        message = 'Player idea video must belong to the week result game run';
    end if;
    if idea_deleted_at is not null then
      raise exception using
        errcode = '23514',
        message = 'Deleted player ideas cannot be published as videos';
    end if;
  else
    select cycle.run_id into idea_run_id
    from public.system_idea_cycle_entries as cycle_entry
    join public.system_idea_cycles as cycle on cycle.id = cycle_entry.cycle_id
    where cycle_entry.id = new.system_idea_cycle_entry_id;

    if idea_run_id is not null and idea_run_id is distinct from result_run_id then
      raise exception using
        errcode = '23514',
        message = 'System idea video must belong to the week result game run';
    end if;
  end if;

  return new;
end;
$$;

create trigger validate_video_idea_source
before insert on public.videos
for each row
execute function public.validate_video_idea_source();

create function public.prevent_published_player_idea_deletion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.deleted_at is null
    and new.deleted_at is not null
    and exists (
      select 1 from public.videos where player_idea_id = old.id
    )
  then
    raise exception using
      errcode = '23514',
      message = 'Published player ideas cannot be logically deleted';
  end if;

  return new;
end;
$$;

create trigger prevent_published_player_idea_deletion
before update of deleted_at on public.player_ideas
for each row
execute function public.prevent_published_player_idea_deletion();

create function public.validate_occurred_event_rule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  run_rule_set_id uuid;
  rule_set_id uuid;
  rule_definition_code text;
begin
  if new.event_rule_id is null then return new; end if;

  select game_run.rule_set_id into run_rule_set_id
  from public.week_results as week_result
  join public.game_runs as game_run on game_run.id = week_result.run_id
  where week_result.id = new.week_result_id;

  select event_rule.rule_set_id, event_rule.event_definition_code
  into rule_set_id, rule_definition_code
  from public.event_rules as event_rule
  where event_rule.id = new.event_rule_id;

  if rule_definition_code is not null
    and rule_definition_code is distinct from new.event_definition_code
  then
    raise exception using
      errcode = '23514',
      message = 'Occurred event definition does not match its event rule';
  end if;

  if run_rule_set_id is not null
    and rule_set_id is not null
    and rule_set_id is distinct from run_rule_set_id
  then
    raise exception using
      errcode = '23514',
      message = 'Occurred event rule set does not match the game run';
  end if;

  return new;
end;
$$;

create trigger validate_occurred_event_rule
before insert on public.occurred_events
for each row
execute function public.validate_occurred_event_rule();

create function public.validate_game_termination_reference()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  referenced_run_id uuid;
  referenced_week integer;
  referenced_outcome text;
begin
  if new.reason in ('death', 'flame_ban') then
    select run_id, attempted_week, outcome
    into referenced_run_id, referenced_week, referenced_outcome
    from public.advance_week_executions
    where idempotency_key = new.execution_id;

    if referenced_run_id is not null and referenced_run_id is distinct from new.run_id then
      raise exception using errcode = '23514', message = 'Fatal termination run does not match its execution';
    end if;
    if referenced_week is not null and referenced_week is distinct from new.occurred_week then
      raise exception using errcode = '23514', message = 'Fatal termination week does not match its execution';
    end if;
    if referenced_outcome is not null and referenced_outcome <> 'fatal_game_over' then
      raise exception using errcode = '23514', message = 'Fatal termination requires a fatal-game-over execution';
    end if;
    if exists (select 1 from public.week_results where execution_id = new.execution_id) then
      raise exception using errcode = '23514', message = 'Fatal executions cannot have a week result';
    end if;
  elsif new.reason = 'deadline' then
    select week_result.run_id, week_result.week_number, execution.outcome
    into referenced_run_id, referenced_week, referenced_outcome
    from public.week_results as week_result
    join public.advance_week_executions as execution
      on execution.idempotency_key = week_result.execution_id
    where week_result.id = new.week_result_id;

    if referenced_run_id is not null and referenced_run_id is distinct from new.run_id then
      raise exception using errcode = '23514', message = 'Deadline termination run does not match its week result';
    end if;
    if referenced_week is not null and referenced_week is distinct from new.occurred_week then
      raise exception using errcode = '23514', message = 'Deadline termination week does not match its week result';
    end if;
    if referenced_outcome is not null and referenced_outcome <> 'week_committed' then
      raise exception using errcode = '23514', message = 'Deadline termination requires a committed week result';
    end if;
  end if;

  return new;
end;
$$;

create trigger validate_game_termination_reference
before insert on public.game_terminations
for each row
execute function public.validate_game_termination_reference();

-- The following validators run at transaction completion. The week commit
-- workflow inserts parents before children, so immediate checks would reject a
-- valid atomic write while it is still being assembled.
create function public.validate_execution_completion()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_execution_id uuid;
  execution_outcome text;
  result_count integer;
  fatal_termination_count integer;
begin
  if tg_table_name = 'advance_week_executions' then
    target_execution_id := new.idempotency_key;
  elsif tg_table_name = 'week_results' then
    target_execution_id := new.execution_id;
  elsif new.execution_id is not null then
    target_execution_id := new.execution_id;
  elsif new.week_result_id is not null then
    select execution_id into target_execution_id
    from public.week_results where id = new.week_result_id;
  else
    return new;
  end if;

  select outcome into execution_outcome
  from public.advance_week_executions
  where idempotency_key = target_execution_id;
  if execution_outcome is null then return new; end if;

  select count(*) into result_count
  from public.week_results where execution_id = target_execution_id;
  select count(*) into fatal_termination_count
  from public.game_terminations
  where execution_id = target_execution_id and reason in ('death', 'flame_ban');

  if execution_outcome = 'week_committed'
    and (result_count <> 1 or fatal_termination_count <> 0)
  then
    raise exception using
      errcode = '23514',
      message = 'Committed-week execution must have exactly one week result and no fatal termination';
  end if;

  if execution_outcome = 'fatal_game_over'
    and (result_count <> 0 or fatal_termination_count <> 1)
  then
    raise exception using
      errcode = '23514',
      message = 'Fatal-game-over execution must have exactly one fatal termination and no week result';
  end if;

  return new;
end;
$$;

create constraint trigger validate_execution_completion_from_execution
after insert on public.advance_week_executions
deferrable initially deferred
for each row execute function public.validate_execution_completion();

create constraint trigger validate_execution_completion_from_result
after insert on public.week_results
deferrable initially deferred
for each row execute function public.validate_execution_completion();

create constraint trigger validate_execution_completion_from_termination
after insert on public.game_terminations
deferrable initially deferred
for each row execute function public.validate_execution_completion();

create function public.validate_week_result_children()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_week_result_id uuid;
  frequency_rule_id uuid;
  expected_video_count integer;
  actual_video_count integer;
  calculation_count integer;
begin
  if tg_table_name = 'week_results' then
    target_week_result_id := new.id;
  elsif tg_table_name = 'videos' then
    target_week_result_id := new.week_result_id;
  else
    select week_result_id into target_week_result_id
    from public.videos where id = new.video_id;
  end if;

  select posting_frequency_rule_id into frequency_rule_id
  from public.week_results where id = target_week_result_id;
  if not found then return new; end if;

  select count(*) into actual_video_count
  from public.videos where week_result_id = target_week_result_id;

  if frequency_rule_id is null then
    expected_video_count := 0;
  else
    select videos_per_week into expected_video_count
    from public.posting_frequency_rules where id = frequency_rule_id;
  end if;

  if actual_video_count <> expected_video_count then
    raise exception using
      errcode = '23514',
      message = 'Week result video count does not match the posting frequency';
  end if;

  select count(*) into calculation_count
  from public.videos as video
  join public.video_calculations as calculation on calculation.video_id = video.id
  where video.week_result_id = target_week_result_id;

  if calculation_count <> actual_video_count then
    raise exception using
      errcode = '23514',
      message = 'Every committed video must have one calculation snapshot';
  end if;

  return new;
end;
$$;

create constraint trigger validate_week_result_children_from_result
after insert on public.week_results
deferrable initially deferred
for each row execute function public.validate_week_result_children();

create constraint trigger validate_week_result_children_from_video
after insert on public.videos
deferrable initially deferred
for each row execute function public.validate_week_result_children();

create constraint trigger validate_week_result_children_from_calculation
after insert on public.video_calculations
deferrable initially deferred
for each row execute function public.validate_week_result_children();

create function public.validate_rule_set_system_idea_pools(target_rule_set_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  expected_pool_count integer;
  enabled_idea_count integer;
begin
  if exists (
    with expected_pools as (
      select channel_type_code, specialty_code
      from (values
        ('mainstream'::text, null::text),
        ('controversial'::text, null::text),
        ('idol'::text, null::text)
      ) as fixed_pool(channel_type_code, specialty_code)
      union all
      select 'specialized', specialty_code
      from public.rule_set_specialties
      where rule_set_id = target_rule_set_id
    ),
    enabled_counts as (
      select template.channel_type_code, template.specialty_code, count(*) as idea_count
      from public.rule_set_system_ideas as rule_idea
      join public.system_idea_templates as template
        on template.id = rule_idea.system_idea_template_id
      where rule_idea.rule_set_id = target_rule_set_id
        and rule_idea.enabled
        and template.enabled
      group by template.channel_type_code, template.specialty_code
    )
    select 1
    from expected_pools as expected
    left join enabled_counts as actual
      on actual.channel_type_code = expected.channel_type_code
     and actual.specialty_code is not distinct from expected.specialty_code
    where coalesce(actual.idea_count, 0) <> 50
  ) then
    raise exception 'Every enabled system idea pool must contain exactly fifty ideas';
  end if;

  if exists (
    select 1
    from public.rule_set_system_ideas as rule_idea
    join public.system_idea_templates as template
      on template.id = rule_idea.system_idea_template_id
    where rule_idea.rule_set_id = target_rule_set_id
      and rule_idea.enabled
      and template.enabled
      and not (
        (template.channel_type_code in ('mainstream', 'controversial', 'idol')
          and template.specialty_code is null)
        or (
          template.channel_type_code = 'specialized'
          and exists (
            select 1
            from public.rule_set_specialties as specialty
            where specialty.rule_set_id = target_rule_set_id
              and specialty.specialty_code = template.specialty_code
          )
        )
      )
  ) then
    raise exception 'Enabled system ideas must belong to a publication pool';
  end if;

  select 3 + count(*) into expected_pool_count
  from public.rule_set_specialties
  where rule_set_id = target_rule_set_id;

  select count(*) into enabled_idea_count
  from public.rule_set_system_ideas as rule_idea
  join public.system_idea_templates as template
    on template.id = rule_idea.system_idea_template_id
  where rule_idea.rule_set_id = target_rule_set_id
    and rule_idea.enabled
    and template.enabled;

  if enabled_idea_count <> expected_pool_count * 50 then
    raise exception 'Rule set must contain exactly fifty enabled ideas per system idea pool';
  end if;
end;
$$;

comment on function public.validate_rule_set_system_idea_pools(uuid) is
  'Counts only enabled associations and enabled templates in the publication target, requiring 50 ideas in every pool.';

create or replace function public.validate_rule_set_for_publication(target_rule_set_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  rule_count integer;
begin
  select count(*) into rule_count from public.global_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 1 then raise exception 'Rule set must contain exactly one global rule'; end if;

  select count(*) into rule_count from public.channel_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 4 or exists (
    select 1 from (values ('mainstream'), ('specialized'), ('controversial'), ('idol')) as required(code)
    where not exists (
      select 1 from public.channel_rules where rule_set_id = target_rule_set_id and channel_type_code = required.code
    )
  ) then raise exception 'Rule set must contain all four channel rules'; end if;

  if exists (
    select 1
    from public.channel_rules as channel_rule
    left join public.channel_ability_weights as ability_weight on ability_weight.channel_rule_id = channel_rule.id
    where channel_rule.rule_set_id = target_rule_set_id
    group by channel_rule.id
    having count(ability_weight.id) <> 2 or sum(ability_weight.weight) <> 1
  ) then raise exception 'Each channel rule must contain two ability weights totaling one'; end if;

  select count(*) into rule_count from public.rule_set_specialties where rule_set_id = target_rule_set_id;
  if rule_count <> 10 or exists (
    select 1 from (values
      ('baseball'), ('soccer'), ('gaming'), ('pc_gadgets'), ('science'),
      ('history_culture'), ('occult'), ('nature'), ('food_culture'), ('outdoor_survival')
    ) as required(code)
    where not exists (
      select 1 from public.rule_set_specialties
      where rule_set_id = target_rule_set_id and specialty_code = required.code
    )
  ) then raise exception 'Rule set must enable all ten initial specialties'; end if;

  select count(*) into rule_count from public.posting_frequency_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 3 or exists (
    select 1 from (values (1), (3), (7)) as required(videos)
    where not exists (
      select 1 from public.posting_frequency_rules where rule_set_id = target_rule_set_id and videos_per_week = required.videos
    )
  ) then raise exception 'Rule set must contain posting frequencies 1, 3, and 7'; end if;

  select count(*) into rule_count from public.idea_score_band_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 5 or exists (
    select 1 from pg_catalog.generate_series(0, 100) as score(value)
    where not exists (
      select 1 from public.idea_score_band_rules
      where rule_set_id = target_rule_set_id and score.value between min_score and max_score
    )
  ) then raise exception 'Idea score bands must cover every score from 0 through 100'; end if;

  select count(*) into rule_count from public.equipment_tier_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 12 or exists (
    select 1
    from (values ('camera'), ('microphone'), ('editing_pc')) as equipment(code)
    cross join (values ('none'), ('beginner'), ('intermediate'), ('advanced')) as required_tier(tier)
    where not exists (
      select 1 from public.equipment_tier_rules
      where rule_set_id = target_rule_set_id
        and equipment_type_code = equipment.code
        and equipment_tier_rules.tier = required_tier.tier
    )
  ) then raise exception 'Rule set must contain all twelve equipment tiers'; end if;

  select count(*) into rule_count from public.action_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 4 or exists (
    select 1 from (values ('part_time_job'), ('rest'), ('collaboration'), ('sponsorship')) as required(code)
    where not exists (
      select 1 from public.action_rules where rule_set_id = target_rule_set_id and action_code = required.code
    )
  ) then raise exception 'Rule set must contain all four action rules'; end if;

  select count(*) into rule_count from public.sponsorship_reward_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 6 or (
    select min(min_subscribers) <> 100000 or count(*) filter (where max_subscribers is null) <> 1
    from public.sponsorship_reward_rules where rule_set_id = target_rule_set_id
  ) or exists (
    select 1
    from (
      select min_subscribers, max_subscribers,
        lead(min_subscribers) over (order by min_subscribers) as next_min_subscribers
      from public.sponsorship_reward_rules where rule_set_id = target_rule_set_id
    ) as reward_band
    where (next_min_subscribers is null) <> (max_subscribers is null)
      or (next_min_subscribers is not null and next_min_subscribers <> max_subscribers + 1)
  ) then raise exception 'Sponsorship reward bands must form the complete configured ladder'; end if;

  select count(*) into rule_count from public.feature_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 3 or exists (
    select 1 from (values ('ad_revenue'), ('collaboration'), ('sponsorship')) as required(code)
    where not exists (
      select 1 from public.feature_rules where rule_set_id = target_rule_set_id and feature_code = required.code
    )
  ) then raise exception 'Rule set must contain all three feature rules'; end if;

  select count(*) into rule_count from public.goal_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 5 or exists (
    select 1 from pg_catalog.generate_series(1, 5) as stage(value)
    where not exists (
      select 1 from public.goal_rules where rule_set_id = target_rule_set_id and stage_number = stage.value
    )
  ) or (select count(*) from public.goal_rules where rule_set_id = target_rule_set_id and is_final) <> 1
    or not exists (
      select 1 from public.goal_rules where rule_set_id = target_rule_set_id and stage_number = 5 and is_final
    )
  then raise exception 'Rule set must contain stages 1 through 5 with stage 5 final'; end if;

  select count(*) into rule_count from public.event_category_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 2 or exists (
    select 1 from (values ('good'), ('bad')) as required(code)
    where not exists (
      select 1 from public.event_category_rules
      where rule_set_id = target_rule_set_id
        and category_code = required.code
        and weekly_probability = 0.05
    )
  ) or (
    select sum(weekly_probability)
    from public.event_category_rules
    where rule_set_id = target_rule_set_id
  ) <> 0.10
  then raise exception 'Rule set must contain good and bad event categories at five percent each'; end if;

  select count(*) into rule_count from public.event_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 6 or exists (
    select 1
    from public.event_definitions as definition
    where definition.category_code in ('good', 'bad')
      and not exists (
        select 1 from public.event_rules
        where rule_set_id = target_rule_set_id and event_definition_code = definition.code
      )
  ) or exists (
    select 1
    from public.event_rules
    where rule_set_id = target_rule_set_id
    group by category_code
    having count(*) <> 3
      or min(selection_weight) <> max(selection_weight)
      or min(selection_weight) <= 0
  ) then raise exception 'Rule set must contain three equally weighted events in each random category'; end if;

  select count(*) into rule_count from public.health_risk_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 4 or exists (
    select 1 from pg_catalog.generate_series(1, 100) as energy(value)
    where not exists (
      select 1 from public.health_risk_rules
      where rule_set_id = target_rule_set_id and energy.value between min_energy and max_energy
    )
  ) then raise exception 'Health risk bands must cover every energy value from 1 through 100'; end if;

  perform public.validate_rule_set_system_idea_pools(target_rule_set_id);
end;
$$;

comment on function public.validate_rule_set_for_publication(uuid) is
  'Validates all versioned rule families, fixed initial probabilities, and exactly 50 enabled ideas in every publication pool.';
