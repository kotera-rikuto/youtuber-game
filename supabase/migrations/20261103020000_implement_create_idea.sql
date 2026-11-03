create function public.commit_create_idea(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_title text,
  p_description text default null,
  p_expected_version integer default null,
  p_score smallint default null,
  p_evaluation_status text default null,
  p_model text default null,
  p_prompt_version text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  normalized_title text;
  run_owner_user_id uuid;
  run_status text;
  run_rule_set_id uuid;
  current_week_number integer;
  current_state_version integer;
  ideas_per_week_limit smallint;
  idea_stock_limit smallint;
  ideas_created_this_week bigint;
  pending_idea_count bigint;
  next_queue_position integer;
  created_idea_id uuid;
begin
  normalized_title := pg_catalog.regexp_replace(
    p_title,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );

  if p_actor_user_id is null
    or p_run_id is null
    or p_expected_version is null
    or p_expected_version < 0
    or normalized_title is null
    or pg_catalog.char_length(normalized_title) not between 1 and 100
    or normalized_title !~ '[^[:space:]]'
    or p_score is null
    or p_score not between 0 and 100
    or p_evaluation_status is null
    or p_evaluation_status not in ('completed', 'fallback')
    or (p_evaluation_status = 'fallback' and p_score <> 60)
    or p_model is null
    or p_model !~ '[^[:space:]]'
    or p_prompt_version is null
    or p_prompt_version !~ '[^[:space:]]'
  then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_VALIDATION_ERROR';
  end if;

  select
    game_run.user_id,
    game_run.status,
    game_run.rule_set_id,
    state.current_week,
    state.state_version
  into
    run_owner_user_id,
    run_status,
    run_rule_set_id,
    current_week_number,
    current_state_version
  from public.run_state as state
  join public.game_runs as game_run on game_run.id = state.run_id
  where state.run_id = p_run_id
  for update of state;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_RUN_NOT_FOUND';
  end if;

  if run_owner_user_id <> p_actor_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_FORBIDDEN';
  end if;

  if run_status <> 'playing' then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_RUN_NOT_PLAYABLE';
  end if;

  if current_state_version <> p_expected_version then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_STALE_STATE';
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
      message = 'CREATE_IDEA_ACTIVITY_UNAVAILABLE';
  end if;

  select global_rule.ideas_per_week, global_rule.idea_stock_max
  into ideas_per_week_limit, idea_stock_limit
  from public.global_rules as global_rule
  where global_rule.rule_set_id = run_rule_set_id;

  if ideas_per_week_limit is null or idea_stock_limit is null then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_RULES_UNAVAILABLE';
  end if;

  select pg_catalog.count(*)
  into ideas_created_this_week
  from public.player_ideas as idea
  where idea.run_id = p_run_id
    and idea.created_week = current_week_number;

  if ideas_created_this_week >= ideas_per_week_limit then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_WEEKLY_LIMIT';
  end if;

  select pg_catalog.count(*)
  into pending_idea_count
  from public.player_ideas as idea
  where idea.run_id = p_run_id
    and idea.deleted_at is null
    and not exists (
      select 1
      from public.videos as video
      where video.player_idea_id = idea.id
    );

  if pending_idea_count >= idea_stock_limit then
    raise exception using
      errcode = 'P0001',
      message = 'CREATE_IDEA_STOCK_FULL';
  end if;

  select coalesce(pg_catalog.max(queue_entry.position), 0) + 1
  into next_queue_position
  from public.idea_queue_entries as queue_entry
  where queue_entry.run_id = p_run_id;

  insert into public.player_ideas (
    run_id,
    title,
    description,
    created_week
  )
  values (
    p_run_id,
    normalized_title,
    p_description,
    current_week_number
  )
  returning id into created_idea_id;

  insert into public.idea_evaluations (
    idea_id,
    score,
    evaluation_status,
    model,
    prompt_version
  )
  values (
    created_idea_id,
    p_score,
    p_evaluation_status,
    p_model,
    p_prompt_version
  );

  insert into public.idea_queue_entries (idea_id, run_id, position)
  values (created_idea_id, p_run_id, next_queue_position);

  update public.run_state
  set
    state_version = state_version + 1,
    updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id;

  return created_idea_id;
end;
$$;

comment on function public.commit_create_idea(
  uuid, uuid, text, text, integer, smallint, text, text, text
) is
  'Locks run_state and atomically creates a player idea, its private evaluation, and its queue entry for a trusted server caller.';

revoke execute on function public.commit_create_idea(
  uuid, uuid, text, text, integer, smallint, text, text, text
)
  from public, anon, authenticated;
grant execute on function public.commit_create_idea(
  uuid, uuid, text, text, integer, smallint, text, text, text
)
  to service_role;
