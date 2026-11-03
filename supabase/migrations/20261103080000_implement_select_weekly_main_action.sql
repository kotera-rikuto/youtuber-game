create function public.select_weekly_main_action(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_action text,
  p_expected_version integer
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  locked_state public.run_state%rowtype;
  locked_run public.game_runs%rowtype;
  current_action public.weekly_actions%rowtype;
  selected_action_rule public.action_rules%rowtype;
  selected_feature_rule public.feature_rules%rowtype;
  next_state_version integer;
begin
  if p_action is null or p_action not in (
    'part_time_job',
    'rest',
    'collaboration',
    'sponsorship'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_INVALID_ACTION';
  end if;

  if p_run_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_FOUND';
  end if;

  if p_actor_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_FORBIDDEN';
  end if;

  if p_expected_version is null or p_expected_version < 0 then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_STALE_STATE';
  end if;

  select *
  into locked_state
  from public.run_state
  where run_id = p_run_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_FOUND';
  end if;

  select *
  into locked_run
  from public.game_runs
  where id = p_run_id;

  if locked_run.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_COMMIT_FAILED';
  end if;

  if locked_run.user_id is distinct from p_actor_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_FORBIDDEN';
  end if;

  if locked_run.status <> 'playing' then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_PLAYABLE';
  end if;

  if locked_state.state_version is distinct from p_expected_version then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_STALE_STATE';
  end if;

  if exists (
    select 1
    from public.run_conditions as condition
    where condition.run_id = p_run_id
      and condition.recovered_at is null
      and locked_state.current_week between
        condition.unavailable_from_week and condition.unavailable_through_week
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_ACTIVITY_UNAVAILABLE';
  end if;

  select *
  into current_action
  from public.weekly_actions
  where run_id = p_run_id
    and week_number = locked_state.current_week
  for update;

  if current_action.id is not null and current_action.locked_at is not null then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_WEEK_ALREADY_COMMITTED';
  end if;

  select *
  into selected_action_rule
  from public.action_rules
  where rule_set_id = locked_run.rule_set_id
    and action_code = p_action;

  if selected_action_rule.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_COMMIT_FAILED';
  end if;

  if selected_action_rule.required_feature_code is not null then
    select *
    into selected_feature_rule
    from public.feature_rules
    where rule_set_id = locked_run.rule_set_id
      and feature_code = selected_action_rule.required_feature_code;

    if selected_feature_rule.id is null then
      raise exception using
        errcode = 'P0001',
        message = 'SELECT_WEEKLY_MAIN_ACTION_COMMIT_FAILED';
    end if;

    if not exists (
      select 1
      from public.run_feature_unlocks as unlock
      where unlock.run_id = p_run_id
        and unlock.feature_rule_id = selected_feature_rule.id
        and unlock.active_from_week <= locked_state.current_week
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'SELECT_WEEKLY_MAIN_ACTION_FEATURE_LOCKED';
    end if;
  end if;

  if selected_action_rule.cooldown_weeks > 0 and exists (
    select 1
    from public.weekly_actions as previous_action
    join public.action_rules as previous_rule
      on previous_rule.id = previous_action.action_rule_id
    where previous_action.run_id = p_run_id
      and previous_action.week_number < locked_state.current_week
      and previous_action.locked_at is not null
      and previous_rule.rule_set_id = locked_run.rule_set_id
      and previous_rule.action_code = selected_action_rule.action_code
      and previous_action.week_number + selected_action_rule.cooldown_weeks
        > locked_state.current_week
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_ACTION_ON_COOLDOWN';
  end if;

  if current_action.id is null then
    insert into public.weekly_actions (
      run_id,
      week_number,
      action_rule_id
    ) values (
      p_run_id,
      locked_state.current_week,
      selected_action_rule.id
    );
  else
    update public.weekly_actions
    set
      action_rule_id = selected_action_rule.id,
      selected_at = pg_catalog.statement_timestamp()
    where id = current_action.id;
  end if;

  next_state_version := locked_state.state_version + 1;

  update public.run_state
  set
    state_version = next_state_version,
    updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id;

  return pg_catalog.jsonb_build_object(
    'action', selected_action_rule.action_code,
    'weekNumber', locked_state.current_week,
    'stateVersion', next_state_version
  );
exception
  when sqlstate 'P0001' then
    raise;
  when others then
    raise exception using
      errcode = 'P0001',
      message = 'SELECT_WEEKLY_MAIN_ACTION_COMMIT_FAILED';
end;
$$;

comment on function public.select_weekly_main_action(uuid, uuid, text, integer) is
  'Locks run_state and atomically inserts or replaces the current unlocked weekly action for a trusted server caller.';

revoke execute on function public.select_weekly_main_action(uuid, uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.select_weekly_main_action(uuid, uuid, text, integer)
  to service_role;
