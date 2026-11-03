create view public.current_game_view
with (security_invoker = true)
as
select
  game_run.id as run_id,
  channel_rule.channel_type_code,
  channel_type.name as channel_type_name,
  game_run.specialty_code,
  specialty.name as specialty_name,
  game_run.channel_name,
  game_run.status,
  game_run.created_at,
  game_run.completed_at,
  current_state.current_week,
  posting_frequency.videos_per_week,
  current_state.cash,
  current_state.energy,
  current_state.subscribers,
  current_state.cumulative_views,
  current_state.flame_count,
  current_state.state_version,
  current_state.updated_at,
  coalesce(ability_state.abilities, '[]'::jsonb) as abilities,
  coalesce(equipment_state.equipment, '[]'::jsonb) as equipment,
  active_goal.stage_number as current_stage_number,
  active_goal.target_subscribers as current_goal_target_subscribers,
  active_goal.started_week as current_goal_started_week,
  active_goal.deadline_week as current_goal_deadline_week,
  active_goal.status as current_goal_status,
  active_goal.is_final as is_current_goal_final,
  coalesce(unlocked_features.features, '[]'::jsonb) as feature_unlocks
from public.game_runs as game_run
join public.channel_rules as channel_rule
  on channel_rule.id = game_run.channel_rule_id
 and channel_rule.rule_set_id = game_run.rule_set_id
join public.channel_types as channel_type
  on channel_type.code = channel_rule.channel_type_code
left join public.specialty_categories as specialty
  on specialty.code = game_run.specialty_code
join public.run_state as current_state
  on current_state.run_id = game_run.id
join public.posting_frequency_rules as posting_frequency
  on posting_frequency.id = current_state.posting_frequency_rule_id
 and posting_frequency.rule_set_id = game_run.rule_set_id
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'code', ability.code,
      'name', ability.name,
      'value', run_ability.value
    ) order by ability.display_order
  ) as abilities
  from public.run_abilities as run_ability
  join public.ability_definitions as ability
    on ability.code = run_ability.ability_code
  where run_ability.run_id = game_run.id
) as ability_state on true
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'typeCode', equipment_type.code,
      'typeName', equipment_type.name,
      'tier', equipment_rule.tier,
      'viewBonus', equipment_rule.view_bonus,
      'acquiredWeek', run_equipment.acquired_week
    ) order by equipment_type.display_order
  ) as equipment
  from public.run_equipment as run_equipment
  join public.equipment_types as equipment_type
    on equipment_type.code = run_equipment.equipment_type_code
  join public.equipment_tier_rules as equipment_rule
    on equipment_rule.id = run_equipment.equipment_tier_rule_id
   and equipment_rule.rule_set_id = game_run.rule_set_id
  where run_equipment.run_id = game_run.id
) as equipment_state on true
left join lateral (
  select
    goal_rule.stage_number,
    goal_rule.target_subscribers,
    run_goal.started_week,
    run_goal.deadline_week,
    run_goal.status,
    goal_rule.is_final
  from public.run_goals as run_goal
  join public.goal_rules as goal_rule
    on goal_rule.id = run_goal.goal_rule_id
   and goal_rule.rule_set_id = game_run.rule_set_id
  where run_goal.run_id = game_run.id
    and run_goal.status = 'active'
) as active_goal on true
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'code', feature_definition.code,
      'name', feature_definition.name,
      'unlockedWeek', run_feature.unlocked_week,
      'activeFromWeek', run_feature.active_from_week
    ) order by feature_definition.code
  ) as features
  from public.run_feature_unlocks as run_feature
  join public.feature_rules as feature_rule
    on feature_rule.id = run_feature.feature_rule_id
   and feature_rule.rule_set_id = game_run.rule_set_id
  join public.feature_definitions as feature_definition
    on feature_definition.code = feature_rule.feature_code
  where run_feature.run_id = game_run.id
) as unlocked_features on true
where game_run.status in ('playing', 'stage_cleared');

comment on view public.current_game_view is
  'One row for the current game run with display catalogs and aggregated current-state children. RLS is inherited through security_invoker.';

create view public.idea_stock_view
with (security_invoker = true)
as
select
  queue_entry.run_id,
  player_idea.id as idea_id,
  'player'::text as idea_source,
  queue_entry.position,
  player_idea.title,
  player_idea.description,
  player_idea.created_week,
  player_idea.created_at,
  queue_entry.queued_at,
  'queued'::text as stock_status,
  true as is_pending
from public.idea_queue_entries as queue_entry
join public.player_ideas as player_idea
  on player_idea.id = queue_entry.idea_id
 and player_idea.run_id = queue_entry.run_id
where player_idea.deleted_at is null
  and not exists (
    select 1
    from public.videos as used_video
    where used_video.player_idea_id = player_idea.id
  );

comment on view public.idea_stock_view is
  'Queued player ideas in display order. AI evaluation score and metadata are intentionally excluded.';

create view public.week_history_view
with (security_invoker = true)
as
select
  week_result.run_id,
  week_result.id as week_result_id,
  week_result.week_number,
  stage.stage_number,
  action_definition.code as action_code,
  action_definition.name as action_name,
  posting_frequency.videos_per_week as planned_video_count,
  posted_videos.video_count as posted_video_count,
  week_result.views_before_event,
  week_result.final_views,
  week_result.final_views - week_result.views_before_event as event_view_change,
  week_result.subscribers_before,
  week_result.max_subscribers_during_week,
  week_result.subscribers_after,
  week_result.subscribers_after - week_result.subscribers_before as subscriber_change,
  week_result.energy_before,
  week_result.energy_after,
  week_result.energy_after - week_result.energy_before as energy_change,
  week_result.cash_before,
  week_result.cash_after,
  week_result.cash_after - week_result.cash_before as cash_change,
  week_result.ad_revenue,
  coalesce(previous_week.flame_count_after, 0::smallint) as flame_count_before,
  week_result.flame_count_after,
  week_result.flame_count_after
    - coalesce(previous_week.flame_count_after, 0::smallint) as flame_count_change,
  coalesce(occurred_event.had_flame, false) as had_flame,
  health_result.started_week is not null as health_condition_started,
  health_result.duration_weeks as health_condition_duration_weeks,
  health_result.unavailable_from_week,
  health_result.unavailable_through_week,
  exists (
    select 1
    from public.run_conditions as unavailable_condition
    where unavailable_condition.run_id = week_result.run_id
      and week_result.week_number between unavailable_condition.unavailable_from_week
        and unavailable_condition.unavailable_through_week
  ) as was_activity_unavailable,
  week_result.run_status_after,
  week_result.state_version_after,
  week_result.created_at,
  coalesce(occurred_event.events, '[]'::jsonb) as events
from public.week_results as week_result
join public.game_runs as game_run
  on game_run.id = week_result.run_id
left join public.weekly_actions as weekly_action
  on weekly_action.id = week_result.weekly_action_id
left join public.action_rules as action_rule
  on action_rule.id = weekly_action.action_rule_id
left join public.action_definitions as action_definition
  on action_definition.code = action_rule.action_code
left join public.posting_frequency_rules as posting_frequency
  on posting_frequency.id = week_result.posting_frequency_rule_id
left join public.week_results as previous_week
  on previous_week.run_id = week_result.run_id
 and previous_week.week_number = week_result.week_number - 1
left join lateral (
  select goal_rule.stage_number
  from public.run_goals as run_goal
  join public.goal_rules as goal_rule
    on goal_rule.id = run_goal.goal_rule_id
   and goal_rule.rule_set_id = game_run.rule_set_id
  where run_goal.run_id = week_result.run_id
    and week_result.week_number between run_goal.started_week
      and coalesce(run_goal.achieved_week, run_goal.deadline_week)
  order by run_goal.started_week desc
  limit 1
) as stage on true
left join lateral (
  select count(*)::smallint as video_count
  from public.videos as posted_video
  where posted_video.week_result_id = week_result.id
) as posted_videos on true
left join lateral (
  select
    run_condition.started_week,
    run_condition.duration_weeks,
    run_condition.unavailable_from_week,
    run_condition.unavailable_through_week
  from public.run_conditions as run_condition
  where run_condition.run_id = week_result.run_id
    and run_condition.started_week = week_result.week_number
  order by run_condition.id
  limit 1
) as health_result on true
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'code', event_definition.code,
        'name', event_definition.name,
        'sequenceNumber', event.sequence_number,
        'displayMetadata', event.display_metadata
      ) order by event.sequence_number
    ) as events,
    bool_or(event.event_definition_code = 'flame') as had_flame
  from public.occurred_events as event
  join public.event_definitions as event_definition
    on event_definition.code = event.event_definition_code
  where event.week_result_id = week_result.id
) as occurred_event on true;

comment on view public.week_history_view is
  'Immutable weekly results with stage, actual posts, precomputed deltas, health outcomes, flame status, display action, and ordered event summaries.';

create view public.video_result_view
with (security_invoker = true)
as
select
  week_result.run_id,
  week_result.id as week_result_id,
  week_result.week_number,
  video.id as video_id,
  video.sequence_number,
  case
    when video.player_idea_id is not null then 'player'
    else 'system'
  end as idea_source,
  video.title_snapshot,
  calculation.base_views,
  calculation.subscriber_multiplier,
  calculation.ability_multiplier,
  calculation.idea_multiplier,
  calculation.posting_frequency_multiplier,
  calculation.channel_multiplier,
  calculation.equipment_multiplier,
  calculation.collaboration_multiplier,
  calculation.views_before_event,
  calculation.event_multiplier,
  calculation.final_views,
  calculation.conversion_rate,
  calculation.subscribers_gained,
  video.created_at
from public.videos as video
join public.week_results as week_result
  on week_result.id = video.week_result_id
join public.video_calculations as calculation
  on calculation.video_id = video.id;

comment on view public.video_result_view is
  'Per-video immutable calculation snapshots for explaining a weekly result.';

revoke all privileges on table
  public.current_game_view,
  public.idea_stock_view,
  public.week_history_view,
  public.video_result_view
from public, anon, authenticated;

grant select on table
  public.current_game_view,
  public.idea_stock_view,
  public.week_history_view,
  public.video_result_view
to authenticated;
