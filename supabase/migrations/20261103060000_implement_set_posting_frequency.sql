create function public.set_posting_frequency(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_videos_per_week integer,
  p_expected_version integer
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  run_owner_user_id uuid;
  run_status text;
  run_rule_set_id uuid;
  current_week_number integer;
  current_state_version integer;
  selected_posting_frequency_rule_id uuid;
  next_state_version integer;
begin
  if p_videos_per_week is null
    or p_videos_per_week not in (1, 3, 7)
  then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_INVALID_POSTING_FREQUENCY';
  end if;

  if p_run_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_RUN_NOT_FOUND';
  end if;

  select game_run.user_id
  into run_owner_user_id
  from public.game_runs as game_run
  where game_run.id = p_run_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_RUN_NOT_FOUND';
  end if;

  if p_actor_user_id is null or run_owner_user_id <> p_actor_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_FORBIDDEN';
  end if;

  select state.current_week, state.state_version
  into current_week_number, current_state_version
  from public.run_state as state
  where state.run_id = p_run_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_COMMIT_FAILED';
  end if;

  -- Status and rule-set membership are read again after the state lock so a
  -- concurrent state transition cannot validate against a stale snapshot.
  select game_run.status, game_run.rule_set_id
  into run_status, run_rule_set_id
  from public.game_runs as game_run
  where game_run.id = p_run_id;

  if run_status <> 'playing' then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_RUN_NOT_PLAYABLE';
  end if;

  if p_expected_version is null
    or p_expected_version < 0
    or current_state_version <> p_expected_version
  then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_STALE_STATE';
  end if;

  if exists (
    select 1
    from public.run_conditions as condition
    where condition.run_id = p_run_id
      and condition.recovered_at is null
      and current_week_number between
        condition.unavailable_from_week and condition.unavailable_through_week
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_ACTIVITY_UNAVAILABLE';
  end if;

  select frequency_rule.id
  into selected_posting_frequency_rule_id
  from public.posting_frequency_rules as frequency_rule
  where frequency_rule.rule_set_id = run_rule_set_id
    and frequency_rule.videos_per_week = p_videos_per_week;

  if selected_posting_frequency_rule_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_RULE_UNAVAILABLE';
  end if;

  update public.run_state
  set
    posting_frequency_rule_id = selected_posting_frequency_rule_id,
    state_version = state_version + 1,
    updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id
    and state_version = p_expected_version
  returning state_version into next_state_version;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'SET_POSTING_FREQUENCY_COMMIT_FAILED';
  end if;

  return pg_catalog.jsonb_build_object(
    'videosPerWeek', p_videos_per_week,
    'nextStateVersion', next_state_version
  );
end;
$$;

comment on function public.set_posting_frequency(uuid, uuid, integer, integer) is
  'Locks run_state and atomically selects a posting-frequency rule from the game run rule set for a trusted server caller.';

revoke execute on function public.set_posting_frequency(uuid, uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.set_posting_frequency(uuid, uuid, integer, integer)
  to service_role;
