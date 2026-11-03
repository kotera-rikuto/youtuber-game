create function public.commit_system_idea_cycle(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_required_count integer,
  p_ordered_rule_set_system_idea_ids uuid[]
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  run_rule_set_id uuid;
  run_channel_type_code text;
  run_specialty_code text;
  run_current_week integer;
  eligible_pool_count integer;
  eligible_template_count integer;
  supplied_association_count integer;
  existing_cycle_count integer;
  available_entry_count integer;
  latest_cycle_id uuid;
  latest_cycle_number integer;
  previous_last_template_id uuid;
  proposed_first_template_id uuid;
  created_cycle_id uuid;
begin
  if p_actor_user_id is null
    or p_run_id is null
    or p_required_count not between 1 and 7
    or p_ordered_rule_set_system_idea_ids is null
    or pg_catalog.cardinality(p_ordered_rule_set_system_idea_ids) <> 50
    or pg_catalog.array_position(p_ordered_rule_set_system_idea_ids, null) is not null
  then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_IDEA_CYCLE_VALIDATION_ERROR';
  end if;

  -- The state row is the common serialization point used by weekly commits.
  select
    game_run.rule_set_id,
    channel_rule.channel_type_code,
    game_run.specialty_code,
    run_state.current_week
  into
    run_rule_set_id,
    run_channel_type_code,
    run_specialty_code,
    run_current_week
  from public.run_state
  join public.game_runs as game_run on game_run.id = run_state.run_id
  join public.channel_rules as channel_rule
    on channel_rule.id = game_run.channel_rule_id
   and channel_rule.rule_set_id = game_run.rule_set_id
  where run_state.run_id = p_run_id
    and game_run.user_id = p_actor_user_id
    and game_run.status in ('playing', 'stage_cleared')
  for update of run_state;

  if run_rule_set_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_IDEA_CYCLE_RUN_NOT_FOUND';
  end if;

  select
    pg_catalog.count(*),
    pg_catalog.count(distinct rule_idea.system_idea_template_id)
  into eligible_pool_count, eligible_template_count
  from public.rule_set_system_ideas as rule_idea
  join public.system_idea_templates as template
    on template.id = rule_idea.system_idea_template_id
  where rule_idea.rule_set_id = run_rule_set_id
    and rule_idea.enabled
    and template.enabled
    and template.channel_type_code = run_channel_type_code
    and template.specialty_code is not distinct from run_specialty_code;

  select pg_catalog.count(distinct supplied_id)
  into supplied_association_count
  from pg_catalog.unnest(p_ordered_rule_set_system_idea_ids) as supplied(supplied_id);

  if eligible_pool_count <> 50
    or eligible_template_count <> 50
    or supplied_association_count <> 50
    or exists (
      select 1
      from pg_catalog.unnest(p_ordered_rule_set_system_idea_ids) as supplied(supplied_id)
      where not exists (
        select 1
        from public.rule_set_system_ideas as rule_idea
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        where rule_idea.id = supplied.supplied_id
          and rule_idea.rule_set_id = run_rule_set_id
          and rule_idea.enabled
          and template.enabled
          and template.channel_type_code = run_channel_type_code
          and template.specialty_code is not distinct from run_specialty_code
      )
    )
  then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_IDEA_CYCLE_POOL_INVALID';
  end if;

  if exists (
    select 1
    from public.system_idea_cycles as cycle
    where cycle.run_id = p_run_id
      and (
        select pg_catalog.count(*)
        from public.system_idea_cycle_entries as entry
        where entry.cycle_id = cycle.id
      ) <> 50
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_IDEA_CYCLE_STATE_INVALID';
  end if;

  select pg_catalog.count(*)
  into existing_cycle_count
  from public.system_idea_cycles
  where run_id = p_run_id;

  if existing_cycle_count > 0 and exists (
    select 1
    from public.system_idea_cycles as cycle
    where cycle.run_id = p_run_id
    having pg_catalog.min(cycle.cycle_number) <> 1
      or pg_catalog.max(cycle.cycle_number) <> pg_catalog.count(*)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_IDEA_CYCLE_STATE_INVALID';
  end if;

  select pg_catalog.count(*)
  into available_entry_count
  from public.system_idea_cycles as cycle
  join public.system_idea_cycle_entries as entry on entry.cycle_id = cycle.id
  where cycle.run_id = p_run_id
    and not exists (
      select 1
      from public.videos as video
      where video.system_idea_cycle_entry_id = entry.id
    );

  select cycle.id, cycle.cycle_number
  into latest_cycle_id, latest_cycle_number
  from public.system_idea_cycles as cycle
  where cycle.run_id = p_run_id
  order by cycle.cycle_number desc
  limit 1;

  -- A concurrent request may already have persisted enough immutable entries.
  if existing_cycle_count > 0 and available_entry_count >= p_required_count then
    return latest_cycle_id;
  end if;

  if latest_cycle_id is not null then
    select rule_idea.system_idea_template_id
    into previous_last_template_id
    from public.system_idea_cycle_entries as entry
    join public.rule_set_system_ideas as rule_idea
      on rule_idea.id = entry.rule_set_system_idea_id
    where entry.cycle_id = latest_cycle_id
      and entry.position = 50;
  end if;

  select rule_idea.system_idea_template_id
  into proposed_first_template_id
  from public.rule_set_system_ideas as rule_idea
  where rule_idea.id = p_ordered_rule_set_system_idea_ids[1];

  if previous_last_template_id is not null
    and proposed_first_template_id = previous_last_template_id
  then
    raise exception using
      errcode = 'P0001',
      message = 'SYSTEM_IDEA_CYCLE_BOUNDARY_CONFLICT';
  end if;

  insert into public.system_idea_cycles (run_id, cycle_number, created_week)
  values (p_run_id, coalesce(latest_cycle_number, 0) + 1, run_current_week)
  returning id into created_cycle_id;

  insert into public.system_idea_cycle_entries (
    cycle_id,
    rule_set_system_idea_id,
    position
  )
  select
    created_cycle_id,
    ordered.rule_set_system_idea_id,
    ordered.position::smallint
  from pg_catalog.unnest(p_ordered_rule_set_system_idea_ids)
    with ordinality as ordered(rule_set_system_idea_id, position);

  return created_cycle_id;
end;
$$;

comment on function public.commit_system_idea_cycle(uuid, uuid, integer, uuid[]) is
  'Locks the run state and atomically persists one complete 50-entry system idea cycle when existing unused entries cannot satisfy a trusted server request.';

revoke execute on function public.commit_system_idea_cycle(uuid, uuid, integer, uuid[])
  from public, anon, authenticated;
grant execute on function public.commit_system_idea_cycle(uuid, uuid, integer, uuid[])
  to service_role;
