alter table public.game_terminations
  drop constraint game_terminations_reason_shape_check;

alter table public.game_terminations
  add constraint game_terminations_reason_shape_check
    check (
      (
        reason = 'death'
        and execution_id is not null
        and week_result_id is null
        and calculated_energy is not null
        and calculated_energy <= 0
        and (calculated_flame_count is null or calculated_flame_count < 3)
      )
      or (
        reason = 'flame_ban'
        and execution_id is not null
        and week_result_id is null
        and calculated_flame_count is not null
        and calculated_flame_count >= 3
      )
      or (
        reason = 'deadline'
        and execution_id is null
        and week_result_id is not null
        and calculated_energy is null
        and calculated_flame_count is null
      )
      or (
        reason = 'abandoned'
        and execution_id is null
        and week_result_id is null
        and calculated_energy is null
        and calculated_flame_count is null
      )
    );

comment on constraint game_terminations_reason_shape_check on public.game_terminations is
  'Flame-ban history may retain calculated energy; commit_advance_week always stores both decision inputs.';

create or replace function public.get_advance_week_receipt(p_idempotency_key uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  committed_week public.week_results%rowtype;
  fatal_termination public.game_terminations%rowtype;
begin
  select *
  into committed_week
  from public.week_results
  where execution_id = p_idempotency_key;

  if found then
    return pg_catalog.jsonb_build_object(
      'outcome', 'week_committed',
      'runId', committed_week.run_id,
      'completedWeek', committed_week.week_number,
      'nextWeek', committed_week.week_number + 1,
      'weekResultId', committed_week.id,
      'nextStateVersion', committed_week.state_version_after,
      'runStatusAfter', committed_week.run_status_after
    );
  end if;

  select *
  into fatal_termination
  from public.game_terminations
  where execution_id = p_idempotency_key
    and reason in ('death', 'flame_ban');

  if found then
    return pg_catalog.jsonb_build_object(
      'outcome', 'fatal_game_over',
      'runId', fatal_termination.run_id,
      'attemptedWeek', fatal_termination.occurred_week,
      'terminationId', fatal_termination.id,
      'reason', fatal_termination.reason,
      'runStatusAfter', 'game_over'
    );
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'ADVANCE_WEEK_COMMIT_FAILED';
end;
$$;

comment on function public.get_advance_week_receipt(uuid) is
  'Reconstructs the immutable receipt for an advance-week execution. This is an internal helper for commit_advance_week.';

create or replace function public.commit_advance_week(p_command jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  actor_user_id uuid;
  target_run_id uuid;
  attempted_week integer;
  expected_version integer;
  command_idempotency_key uuid;
  command_kind text;
  goal_outcome text;

  existing_execution public.advance_week_executions%rowtype;
  execution_owner_id uuid;
  locked_state public.run_state%rowtype;
  locked_run public.game_runs%rowtype;
  locked_action public.weekly_actions%rowtype;
  active_condition public.run_conditions%rowtype;
  active_goal public.run_goals%rowtype;
  selected_goal_rule public.goal_rules%rowtype;
  selected_global_rule public.global_rules%rowtype;
  selected_frequency_rule public.posting_frequency_rules%rowtype;
  selected_action_rule public.action_rules%rowtype;

  week_snapshot jsonb;
  state_after jsonb;
  video_items jsonb;
  event_items jsonb;
  feature_items jsonb;
  health_condition jsonb;
  random_event jsonb;
  flame_event jsonb;
  video_item jsonb;

  week_result_id uuid;
  weekly_action_id uuid;
  posting_frequency_rule_id uuid;
  next_state_version integer;
  run_status_after text;

  views_before_event bigint;
  final_views bigint;
  subscribers_before bigint;
  max_subscribers_during_week bigint;
  subscribers_after bigint;
  energy_before smallint;
  energy_after smallint;
  cash_before bigint;
  cash_after bigint;
  ad_revenue bigint;
  flame_count_after smallint;

  state_cash bigint;
  state_energy smallint;
  state_subscribers bigint;
  state_cumulative_views bigint;
  state_flame_count smallint;

  expected_video_count integer;
  actual_video_count integer;
  actual_player_video_count integer;
  queued_player_idea_count integer;
  expected_player_video_count integer;
  supplied_player_idea_ids uuid[];
  expected_player_idea_ids uuid[];
  supplied_feature_rule_ids uuid[];
  eligible_feature_rule_ids uuid[];

  video_sequence integer;
  video_source text;
  video_id uuid;
  player_idea_id uuid;
  system_idea_cycle_entry_id uuid;
  expected_title text;
  title_snapshot text;
  calculation jsonb;
  base_views bigint;
  subscriber_multiplier numeric;
  ability_multiplier numeric;
  idea_multiplier numeric;
  frequency_multiplier numeric;
  channel_multiplier numeric;
  equipment_multiplier numeric;
  collaboration_multiplier numeric;
  video_views_before_event bigint;
  event_multiplier numeric;
  video_final_views bigint;
  conversion_rate numeric;
  subscribers_gained bigint;
  expected_subscriber_multiplier numeric;
  expected_ability_multiplier numeric;
  expected_idea_multiplier numeric;
  expected_conversion_rate numeric;
  expected_equipment_multiplier numeric;
  expected_event_multiplier numeric := 1;
  expected_views_before_event bigint;
  summed_views_before_event bigint := 0;
  summed_final_views bigint := 0;
  summed_subscribers_gained bigint := 0;

  subscribers_after_videos bigint;
  subscribers_after_random_event bigint;
  expected_subscribers_after bigint;
  expected_max_subscribers_during_week bigint;
  sponsorship_reward bigint := 0;
  expected_ad_revenue bigint;
  cash_after_action bigint;
  cash_before_random_event bigint;
  expected_cash_after bigint;
  energy_after_action integer;
  energy_before_flame_event integer;
  expected_energy_after integer;

  event_rule public.event_rules%rowtype;
  random_event_definition text;
  random_cash_before bigint;
  random_cash_after bigint;
  random_subscribers_before bigint;
  random_subscribers_after bigint;
  flame_subscribers_before bigint;
  flame_subscribers_after bigint;
  flame_energy_before integer;
  flame_energy_after integer;
  flame_count_before integer;
  event_flame_count_after integer;

  ability_points_awarded smallint;
  ability_point_grant_status text;
  health_risk_rule public.health_risk_rules%rowtype;
  health_duration_weeks smallint;
  fatal_reason text;
  calculated_energy integer;
  calculated_flame_count integer;
begin
  if p_command is null or pg_catalog.jsonb_typeof(p_command) <> 'object' then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
  end if;

  actor_user_id := (p_command ->> 'actorUserId')::uuid;
  target_run_id := (p_command ->> 'runId')::uuid;
  attempted_week := (p_command ->> 'attemptedWeek')::integer;
  expected_version := (p_command ->> 'expectedVersion')::integer;
  command_idempotency_key := (p_command ->> 'idempotencyKey')::uuid;
  command_kind := p_command ->> 'kind';

  if actor_user_id is null
    or target_run_id is null
    or attempted_week is null
    or attempted_week < 1
    or expected_version is null
    or expected_version < 0
    or command_idempotency_key is null
    or command_kind not in ('normal', 'activity_unavailable', 'fatal_game_over')
  then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
  end if;

  -- Serializing on the client-generated key closes the gap between the first
  -- lookup and execution insertion for concurrent retries of the same command.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('advance_week:' || command_idempotency_key::text, 0)
  );

  select execution.*
  into existing_execution
  from public.advance_week_executions as execution
  where execution.idempotency_key = command_idempotency_key;

  if found then
    select user_id
    into execution_owner_id
    from public.game_runs
    where id = existing_execution.run_id;

    if execution_owner_id is distinct from actor_user_id
      or existing_execution.run_id is distinct from target_run_id
      or existing_execution.attempted_week is distinct from attempted_week
      or existing_execution.expected_state_version is distinct from expected_version
    then
      raise exception using
        errcode = 'P0001',
        message = 'ADVANCE_WEEK_IDEMPOTENCY_KEY_REUSED';
    end if;

    return public.get_advance_week_receipt(command_idempotency_key);
  end if;

  select *
  into locked_state
  from public.run_state
  where run_id = target_run_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_RUN_NOT_FOUND';
  end if;

  select *
  into locked_run
  from public.game_runs
  where id = target_run_id;

  if locked_run.user_id is distinct from actor_user_id then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_FORBIDDEN';
  end if;

  if locked_run.status <> 'playing' then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_RUN_NOT_PLAYABLE';
  end if;

  if locked_state.current_week is distinct from attempted_week then
    if exists (
      select 1
      from public.week_results
      where run_id = target_run_id and week_number = attempted_week
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'ADVANCE_WEEK_WEEK_ALREADY_COMMITTED';
    end if;

    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_STALE_STATE';
  end if;

  if locked_state.state_version is distinct from expected_version then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_STALE_STATE';
  end if;

  select *
  into selected_global_rule
  from public.global_rules
  where rule_set_id = locked_run.rule_set_id;

  select *
  into active_goal
  from public.run_goals
  where run_id = target_run_id and status = 'active'
  for update;

  if selected_global_rule.rule_set_id is null or active_goal.id is null then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_COMMIT_FAILED';
  end if;

  select *
  into selected_goal_rule
  from public.goal_rules
  where id = active_goal.goal_rule_id
    and rule_set_id = locked_run.rule_set_id;

  if selected_goal_rule.id is null then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_COMMIT_FAILED';
  end if;

  next_state_version := expected_version + 1;

  if command_kind = 'fatal_game_over' then
    select *
    into locked_action
    from public.weekly_actions
    where run_id = target_run_id and week_number = attempted_week
    for update;

    if locked_action.id is null or locked_action.locked_at is not null then
      raise exception using
        errcode = 'P0001',
        message = 'ADVANCE_WEEK_WEEKLY_ACTION_REQUIRED';
    end if;

    if exists (
      select 1
      from public.run_conditions
      where run_id = target_run_id
        and attempted_week between unavailable_from_week and unavailable_through_week
    ) then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    fatal_reason := p_command ->> 'reason';
    calculated_energy := (p_command ->> 'calculatedEnergy')::integer;
    calculated_flame_count := (p_command ->> 'calculatedFlameCount')::integer;

    if calculated_energy is null or calculated_flame_count is null then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    if fatal_reason = 'flame_ban' then
      if calculated_flame_count < selected_global_rule.ban_flame_count then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;
    elsif fatal_reason = 'death' then
      if calculated_energy > 0
        or calculated_flame_count >= selected_global_rule.ban_flame_count
      then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;
    else
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    insert into public.advance_week_executions (
      idempotency_key,
      run_id,
      attempted_week,
      expected_state_version,
      outcome
    ) values (
      command_idempotency_key,
      target_run_id,
      attempted_week,
      expected_version,
      'fatal_game_over'
    );

    insert into public.game_terminations (
      run_id,
      execution_id,
      reason,
      occurred_week,
      calculated_energy,
      calculated_flame_count
    ) values (
      target_run_id,
      command_idempotency_key,
      fatal_reason,
      attempted_week,
      calculated_energy,
      calculated_flame_count
    );

    update public.game_runs
    set status = 'game_over', completed_at = pg_catalog.statement_timestamp()
    where id = target_run_id;

    return public.get_advance_week_receipt(command_idempotency_key);
  end if;

  week_snapshot := p_command -> 'weekResult';
  state_after := p_command -> 'stateAfter';
  goal_outcome := p_command ->> 'goalOutcome';

  if pg_catalog.jsonb_typeof(week_snapshot) <> 'object'
    or pg_catalog.jsonb_typeof(state_after) <> 'object'
    or goal_outcome not in ('active', 'achieved', 'deadline')
  then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
  end if;

  views_before_event := (week_snapshot ->> 'viewsBeforeEvent')::bigint;
  final_views := (week_snapshot ->> 'finalViews')::bigint;
  subscribers_before := (week_snapshot ->> 'subscribersBefore')::bigint;
  max_subscribers_during_week := (week_snapshot ->> 'maxSubscribersDuringWeek')::bigint;
  subscribers_after := (week_snapshot ->> 'subscribersAfter')::bigint;
  energy_before := (week_snapshot ->> 'energyBefore')::smallint;
  energy_after := (week_snapshot ->> 'energyAfter')::smallint;
  cash_before := (week_snapshot ->> 'cashBefore')::bigint;
  cash_after := (week_snapshot ->> 'cashAfter')::bigint;
  ad_revenue := (week_snapshot ->> 'adRevenue')::bigint;
  flame_count_after := (week_snapshot ->> 'flameCountAfter')::smallint;

  state_cash := (state_after ->> 'cash')::bigint;
  state_energy := (state_after ->> 'energy')::smallint;
  state_subscribers := (state_after ->> 'subscribers')::bigint;
  state_cumulative_views := (state_after ->> 'cumulativeViews')::bigint;
  state_flame_count := (state_after ->> 'flameCount')::smallint;

  if views_before_event < 0
    or final_views < 0
    or subscribers_before < 0
    or subscribers_after < 0
    or max_subscribers_during_week < subscribers_before
    or max_subscribers_during_week < subscribers_after
    or energy_before < 0
    or energy_after < 0
    or cash_before < 0
    or cash_after < 0
    or ad_revenue < 0
    or flame_count_after < 0
    or subscribers_before is distinct from locked_state.subscribers
    or energy_before is distinct from locked_state.energy
    or cash_before is distinct from locked_state.cash
    or state_cash is distinct from cash_after
    or state_energy is distinct from energy_after
    or state_subscribers is distinct from subscribers_after
    or state_flame_count is distinct from flame_count_after
    or state_cumulative_views is distinct from locked_state.cumulative_views + final_views
  then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
  end if;

  if subscribers_after >= selected_goal_rule.target_subscribers then
    if goal_outcome <> 'achieved' then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;
    run_status_after := case when selected_goal_rule.is_final then 'cleared' else 'stage_cleared' end;
  elsif attempted_week >= active_goal.deadline_week then
    if goal_outcome <> 'deadline' then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;
    run_status_after := 'game_over';
  else
    if goal_outcome <> 'active' then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;
    run_status_after := 'playing';
  end if;

  if command_kind = 'activity_unavailable' then
    select *
    into active_condition
    from public.run_conditions
    where run_id = target_run_id
      and recovered_at is null
      and attempted_week between unavailable_from_week and unavailable_through_week
    for update;

    if active_condition.id is null
      or exists (
        select 1
        from public.weekly_actions
        where run_id = target_run_id and week_number = attempted_week
      )
      or views_before_event <> 0
      or final_views <> 0
      or ad_revenue <> 0
      or subscribers_after is distinct from subscribers_before
      or max_subscribers_during_week is distinct from subscribers_before
      or cash_after is distinct from cash_before
      or flame_count_after is distinct from locked_state.flame_count
      or energy_after is distinct from least(
        selected_global_rule.energy_max,
        energy_before + selected_global_rule.unavailable_energy_recovery
      )
    then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    insert into public.advance_week_executions (
      idempotency_key, run_id, attempted_week, expected_state_version, outcome
    ) values (
      command_idempotency_key, target_run_id, attempted_week, expected_version, 'week_committed'
    );

    insert into public.week_results (
      execution_id,
      run_id,
      week_number,
      weekly_action_id,
      posting_frequency_rule_id,
      views_before_event,
      final_views,
      subscribers_before,
      max_subscribers_during_week,
      subscribers_after,
      energy_before,
      energy_after,
      cash_before,
      cash_after,
      ad_revenue,
      flame_count_after,
      run_status_after,
      state_version_after
    ) values (
      command_idempotency_key,
      target_run_id,
      attempted_week,
      null,
      null,
      views_before_event,
      final_views,
      subscribers_before,
      max_subscribers_during_week,
      subscribers_after,
      energy_before,
      energy_after,
      cash_before,
      cash_after,
      ad_revenue,
      flame_count_after,
      run_status_after,
      next_state_version
    ) returning id into week_result_id;

    if attempted_week = active_condition.unavailable_through_week then
      update public.run_conditions
      set recovered_at = pg_catalog.statement_timestamp()
      where id = active_condition.id;

      update public.ability_point_grants
      set status = 'available'
      where run_id = target_run_id and status = 'held';
    end if;
  else
    weekly_action_id := (p_command ->> 'weeklyActionId')::uuid;
    posting_frequency_rule_id := (p_command ->> 'postingFrequencyRuleId')::uuid;
    video_items := p_command -> 'videos';
    event_items := p_command -> 'events';
    feature_items := p_command -> 'featureUnlockRuleIds';
    health_condition := p_command -> 'healthCondition';
    ability_points_awarded := (p_command ->> 'abilityPointsAwarded')::smallint;
    ability_point_grant_status := p_command ->> 'abilityPointGrantStatus';

    if weekly_action_id is null
      or posting_frequency_rule_id is null
      or pg_catalog.jsonb_typeof(video_items) <> 'array'
      or pg_catalog.jsonb_typeof(event_items) <> 'array'
      or pg_catalog.jsonb_typeof(feature_items) <> 'array'
    then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    select *
    into locked_action
    from public.weekly_actions
    where id = weekly_action_id
      and run_id = target_run_id
      and week_number = attempted_week
    for update;

    if locked_action.id is null or locked_action.locked_at is not null then
      raise exception using
        errcode = 'P0001',
        message = 'ADVANCE_WEEK_WEEKLY_ACTION_REQUIRED';
    end if;

    select *
    into selected_action_rule
    from public.action_rules
    where id = locked_action.action_rule_id
      and rule_set_id = locked_run.rule_set_id;

    select *
    into selected_frequency_rule
    from public.posting_frequency_rules
    where id = posting_frequency_rule_id
      and rule_set_id = locked_run.rule_set_id;

    if selected_action_rule.id is null
      or selected_frequency_rule.id is null
      or posting_frequency_rule_id is distinct from locked_state.posting_frequency_rule_id
      or ability_points_awarded is distinct from selected_frequency_rule.ability_points_awarded
      or energy_after <= 0
      or flame_count_after >= selected_global_rule.ban_flame_count
      or exists (
        select 1
        from public.run_conditions
        where run_id = target_run_id
          and attempted_week between unavailable_from_week and unavailable_through_week
      )
    then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    expected_video_count := selected_frequency_rule.videos_per_week;
    actual_video_count := pg_catalog.jsonb_array_length(video_items);

    if actual_video_count <> expected_video_count
      or (select pg_catalog.count(distinct (item ->> 'sequenceNumber')::integer)
          from pg_catalog.jsonb_array_elements(video_items) as items(item)) <> expected_video_count
      or (select pg_catalog.min((item ->> 'sequenceNumber')::integer)
          from pg_catalog.jsonb_array_elements(video_items) as items(item)) <> 1
      or (select pg_catalog.max((item ->> 'sequenceNumber')::integer)
          from pg_catalog.jsonb_array_elements(video_items) as items(item)) <> expected_video_count
    then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    select pg_catalog.count(*)::integer
    into queued_player_idea_count
    from public.idea_queue_entries
    where run_id = target_run_id;

    expected_player_video_count := least(queued_player_idea_count, expected_video_count);

    select
      pg_catalog.count(*) filter (where item ->> 'source' = 'player')::integer,
      coalesce(
        pg_catalog.array_agg((item ->> 'playerIdeaId')::uuid order by (item ->> 'sequenceNumber')::integer)
          filter (where item ->> 'source' = 'player'),
        array[]::uuid[]
      )
    into actual_player_video_count, supplied_player_idea_ids
    from pg_catalog.jsonb_array_elements(video_items) as items(item);

    select coalesce(pg_catalog.array_agg(idea_id order by position), array[]::uuid[])
    into expected_player_idea_ids
    from (
      select idea_id, position
      from public.idea_queue_entries
      where run_id = target_run_id
      order by position
      limit expected_player_video_count
    ) as queued;

    if actual_player_video_count <> expected_player_video_count
      or supplied_player_idea_ids is distinct from expected_player_idea_ids
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(video_items) as items(item)
        where ((item ->> 'sequenceNumber')::integer <= expected_player_video_count)
          is distinct from (item ->> 'source' = 'player')
      )
    then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    if (select pg_catalog.count(*)
        from pg_catalog.jsonb_array_elements(event_items) as items(item)
        where item ->> 'kind' = 'random') > 1
      or (select pg_catalog.count(*)
          from pg_catalog.jsonb_array_elements(event_items) as items(item)
          where item ->> 'kind' = 'flame') > 1
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(event_items) as items(item)
        where item ->> 'kind' not in ('random', 'flame')
      )
    then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    select item into random_event
    from pg_catalog.jsonb_array_elements(event_items) as items(item)
    where item ->> 'kind' = 'random';

    select item into flame_event
    from pg_catalog.jsonb_array_elements(event_items) as items(item)
    where item ->> 'kind' = 'flame';

    if random_event is not null then
      select *
      into event_rule
      from public.event_rules
      where id = (random_event ->> 'eventRuleId')::uuid
        and rule_set_id = locked_run.rule_set_id;

      if event_rule.id is null then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;

      expected_event_multiplier := event_rule.weekly_view_multiplier;
      random_event_definition := event_rule.event_definition_code;
      random_cash_before := (random_event ->> 'cashBefore')::bigint;
      random_cash_after := (random_event ->> 'cashAfter')::bigint;
      random_subscribers_before := (random_event ->> 'subscribersBefore')::bigint;
      random_subscribers_after := (random_event ->> 'subscribersAfter')::bigint;

      if random_cash_before < 0
        or random_subscribers_before < 0
      then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;
    end if;

    if flame_event is not null then
      flame_subscribers_before := (flame_event ->> 'subscribersBefore')::bigint;
      flame_subscribers_after := (flame_event ->> 'subscribersAfter')::bigint;
      flame_energy_before := (flame_event ->> 'energyBefore')::integer;
      flame_energy_after := (flame_event ->> 'energyAfter')::integer;
      flame_count_before := (flame_event ->> 'flameCountBefore')::integer;
      event_flame_count_after := (flame_event ->> 'flameCountAfter')::integer;

      if flame_count_before is distinct from locked_state.flame_count
        or event_flame_count_after is distinct from flame_count_before + 1
        or event_flame_count_after is distinct from flame_count_after
      then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;
    elsif flame_count_after is distinct from locked_state.flame_count then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    expected_subscriber_multiplier :=
      1 + pg_catalog.floor(locked_state.subscribers::numeric / 100000) * 0.5;

    select 1 + (pg_catalog.sum(ability.value * weight.weight) - 10) / 100
    into expected_ability_multiplier
    from public.run_abilities as ability
    join public.channel_ability_weights as weight
      on weight.ability_code = ability.ability_code
     and weight.channel_rule_id = locked_run.channel_rule_id
     and weight.rule_set_id = locked_run.rule_set_id
    where ability.run_id = target_run_id;

    select least(1.45::numeric, 1 + coalesce(pg_catalog.sum(tier.view_bonus), 0))
    into expected_equipment_multiplier
    from public.run_equipment as equipment
    join public.equipment_tier_rules as tier
      on tier.id = equipment.equipment_tier_rule_id
     and tier.rule_set_id = locked_run.rule_set_id
    where equipment.run_id = target_run_id;

    if expected_ability_multiplier is null or expected_equipment_multiplier is null then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_COMMIT_FAILED';
    end if;

    for video_item in
      select item
      from pg_catalog.jsonb_array_elements(video_items) as items(item)
      order by (item ->> 'sequenceNumber')::integer
    loop
      video_sequence := (video_item ->> 'sequenceNumber')::integer;
      video_source := video_item ->> 'source';
      title_snapshot := video_item ->> 'titleSnapshot';
      calculation := video_item -> 'calculation';
      player_idea_id := null;
      system_idea_cycle_entry_id := null;

      if pg_catalog.jsonb_typeof(calculation) <> 'object'
        or title_snapshot is null
        or pg_catalog.char_length(title_snapshot) not between 1 and 100
      then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;

      if video_source = 'player' then
        player_idea_id := (video_item ->> 'playerIdeaId')::uuid;

        select idea.title, band.view_multiplier, band.subscriber_conversion_rate
        into expected_title, expected_idea_multiplier, expected_conversion_rate
        from public.player_ideas as idea
        join public.idea_evaluations as evaluation on evaluation.idea_id = idea.id
        join public.idea_score_band_rules as band
          on band.rule_set_id = locked_run.rule_set_id
         and evaluation.score between band.min_score and band.max_score
        where idea.id = player_idea_id
          and idea.run_id = target_run_id
          and idea.deleted_at is null;
      elsif video_source = 'system' then
        system_idea_cycle_entry_id := (video_item ->> 'systemIdeaCycleEntryId')::uuid;

        select
          template.title,
          selected_global_rule.system_idea_view_multiplier,
          selected_global_rule.system_idea_subscriber_conversion_rate
        into expected_title, expected_idea_multiplier, expected_conversion_rate
        from public.system_idea_cycle_entries as entry
        join public.system_idea_cycles as cycle on cycle.id = entry.cycle_id
        join public.rule_set_system_ideas as rule_idea
          on rule_idea.id = entry.rule_set_system_idea_id
        join public.system_idea_templates as template
          on template.id = rule_idea.system_idea_template_id
        join public.channel_rules as channel_rule
          on channel_rule.id = locked_run.channel_rule_id
         and channel_rule.rule_set_id = locked_run.rule_set_id
        where entry.id = system_idea_cycle_entry_id
          and cycle.run_id = target_run_id
          and rule_idea.rule_set_id = locked_run.rule_set_id
          and rule_idea.enabled
          and template.enabled
          and template.channel_type_code = channel_rule.channel_type_code
          and template.specialty_code is not distinct from locked_run.specialty_code
          and not exists (
            select 1
            from public.videos
            where videos.system_idea_cycle_entry_id = entry.id
          );
      else
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;

      if expected_title is null or title_snapshot is distinct from expected_title then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;

      base_views := (calculation ->> 'baseViews')::bigint;
      subscriber_multiplier := (calculation ->> 'subscriberMultiplier')::numeric;
      ability_multiplier := (calculation ->> 'abilityMultiplier')::numeric;
      idea_multiplier := (calculation ->> 'ideaMultiplier')::numeric;
      frequency_multiplier := (calculation ->> 'postingFrequencyMultiplier')::numeric;
      channel_multiplier := (calculation ->> 'channelMultiplier')::numeric;
      equipment_multiplier := (calculation ->> 'equipmentMultiplier')::numeric;
      collaboration_multiplier := (calculation ->> 'collaborationMultiplier')::numeric;
      video_views_before_event := (calculation ->> 'viewsBeforeEvent')::bigint;
      event_multiplier := (calculation ->> 'eventMultiplier')::numeric;
      video_final_views := (calculation ->> 'finalViews')::bigint;
      conversion_rate := (calculation ->> 'conversionRate')::numeric;
      subscribers_gained := (calculation ->> 'subscribersGained')::bigint;

      expected_views_before_event := pg_catalog.floor(
        base_views::numeric
          * subscriber_multiplier
          * ability_multiplier
          * idea_multiplier
          * frequency_multiplier
          * channel_multiplier
          * equipment_multiplier
          * collaboration_multiplier
      )::bigint;

      if base_views not between selected_global_rule.base_views_min and selected_global_rule.base_views_max
        or subscriber_multiplier is distinct from expected_subscriber_multiplier
        or ability_multiplier is distinct from expected_ability_multiplier
        or idea_multiplier is distinct from expected_idea_multiplier
        or frequency_multiplier is distinct from selected_frequency_rule.view_multiplier
        or channel_multiplier is distinct from (
          select view_multiplier from public.channel_rules where id = locked_run.channel_rule_id
        )
        or equipment_multiplier is distinct from expected_equipment_multiplier
        or collaboration_multiplier is distinct from selected_action_rule.video_view_multiplier
        or video_views_before_event is distinct from expected_views_before_event
        or event_multiplier is distinct from expected_event_multiplier
        or video_final_views < 0
        or conversion_rate is distinct from expected_conversion_rate
        or subscribers_gained is distinct from pg_catalog.floor(
          video_final_views::numeric * conversion_rate
        )::bigint
      then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;

      summed_views_before_event := summed_views_before_event + video_views_before_event;
      summed_final_views := summed_final_views + video_final_views;
      summed_subscribers_gained := summed_subscribers_gained + subscribers_gained;
    end loop;

    expected_ad_revenue := case
      when exists (
        select 1
        from public.run_feature_unlocks as unlock
        join public.feature_rules as feature on feature.id = unlock.feature_rule_id
        where unlock.run_id = target_run_id
          and feature.rule_set_id = locked_run.rule_set_id
          and feature.feature_code = 'ad_revenue'
          and unlock.active_from_week <= attempted_week
      ) then pg_catalog.floor(
        final_views::numeric * selected_global_rule.ad_revenue_per_view
      )::bigint
      else 0
    end;

    if selected_action_rule.action_code = 'sponsorship' then
      select reward_amount
      into sponsorship_reward
      from public.sponsorship_reward_rules as reward_rule
      where reward_rule.rule_set_id = locked_run.rule_set_id
        and locked_state.subscribers >= reward_rule.min_subscribers
        and (
          reward_rule.max_subscribers is null
          or locked_state.subscribers <= reward_rule.max_subscribers
        );

      if sponsorship_reward is null then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;
    end if;

    subscribers_after_videos := locked_state.subscribers + summed_subscribers_gained;
    subscribers_after_random_event := case
      when random_event is null then subscribers_after_videos
      else greatest(
        0::bigint,
        pg_catalog.floor(
          subscribers_after_videos::numeric * event_rule.subscriber_multiplier
        )::bigint + event_rule.fixed_subscriber_delta
      )
    end;
    expected_subscribers_after := case
      when flame_event is null then subscribers_after_random_event
      else pg_catalog.floor(
        subscribers_after_random_event::numeric
          * (1 - selected_global_rule.flame_subscriber_loss_rate)
      )::bigint
    end;
    expected_max_subscribers_during_week := greatest(
      locked_state.subscribers,
      subscribers_after_videos,
      subscribers_after_random_event,
      expected_subscribers_after
    );

    cash_after_action := greatest(
      0::bigint,
      locked_state.cash + selected_action_rule.fixed_cash_delta + sponsorship_reward
    );
    cash_before_random_event := cash_after_action + expected_ad_revenue;
    expected_cash_after := case
      when random_event is null then cash_before_random_event
      else greatest(
        0::bigint,
        cash_before_random_event + event_rule.fixed_cash_delta
      )
    end;

    energy_after_action := locked_state.energy + selected_action_rule.energy_delta;
    if selected_action_rule.energy_delta > 0 then
      energy_after_action := least(energy_after_action, selected_global_rule.energy_max);
    end if;
    energy_before_flame_event := energy_after_action - selected_frequency_rule.energy_cost;
    expected_energy_after := case
      when flame_event is null then energy_before_flame_event
      else energy_before_flame_event - selected_global_rule.flame_energy_loss
    end;

    if summed_views_before_event is distinct from views_before_event
      or summed_final_views is distinct from final_views
      or final_views is distinct from pg_catalog.floor(
        views_before_event::numeric * expected_event_multiplier
      )::bigint
      or ad_revenue is distinct from expected_ad_revenue
      or subscribers_after is distinct from expected_subscribers_after
      or max_subscribers_during_week is distinct from expected_max_subscribers_during_week
      or cash_after is distinct from expected_cash_after
      or energy_after is distinct from expected_energy_after
      or (random_event is not null and (
        random_subscribers_before is distinct from subscribers_after_videos
        or random_subscribers_after is distinct from subscribers_after_random_event
        or random_cash_before is distinct from cash_before_random_event
        or random_cash_after is distinct from expected_cash_after
      ))
      or (flame_event is not null and (
        flame_subscribers_before is distinct from subscribers_after_random_event
        or flame_subscribers_after is distinct from expected_subscribers_after
        or flame_energy_before is distinct from energy_before_flame_event
        or flame_energy_after is distinct from expected_energy_after
      ))
    then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    select coalesce(
      pg_catalog.array_agg((item #>> '{}')::uuid order by (item #>> '{}')::uuid),
      array[]::uuid[]
    )
    into supplied_feature_rule_ids
    from pg_catalog.jsonb_array_elements(feature_items) as items(item);

    if pg_catalog.cardinality(supplied_feature_rule_ids) is distinct from (
      select pg_catalog.count(distinct feature_id)::integer
      from pg_catalog.unnest(supplied_feature_rule_ids) as supplied(feature_id)
    ) then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    select coalesce(pg_catalog.array_agg(feature.id order by feature.id), array[]::uuid[])
    into eligible_feature_rule_ids
    from public.feature_rules as feature
    where feature.rule_set_id = locked_run.rule_set_id
      and feature.unlock_subscribers <= max_subscribers_during_week
      and not exists (
        select 1
        from public.run_feature_unlocks as unlock
        where unlock.run_id = target_run_id and unlock.feature_rule_id = feature.id
      );

    if supplied_feature_rule_ids is distinct from eligible_feature_rule_ids then
      raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
    end if;

    if health_condition is null or pg_catalog.jsonb_typeof(health_condition) = 'null' then
      if ability_point_grant_status <> 'available' then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;
    else
      if pg_catalog.jsonb_typeof(health_condition) <> 'object'
        or ability_point_grant_status <> 'held'
      then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;

      health_duration_weeks := (health_condition ->> 'durationWeeks')::smallint;
      select *
      into health_risk_rule
      from public.health_risk_rules
      where id = (health_condition ->> 'healthRiskRuleId')::uuid
        and rule_set_id = locked_run.rule_set_id
        and energy_after between min_energy and max_energy;

      if health_risk_rule.id is null
        or health_duration_weeks not between health_risk_rule.min_unavailable_weeks
          and health_risk_rule.max_unavailable_weeks
        or health_duration_weeks <= 0
      then
        raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
      end if;
    end if;

    insert into public.advance_week_executions (
      idempotency_key, run_id, attempted_week, expected_state_version, outcome
    ) values (
      command_idempotency_key, target_run_id, attempted_week, expected_version, 'week_committed'
    );

    update public.weekly_actions
    set locked_at = pg_catalog.statement_timestamp()
    where id = weekly_action_id;

    insert into public.week_results (
      execution_id,
      run_id,
      week_number,
      weekly_action_id,
      posting_frequency_rule_id,
      views_before_event,
      final_views,
      subscribers_before,
      max_subscribers_during_week,
      subscribers_after,
      energy_before,
      energy_after,
      cash_before,
      cash_after,
      ad_revenue,
      flame_count_after,
      run_status_after,
      state_version_after
    ) values (
      command_idempotency_key,
      target_run_id,
      attempted_week,
      weekly_action_id,
      posting_frequency_rule_id,
      views_before_event,
      final_views,
      subscribers_before,
      max_subscribers_during_week,
      subscribers_after,
      energy_before,
      energy_after,
      cash_before,
      cash_after,
      ad_revenue,
      flame_count_after,
      run_status_after,
      next_state_version
    ) returning id into week_result_id;

    for video_item in
      select item
      from pg_catalog.jsonb_array_elements(video_items) as items(item)
      order by (item ->> 'sequenceNumber')::integer
    loop
      video_sequence := (video_item ->> 'sequenceNumber')::integer;
      video_source := video_item ->> 'source';
      calculation := video_item -> 'calculation';
      player_idea_id := case when video_source = 'player'
        then (video_item ->> 'playerIdeaId')::uuid else null end;
      system_idea_cycle_entry_id := case when video_source = 'system'
        then (video_item ->> 'systemIdeaCycleEntryId')::uuid else null end;

      insert into public.videos (
        week_result_id,
        sequence_number,
        player_idea_id,
        system_idea_cycle_entry_id,
        title_snapshot
      ) values (
        week_result_id,
        video_sequence,
        player_idea_id,
        system_idea_cycle_entry_id,
        video_item ->> 'titleSnapshot'
      ) returning id into video_id;

      insert into public.video_calculations (
        video_id,
        base_views,
        subscriber_multiplier,
        ability_multiplier,
        idea_multiplier,
        posting_frequency_multiplier,
        channel_multiplier,
        equipment_multiplier,
        collaboration_multiplier,
        views_before_event,
        event_multiplier,
        final_views,
        conversion_rate,
        subscribers_gained
      ) values (
        video_id,
        (calculation ->> 'baseViews')::bigint,
        (calculation ->> 'subscriberMultiplier')::numeric,
        (calculation ->> 'abilityMultiplier')::numeric,
        (calculation ->> 'ideaMultiplier')::numeric,
        (calculation ->> 'postingFrequencyMultiplier')::numeric,
        (calculation ->> 'channelMultiplier')::numeric,
        (calculation ->> 'equipmentMultiplier')::numeric,
        (calculation ->> 'collaborationMultiplier')::numeric,
        (calculation ->> 'viewsBeforeEvent')::bigint,
        (calculation ->> 'eventMultiplier')::numeric,
        (calculation ->> 'finalViews')::bigint,
        (calculation ->> 'conversionRate')::numeric,
        (calculation ->> 'subscribersGained')::bigint
      );
    end loop;

    if random_event is not null then
      insert into public.occurred_events (
        week_result_id,
        event_definition_code,
        event_rule_id,
        sequence_number
      ) values (
        week_result_id,
        random_event_definition,
        event_rule.id,
        1
      );
    end if;

    if flame_event is not null then
      insert into public.occurred_events (
        week_result_id,
        event_definition_code,
        event_rule_id,
        sequence_number
      ) values (
        week_result_id,
        'flame',
        null,
        case when random_event is null then 1 else 2 end
      );
    end if;

    delete from public.idea_queue_entries
    where run_id = target_run_id
      and idea_id = any(supplied_player_idea_ids);

    update public.idea_queue_entries
    set position = position - expected_player_video_count
    where run_id = target_run_id;

    insert into public.run_feature_unlocks (
      run_id, feature_rule_id, unlocked_week, active_from_week
    )
    select
      target_run_id,
      feature.id,
      attempted_week,
      attempted_week + feature.activation_delay_weeks
    from public.feature_rules as feature
    where feature.id = any(supplied_feature_rule_ids);

    update public.ability_point_grants as point_grant
    set status = case
      when (
        select coalesce(pg_catalog.sum(allocation.points), 0)
        from public.ability_allocations as allocation
        where allocation.grant_id = point_grant.id
      ) >= point_grant.amount then 'consumed'
      else 'expired'
    end
    where point_grant.run_id = target_run_id
      and point_grant.status in ('available', 'held');

    insert into public.ability_point_grants (
      run_id,
      earned_week,
      available_from_week,
      amount,
      status
    ) values (
      target_run_id,
      attempted_week,
      attempted_week + 1,
      ability_points_awarded,
      ability_point_grant_status
    );

    if health_condition is not null and pg_catalog.jsonb_typeof(health_condition) <> 'null' then
      insert into public.run_conditions (
        run_id,
        health_risk_rule_id,
        started_week,
        duration_weeks,
        unavailable_from_week,
        unavailable_through_week
      ) values (
        target_run_id,
        health_risk_rule.id,
        attempted_week,
        health_duration_weeks,
        attempted_week + 1,
        attempted_week + health_duration_weeks
      );
    end if;
  end if;

  if goal_outcome = 'achieved' then
    update public.run_goals
    set status = 'achieved', achieved_week = attempted_week
    where id = active_goal.id;
  elsif goal_outcome = 'deadline' then
    update public.run_goals
    set status = 'failed'
    where id = active_goal.id;

    insert into public.game_terminations (
      run_id, week_result_id, reason, occurred_week
    ) values (
      target_run_id, week_result_id, 'deadline', attempted_week
    );
  end if;

  update public.run_state
  set current_week = attempted_week + 1,
      cash = state_cash,
      energy = state_energy,
      subscribers = state_subscribers,
      cumulative_views = state_cumulative_views,
      flame_count = state_flame_count,
      state_version = next_state_version,
      updated_at = pg_catalog.statement_timestamp()
  where run_id = target_run_id;

  update public.game_runs
  set status = run_status_after,
      completed_at = case
        when run_status_after in ('cleared', 'game_over')
          then pg_catalog.statement_timestamp()
        else null
      end
  where id = target_run_id;

  return public.get_advance_week_receipt(command_idempotency_key);
exception
  when sqlstate 'P0001' then
    raise;
  when invalid_text_representation or numeric_value_out_of_range or not_null_violation then
    raise exception using errcode = 'P0001', message = 'ADVANCE_WEEK_VALIDATION_ERROR';
end;
$$;

comment on function public.commit_advance_week(jsonb) is
  'Validates and atomically persists one precomputed normal, unavailable, or fatal advance-week command for a trusted server caller.';

revoke execute on function public.get_advance_week_receipt(uuid)
  from public, anon, authenticated;
revoke execute on function public.commit_advance_week(jsonb)
  from public, anon, authenticated;
grant execute on function public.get_advance_week_receipt(uuid)
  to service_role;
grant execute on function public.commit_advance_week(jsonb)
  to service_role;
