create function public.allocate_ability_points(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_allocations jsonb,
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
  allocation_pair record;
  ability_allocation record;
  locked_grant record;
  allocation_key_count integer;
  allocation_value numeric;
  requested_points integer := 0;
  available_points bigint := 0;
  grant_spent bigint;
  grant_remaining integer;
  ability_remaining integer;
  points_to_use integer;
  remaining_allocations jsonb;
  next_state_version integer;
begin
  if p_actor_user_id is null
    or p_run_id is null
    or p_expected_version is null
    or p_expected_version < 0
    or p_allocations is null
    or pg_catalog.jsonb_typeof(p_allocations) <> 'object'
  then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION';
  end if;

  select pg_catalog.count(*)::integer
  into allocation_key_count
  from pg_catalog.jsonb_object_keys(p_allocations);

  if allocation_key_count <> 6
    or not (p_allocations ? 'planning')
    or not (p_allocations ? 'talking')
    or not (p_allocations ? 'expertise')
    or not (p_allocations ? 'editing')
    or not (p_allocations ? 'visual')
    or not (p_allocations ? 'filming')
  then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION';
  end if;

  for allocation_pair in
    select allocation.key, allocation.value
    from pg_catalog.jsonb_each(p_allocations) as allocation
  loop
    if pg_catalog.jsonb_typeof(allocation_pair.value) <> 'number' then
      raise exception using
        errcode = 'P0001',
        message = 'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION';
    end if;

    allocation_value := (allocation_pair.value #>> '{}')::numeric;
    if allocation_value < 0
      or allocation_value <> pg_catalog.trunc(allocation_value)
    then
      raise exception using
        errcode = 'P0001',
        message = 'ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION';
    end if;
  end loop;

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
      message = 'ALLOCATE_ABILITY_POINTS_RUN_NOT_FOUND';
  end if;

  if run_owner_user_id <> p_actor_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_FORBIDDEN';
  end if;

  if run_status <> 'playing' then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_RUN_NOT_PLAYABLE';
  end if;

  if current_state_version <> p_expected_version then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_STALE_STATE';
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
      message = 'ALLOCATE_ABILITY_POINTS_ACTIVITY_UNAVAILABLE';
  end if;

  perform 1
  from public.run_abilities as ability
  where ability.run_id = p_run_id
    and ability.ability_code in (
      'planning', 'talking', 'expertise', 'editing', 'visual', 'filming'
    )
  order by ability.ability_code
  for update;

  if (
    select pg_catalog.count(*)
    from public.run_abilities as ability
    where ability.run_id = p_run_id
      and ability.ability_code in (
        'planning', 'talking', 'expertise', 'editing', 'visual', 'filming'
      )
  ) <> 6 then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_COMMIT_FAILED';
  end if;

  for ability_allocation in
    select input.ability_code, input.points
    from (values
      (1, 'planning', (p_allocations ->> 'planning')::numeric),
      (2, 'talking', (p_allocations ->> 'talking')::numeric),
      (3, 'expertise', (p_allocations ->> 'expertise')::numeric),
      (4, 'editing', (p_allocations ->> 'editing')::numeric),
      (5, 'visual', (p_allocations ->> 'visual')::numeric),
      (6, 'filming', (p_allocations ->> 'filming')::numeric)
    ) as input(display_order, ability_code, points)
    order by input.display_order
  loop
    if exists (
      select 1
      from public.run_abilities as ability
      where ability.run_id = p_run_id
        and ability.ability_code = ability_allocation.ability_code
        and ability.value + ability_allocation.points > 100
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'ALLOCATE_ABILITY_POINTS_ABILITY_LIMIT_EXCEEDED';
    end if;

    requested_points := requested_points + ability_allocation.points::integer;
  end loop;

  -- Lock in the same order used for consumption so concurrent requests cannot
  -- wait on the same grant set in conflicting orders.
  for locked_grant in
    select point_grant.*
    from public.ability_point_grants as point_grant
    where point_grant.run_id = p_run_id
      and point_grant.status = 'available'
      and point_grant.available_from_week <= current_week_number
    order by
      point_grant.available_from_week,
      point_grant.earned_week,
      point_grant.id
    for update
  loop
    select coalesce(pg_catalog.sum(allocation.points), 0)
    into grant_spent
    from public.ability_allocations as allocation
    where allocation.grant_id = locked_grant.id;

    available_points := available_points
      + greatest(locked_grant.amount - grant_spent, 0);
  end loop;

  if requested_points > available_points then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_INSUFFICIENT_ABILITY_POINTS';
  end if;

  remaining_allocations := p_allocations;

  for locked_grant in
    select point_grant.*
    from public.ability_point_grants as point_grant
    where point_grant.run_id = p_run_id
      and point_grant.status = 'available'
      and point_grant.available_from_week <= current_week_number
    order by
      point_grant.available_from_week,
      point_grant.earned_week,
      point_grant.id
  loop
    select coalesce(pg_catalog.sum(allocation.points), 0)
    into grant_spent
    from public.ability_allocations as allocation
    where allocation.grant_id = locked_grant.id;

    grant_remaining := greatest(
      locked_grant.amount - grant_spent,
      0
    );

    for ability_allocation in
      select input.ability_code
      from (values
        (1, 'planning'),
        (2, 'talking'),
        (3, 'expertise'),
        (4, 'editing'),
        (5, 'visual'),
        (6, 'filming')
      ) as input(display_order, ability_code)
      order by input.display_order
    loop
      exit when grant_remaining = 0;

      ability_remaining := (
        remaining_allocations ->> ability_allocation.ability_code
      )::integer;
      if ability_remaining = 0 then
        continue;
      end if;

      points_to_use := least(ability_remaining, grant_remaining);
      insert into public.ability_allocations (
        grant_id,
        ability_code,
        points,
        allocated_week
      ) values (
        locked_grant.id,
        ability_allocation.ability_code,
        points_to_use,
        current_week_number
      );

      ability_remaining := ability_remaining - points_to_use;
      grant_remaining := grant_remaining - points_to_use;
      remaining_allocations := pg_catalog.jsonb_set(
        remaining_allocations,
        array[ability_allocation.ability_code],
        pg_catalog.to_jsonb(ability_remaining)
      );
    end loop;

    if grant_remaining = 0 then
      update public.ability_point_grants
      set status = 'consumed'
      where id = locked_grant.id;
    end if;
  end loop;

  if exists (
    select 1
    from pg_catalog.jsonb_each_text(remaining_allocations) as allocation
    where allocation.value::integer <> 0
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'ALLOCATE_ABILITY_POINTS_COMMIT_FAILED';
  end if;

  for ability_allocation in
    select input.ability_code, input.points
    from (values
      ('planning', (p_allocations ->> 'planning')::integer),
      ('talking', (p_allocations ->> 'talking')::integer),
      ('expertise', (p_allocations ->> 'expertise')::integer),
      ('editing', (p_allocations ->> 'editing')::integer),
      ('visual', (p_allocations ->> 'visual')::integer),
      ('filming', (p_allocations ->> 'filming')::integer)
    ) as input(ability_code, points)
  loop
    if ability_allocation.points > 0 then
      update public.run_abilities
      set value = value + ability_allocation.points
      where run_id = p_run_id
        and ability_code = ability_allocation.ability_code;
    end if;
  end loop;

  update public.run_state
  set
    state_version = state_version + 1,
    updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id
  returning state_version into next_state_version;

  return next_state_version;
end;
$$;

comment on function public.allocate_ability_points(uuid, uuid, jsonb, integer) is
  'Locks run state and eligible grants, then atomically appends allocations, updates all affected abilities and advances the state version for a trusted server caller.';

revoke execute on function public.allocate_ability_points(uuid, uuid, jsonb, integer)
  from public, anon, authenticated;
grant execute on function public.allocate_ability_points(uuid, uuid, jsonb, integer)
  to service_role;
