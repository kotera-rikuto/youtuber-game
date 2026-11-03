alter table public.channel_types
  add column display_order smallint;

update public.channel_types
set display_order = case code
  when 'mainstream' then 1
  when 'specialized' then 2
  when 'controversial' then 3
  when 'idol' then 4
end;

alter table public.channel_types
  alter column display_order set not null,
  add constraint channel_types_display_order_key unique (display_order),
  add constraint channel_types_display_order_positive_check
    check (display_order >= 1);

create function public.commit_start_game(
  p_actor_user_id uuid,
  p_channel_name text,
  p_posting_style text,
  p_specialty_code text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  normalized_channel_name text;
  active_rule_set_id uuid;
  selected_channel_rule_id uuid;
  initial_posting_frequency_rule_id uuid;
  stage_one_goal_rule_id uuid;
  stage_one_duration_weeks integer;
  created_run_id uuid;
  inserted_ability_count integer;
begin
  normalized_channel_name := pg_catalog.btrim(p_channel_name);
  if p_actor_user_id is null
    or normalized_channel_name is null
    or normalized_channel_name = ''
    or p_posting_style is null
  then
    raise exception using
      errcode = 'P0001',
      message = 'START_GAME_VALIDATION_ERROR';
  end if;

  -- The partial unique index remains the final defense, while this lock makes
  -- the check deterministic for concurrent starts by the same auth user.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_actor_user_id::text, 0)
  );

  if exists (
    select 1
    from public.game_runs
    where user_id = p_actor_user_id
      and status in ('playing', 'stage_cleared')
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'START_GAME_ACTIVE_GAME_EXISTS';
  end if;

  select id
  into active_rule_set_id
  from public.rule_sets
  where status = 'active'
    and published_at is not null;

  if active_rule_set_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'START_GAME_RULES_UNAVAILABLE';
  end if;

  select id
  into selected_channel_rule_id
  from public.channel_rules
  where rule_set_id = active_rule_set_id
    and channel_type_code = p_posting_style;

  if selected_channel_rule_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'START_GAME_VALIDATION_ERROR';
  end if;

  if p_posting_style = 'specialized' then
    if p_specialty_code is null or p_specialty_code = '' then
      raise exception using
        errcode = 'P0001',
        message = 'START_GAME_SPECIALTY_REQUIRED';
    end if;

    if not exists (
      select 1
      from public.rule_set_specialties
      where rule_set_id = active_rule_set_id
        and specialty_code = p_specialty_code
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'START_GAME_SPECIALTY_NOT_ALLOWED';
    end if;
  elsif p_specialty_code is not null then
    raise exception using
      errcode = 'P0001',
      message = 'START_GAME_SPECIALTY_NOT_ALLOWED';
  end if;

  select id
  into initial_posting_frequency_rule_id
  from public.posting_frequency_rules
  where rule_set_id = active_rule_set_id
    and videos_per_week = 1;

  select id, duration_weeks
  into stage_one_goal_rule_id, stage_one_duration_weeks
  from public.goal_rules
  where rule_set_id = active_rule_set_id
    and stage_number = 1;

  if initial_posting_frequency_rule_id is null
    or stage_one_goal_rule_id is null
    or stage_one_duration_weeks is null
  then
    raise exception using
      errcode = 'P0001',
      message = 'START_GAME_RULES_UNAVAILABLE';
  end if;

  insert into public.game_runs (
    user_id,
    rule_set_id,
    channel_rule_id,
    specialty_code,
    channel_name
  )
  values (
    p_actor_user_id,
    active_rule_set_id,
    selected_channel_rule_id,
    p_specialty_code,
    normalized_channel_name
  )
  returning id into created_run_id;

  insert into public.run_state (run_id, posting_frequency_rule_id)
  values (created_run_id, initial_posting_frequency_rule_id);

  insert into public.run_abilities (run_id, ability_code, value)
  select created_run_id, code, 10
  from public.ability_definitions;

  get diagnostics inserted_ability_count = row_count;
  if inserted_ability_count <> 6 then
    raise exception using
      errcode = 'P0001',
      message = 'START_GAME_RULES_UNAVAILABLE';
  end if;

  insert into public.run_goals (
    run_id,
    goal_rule_id,
    started_week,
    deadline_week,
    status
  )
  values (
    created_run_id,
    stage_one_goal_rule_id,
    1,
    stage_one_duration_weeks,
    'active'
  );

  return created_run_id;
end;
$$;

comment on function public.commit_start_game(uuid, text, text, text) is
  'Atomically creates a game run and its complete initial state for a trusted server caller.';

revoke execute on function public.commit_start_game(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.commit_start_game(uuid, text, text, text)
  to service_role;
