create function public.abandon_game(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  run_owner_user_id uuid;
  run_status text;
  current_week_number integer;
  current_state_version integer;
begin
  if p_run_id is null then
    raise exception using errcode = 'P0001', message = 'ABANDON_GAME_RUN_NOT_FOUND';
  end if;

  select user_id into run_owner_user_id
  from public.game_runs
  where id = p_run_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'ABANDON_GAME_RUN_NOT_FOUND';
  end if;
  if p_actor_user_id is null or run_owner_user_id <> p_actor_user_id then
    raise exception using errcode = 'P0001', message = 'ABANDON_GAME_FORBIDDEN';
  end if;

  select current_week, state_version
  into current_week_number, current_state_version
  from public.run_state
  where run_id = p_run_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'ABANDON_GAME_COMMIT_FAILED';
  end if;

  select status into run_status
  from public.game_runs
  where id = p_run_id;

  if run_status = 'abandoned' then
    raise exception using errcode = 'P0001', message = 'ABANDON_GAME_ALREADY_ABANDONED';
  end if;
  if run_status not in ('playing', 'stage_cleared') then
    raise exception using errcode = 'P0001', message = 'ABANDON_GAME_RUN_NOT_ACTIVE';
  end if;
  if p_expected_version is null or p_expected_version < 0
    or current_state_version <> p_expected_version
  then
    raise exception using errcode = 'P0001', message = 'ABANDON_GAME_STALE_STATE';
  end if;

  update public.game_runs
  set status = 'abandoned', completed_at = pg_catalog.statement_timestamp()
  where id = p_run_id;

  insert into public.game_terminations (
    run_id, reason, occurred_week
  ) values (
    p_run_id, 'abandoned', current_week_number
  );

  return pg_catalog.jsonb_build_object('occurredWeek', current_week_number);
end;
$$;

comment on function public.abandon_game(uuid, uuid, integer) is
  'Atomically abandons an owned active game run without deleting any game history.';

create function public.rename_channel(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_channel_name text,
  p_expected_version integer
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  run_owner_user_id uuid;
  run_status text;
  normalized_channel_name text;
  current_state_version integer;
  next_state_version integer;
begin
  normalized_channel_name := pg_catalog.btrim(p_channel_name);
  if normalized_channel_name is null or normalized_channel_name = '' then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_INVALID_CHANNEL_NAME';
  end if;
  if p_run_id is null then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_RUN_NOT_FOUND';
  end if;

  select user_id into run_owner_user_id
  from public.game_runs
  where id = p_run_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_RUN_NOT_FOUND';
  end if;
  if p_actor_user_id is null or run_owner_user_id <> p_actor_user_id then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_FORBIDDEN';
  end if;

  select state_version into current_state_version
  from public.run_state
  where run_id = p_run_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_COMMIT_FAILED';
  end if;

  select status into run_status
  from public.game_runs
  where id = p_run_id;
  if run_status not in ('playing', 'stage_cleared') then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_RUN_NOT_ACTIVE';
  end if;
  if p_expected_version is null or p_expected_version < 0
    or current_state_version <> p_expected_version
  then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_STALE_STATE';
  end if;

  update public.game_runs
  set channel_name = normalized_channel_name
  where id = p_run_id;

  update public.run_state
  set state_version = state_version + 1,
      updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id and state_version = p_expected_version
  returning state_version into next_state_version;

  if not found then
    raise exception using errcode = 'P0001', message = 'RENAME_CHANNEL_COMMIT_FAILED';
  end if;

  return pg_catalog.jsonb_build_object(
    'channelName', normalized_channel_name,
    'nextStateVersion', next_state_version
  );
end;
$$;

comment on function public.rename_channel(uuid, uuid, text, integer) is
  'Atomically renames an owned active game run and advances its optimistic-lock version.';

revoke execute on function public.abandon_game(uuid, uuid, integer),
  public.rename_channel(uuid, uuid, text, integer)
from public, anon, authenticated;
grant execute on function public.abandon_game(uuid, uuid, integer),
  public.rename_channel(uuid, uuid, text, integer)
to service_role;