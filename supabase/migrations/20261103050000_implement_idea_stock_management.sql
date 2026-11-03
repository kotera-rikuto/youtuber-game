create function public.delete_idea(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_idea_id uuid,
  p_expected_version integer
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  run_owner_user_id uuid;
  run_status text;
  current_week_number integer;
  current_state_version integer;
  idea_run_id uuid;
  idea_deleted_at timestamptz;
  is_idea_posted boolean;
  queue_position_offset integer;
  next_state_version integer;
begin
  select
    game_run.user_id,
    game_run.status,
    state.current_week,
    state.state_version
  into
    run_owner_user_id,
    run_status,
    current_week_number,
    current_state_version
  from public.run_state as state
  join public.game_runs as game_run on game_run.id = state.run_id
  where state.run_id = p_run_id
  for update of state;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_RUN_NOT_FOUND';
  end if;

  if run_owner_user_id is distinct from p_actor_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_FORBIDDEN';
  end if;

  if run_status <> 'playing' then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_RUN_NOT_PLAYABLE';
  end if;

  if p_expected_version is null
    or p_expected_version < 0
    or current_state_version <> p_expected_version
  then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_STALE_STATE';
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
      message = 'DELETE_IDEA_ACTIVITY_UNAVAILABLE';
  end if;

  select
    idea.run_id,
    idea.deleted_at,
    exists (
      select 1
      from public.videos as video
      where video.player_idea_id = idea.id
    )
  into idea_run_id, idea_deleted_at, is_idea_posted
  from public.player_ideas as idea
  where idea.id = p_idea_id;

  if not found or idea_run_id is distinct from p_run_id then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_IDEA_NOT_FOUND';
  end if;

  if idea_deleted_at is not null then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_IDEA_ALREADY_DELETED';
  end if;

  if is_idea_posted then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_IDEA_ALREADY_POSTED';
  end if;

  perform queue_entry.idea_id
  from public.idea_queue_entries as queue_entry
  where queue_entry.run_id = p_run_id
  order by queue_entry.position
  for update;

  if not exists (
    select 1
    from public.idea_queue_entries as queue_entry
    where queue_entry.run_id = p_run_id
      and queue_entry.idea_id = p_idea_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'DELETE_IDEA_COMMIT_FAILED';
  end if;

  update public.player_ideas
  set deleted_at = pg_catalog.statement_timestamp()
  where id = p_idea_id;

  delete from public.idea_queue_entries
  where run_id = p_run_id
    and idea_id = p_idea_id;

  select coalesce(pg_catalog.max(queue_entry.position), 0) + 1
  into queue_position_offset
  from public.idea_queue_entries as queue_entry
  where queue_entry.run_id = p_run_id;

  update public.idea_queue_entries
  set position = position + queue_position_offset
  where run_id = p_run_id;

  with compacted_queue as (
    select
      queue_entry.idea_id,
      row_number() over (order by queue_entry.position)::integer as position
    from public.idea_queue_entries as queue_entry
    where queue_entry.run_id = p_run_id
  )
  update public.idea_queue_entries as queue_entry
  set position = compacted_queue.position
  from compacted_queue
  where queue_entry.idea_id = compacted_queue.idea_id;

  update public.run_state
  set
    state_version = state_version + 1,
    updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id
  returning state_version into next_state_version;

  return next_state_version;
end;
$$;

comment on function public.delete_idea(uuid, uuid, uuid, integer) is
  'Locks run_state and atomically soft-deletes one pending player idea, removes its queue entry, and compacts the queue for a trusted server caller.';

revoke execute on function public.delete_idea(uuid, uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.delete_idea(uuid, uuid, uuid, integer)
  to service_role;

create function public.reorder_idea_stock(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_ordered_idea_ids uuid[],
  p_expected_version integer
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  run_owner_user_id uuid;
  run_status text;
  current_week_number integer;
  current_state_version integer;
  pending_idea_count integer;
  queue_position_offset integer;
  updated_queue_count integer;
  next_state_version integer;
begin
  select
    game_run.user_id,
    game_run.status,
    state.current_week,
    state.state_version
  into
    run_owner_user_id,
    run_status,
    current_week_number,
    current_state_version
  from public.run_state as state
  join public.game_runs as game_run on game_run.id = state.run_id
  where state.run_id = p_run_id
  for update of state;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_RUN_NOT_FOUND';
  end if;

  if run_owner_user_id is distinct from p_actor_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_FORBIDDEN';
  end if;

  if run_status <> 'playing' then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_RUN_NOT_PLAYABLE';
  end if;

  if p_expected_version is null
    or p_expected_version < 0
    or current_state_version <> p_expected_version
  then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_STALE_STATE';
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
      message = 'REORDER_IDEA_STOCK_ACTIVITY_UNAVAILABLE';
  end if;

  if p_ordered_idea_ids is null
    or pg_catalog.array_position(p_ordered_idea_ids, null) is not null
    or pg_catalog.cardinality(p_ordered_idea_ids) <> (
      select pg_catalog.count(distinct ordered_idea.idea_id)
      from pg_catalog.unnest(p_ordered_idea_ids) as ordered_idea(idea_id)
    )
  then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER';
  end if;

  perform queue_entry.idea_id
  from public.idea_queue_entries as queue_entry
  where queue_entry.run_id = p_run_id
  order by queue_entry.position
  for update;

  select pg_catalog.count(*)::integer
  into pending_idea_count
  from public.idea_queue_entries as queue_entry
  join public.player_ideas as idea
    on idea.run_id = queue_entry.run_id
   and idea.id = queue_entry.idea_id
  where queue_entry.run_id = p_run_id
    and idea.deleted_at is null
    and not exists (
      select 1
      from public.videos as video
      where video.player_idea_id = idea.id
    );

  if pending_idea_count <> (
      select pg_catalog.count(*)::integer
      from public.idea_queue_entries as queue_entry
      where queue_entry.run_id = p_run_id
    )
  then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_COMMIT_FAILED';
  end if;

  if pg_catalog.cardinality(p_ordered_idea_ids) <> pending_idea_count
    or exists (
      select 1
      from pg_catalog.unnest(p_ordered_idea_ids) as ordered_idea(idea_id)
      where not exists (
        select 1
        from public.idea_queue_entries as queue_entry
        join public.player_ideas as idea
          on idea.run_id = queue_entry.run_id
         and idea.id = queue_entry.idea_id
        where queue_entry.run_id = p_run_id
          and queue_entry.idea_id = ordered_idea.idea_id
          and idea.deleted_at is null
          and not exists (
            select 1
            from public.videos as video
            where video.player_idea_id = idea.id
          )
      )
    )
  then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_INVALID_IDEA_ORDER';
  end if;

  select coalesce(pg_catalog.max(queue_entry.position), 0) + 1
  into queue_position_offset
  from public.idea_queue_entries as queue_entry
  where queue_entry.run_id = p_run_id;

  update public.idea_queue_entries
  set position = position + queue_position_offset
  where run_id = p_run_id;

  update public.idea_queue_entries as queue_entry
  set position = ordered_idea.position::integer
  from pg_catalog.unnest(p_ordered_idea_ids) with ordinality
    as ordered_idea(idea_id, position)
  where queue_entry.run_id = p_run_id
    and queue_entry.idea_id = ordered_idea.idea_id;

  get diagnostics updated_queue_count = row_count;
  if updated_queue_count <> pending_idea_count then
    raise exception using
      errcode = 'P0001',
      message = 'REORDER_IDEA_STOCK_COMMIT_FAILED';
  end if;

  update public.run_state
  set
    state_version = state_version + 1,
    updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id
  returning state_version into next_state_version;

  return next_state_version;
end;
$$;

comment on function public.reorder_idea_stock(uuid, uuid, uuid[], integer) is
  'Locks run_state, validates the complete pending player-idea set, and atomically replaces queue positions for a trusted server caller.';

revoke execute on function public.reorder_idea_stock(uuid, uuid, uuid[], integer)
  from public, anon, authenticated;
grant execute on function public.reorder_idea_stock(uuid, uuid, uuid[], integer)
  to service_role;
