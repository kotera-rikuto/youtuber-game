-- Client roles start with no table access. Grants below are the complete public
-- API for the schema; RLS remains a second ownership boundary for granted reads.
revoke all privileges on all tables in schema public from public, anon, authenticated;

alter table public.channel_types enable row level security;
alter table public.specialty_categories enable row level security;
alter table public.ability_definitions enable row level security;
alter table public.equipment_types enable row level security;
alter table public.action_definitions enable row level security;
alter table public.feature_definitions enable row level security;
alter table public.event_categories enable row level security;
alter table public.event_definitions enable row level security;

create policy authenticated_read_channel_types
on public.channel_types for select to authenticated using (true);
create policy authenticated_read_specialty_categories
on public.specialty_categories for select to authenticated using (true);
create policy authenticated_read_ability_definitions
on public.ability_definitions for select to authenticated using (true);
create policy authenticated_read_equipment_types
on public.equipment_types for select to authenticated using (true);
create policy authenticated_read_action_definitions
on public.action_definitions for select to authenticated using (true);
create policy authenticated_read_feature_definitions
on public.feature_definitions for select to authenticated using (true);
create policy authenticated_read_event_categories
on public.event_categories for select to authenticated using (true);
create policy authenticated_read_event_definitions
on public.event_definitions for select to authenticated using (true);

grant select on table
  public.channel_types,
  public.specialty_categories,
  public.ability_definitions,
  public.equipment_types,
  public.action_definitions,
  public.feature_definitions,
  public.event_categories,
  public.event_definitions
to authenticated;

-- A non-draft rule set is immutable and may remain referenced after retirement,
-- so both active and retired published versions are readable.
alter table public.rule_sets enable row level security;

create policy authenticated_read_published_rule_sets
on public.rule_sets for select to authenticated
using (status in ('active', 'retired') and published_at is not null);

grant select on table public.rule_sets to authenticated;

alter table public.global_rules enable row level security;
alter table public.channel_rules enable row level security;
alter table public.channel_ability_weights enable row level security;
alter table public.rule_set_specialties enable row level security;
alter table public.posting_frequency_rules enable row level security;
alter table public.idea_score_band_rules enable row level security;
alter table public.equipment_tier_rules enable row level security;
alter table public.feature_rules enable row level security;
alter table public.action_rules enable row level security;
alter table public.sponsorship_reward_rules enable row level security;
alter table public.goal_rules enable row level security;
alter table public.event_category_rules enable row level security;
alter table public.event_rules enable row level security;
alter table public.health_risk_rules enable row level security;

create policy authenticated_read_published_global_rules
on public.global_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = global_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_channel_rules
on public.channel_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = channel_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_channel_ability_weights
on public.channel_ability_weights for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = channel_ability_weights.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_rule_set_specialties
on public.rule_set_specialties for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = rule_set_specialties.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_posting_frequency_rules
on public.posting_frequency_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = posting_frequency_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_idea_score_band_rules
on public.idea_score_band_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = idea_score_band_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_equipment_tier_rules
on public.equipment_tier_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = equipment_tier_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_feature_rules
on public.feature_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = feature_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_action_rules
on public.action_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = action_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_sponsorship_reward_rules
on public.sponsorship_reward_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = sponsorship_reward_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_goal_rules
on public.goal_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = goal_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_event_category_rules
on public.event_category_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = event_category_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_event_rules
on public.event_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = event_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));
create policy authenticated_read_published_health_risk_rules
on public.health_risk_rules for select to authenticated
using (exists (
  select 1 from public.rule_sets
  where rule_sets.id = health_risk_rules.rule_set_id
    and rule_sets.status in ('active', 'retired')
    and rule_sets.published_at is not null
));

grant select on table
  public.global_rules,
  public.channel_rules,
  public.channel_ability_weights,
  public.rule_set_specialties,
  public.posting_frequency_rules,
  public.idea_score_band_rules,
  public.equipment_tier_rules,
  public.feature_rules,
  public.action_rules,
  public.sponsorship_reward_rules,
  public.goal_rules,
  public.event_category_rules,
  public.event_rules,
  public.health_risk_rules
to authenticated;

alter table public.system_idea_templates enable row level security;
alter table public.rule_set_system_ideas enable row level security;

create policy authenticated_read_published_system_idea_templates
on public.system_idea_templates for select to authenticated
using (
  enabled
  and exists (
    select 1
    from public.rule_set_system_ideas
    join public.rule_sets on rule_sets.id = rule_set_system_ideas.rule_set_id
    where rule_set_system_ideas.system_idea_template_id = system_idea_templates.id
      and rule_set_system_ideas.enabled
      and rule_sets.status in ('active', 'retired')
      and rule_sets.published_at is not null
  )
);

create policy authenticated_read_published_rule_set_system_ideas
on public.rule_set_system_ideas for select to authenticated
using (
  enabled
  and exists (
    select 1 from public.rule_sets
    where rule_sets.id = rule_set_system_ideas.rule_set_id
      and rule_sets.status in ('active', 'retired')
      and rule_sets.published_at is not null
  )
);

grant select on table
  public.system_idea_templates,
  public.rule_set_system_ideas
to authenticated;

-- Profiles are the only client-writable table. The column-level UPDATE grant
-- prevents ownership and creation metadata from being reassigned.
alter table public.profiles enable row level security;

create policy users_read_own_profile
on public.profiles for select to authenticated
using (user_id = auth.uid());
create policy users_insert_own_profile
on public.profiles for insert to authenticated
with check (user_id = auth.uid());
create policy users_update_own_profile
on public.profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
create policy users_delete_own_profile
on public.profiles for delete to authenticated
using (user_id = auth.uid());

grant select, delete on table public.profiles to authenticated;
grant insert (user_id, display_name) on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

alter table public.game_runs enable row level security;
alter table public.run_state enable row level security;
alter table public.run_abilities enable row level security;
alter table public.run_equipment enable row level security;
alter table public.run_feature_unlocks enable row level security;
alter table public.run_conditions enable row level security;
alter table public.run_goals enable row level security;
alter table public.player_ideas enable row level security;
alter table public.idea_evaluations enable row level security;
alter table public.idea_queue_entries enable row level security;
alter table public.weekly_actions enable row level security;
alter table public.ability_point_grants enable row level security;
alter table public.ability_allocations enable row level security;
alter table public.equipment_purchases enable row level security;
alter table public.system_idea_cycles enable row level security;
alter table public.system_idea_cycle_entries enable row level security;
alter table public.advance_week_executions enable row level security;
alter table public.week_results enable row level security;
alter table public.videos enable row level security;
alter table public.video_calculations enable row level security;
alter table public.occurred_events enable row level security;
alter table public.game_terminations enable row level security;

create policy users_read_own_game_runs
on public.game_runs for select to authenticated
using (user_id = auth.uid());

create policy users_read_own_run_state
on public.run_state for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = run_state.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_run_abilities
on public.run_abilities for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = run_abilities.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_run_equipment
on public.run_equipment for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = run_equipment.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_run_feature_unlocks
on public.run_feature_unlocks for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = run_feature_unlocks.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_run_conditions
on public.run_conditions for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = run_conditions.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_run_goals
on public.run_goals for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = run_goals.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_player_ideas
on public.player_ideas for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = player_ideas.run_id and game_runs.user_id = auth.uid()
));

-- No policy or table grant is intentionally created for idea_evaluations. AI
-- scores and model metadata are only available to trusted server credentials.

create policy users_read_own_idea_queue_entries
on public.idea_queue_entries for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = idea_queue_entries.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_weekly_actions
on public.weekly_actions for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = weekly_actions.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_ability_point_grants
on public.ability_point_grants for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = ability_point_grants.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_ability_allocations
on public.ability_allocations for select to authenticated
using (exists (
  select 1
  from public.ability_point_grants
  join public.game_runs on game_runs.id = ability_point_grants.run_id
  where ability_point_grants.id = ability_allocations.grant_id
    and game_runs.user_id = auth.uid()
));
create policy users_read_own_equipment_purchases
on public.equipment_purchases for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = equipment_purchases.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_system_idea_cycles
on public.system_idea_cycles for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = system_idea_cycles.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_system_idea_cycle_entries
on public.system_idea_cycle_entries for select to authenticated
using (exists (
  select 1
  from public.system_idea_cycles
  join public.game_runs on game_runs.id = system_idea_cycles.run_id
  where system_idea_cycles.id = system_idea_cycle_entries.cycle_id
    and game_runs.user_id = auth.uid()
));
create policy users_read_own_advance_week_executions
on public.advance_week_executions for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = advance_week_executions.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_week_results
on public.week_results for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = week_results.run_id and game_runs.user_id = auth.uid()
));
create policy users_read_own_videos
on public.videos for select to authenticated
using (exists (
  select 1
  from public.week_results
  join public.game_runs on game_runs.id = week_results.run_id
  where week_results.id = videos.week_result_id
    and game_runs.user_id = auth.uid()
));
create policy users_read_own_video_calculations
on public.video_calculations for select to authenticated
using (exists (
  select 1
  from public.videos
  join public.week_results on week_results.id = videos.week_result_id
  join public.game_runs on game_runs.id = week_results.run_id
  where videos.id = video_calculations.video_id
    and game_runs.user_id = auth.uid()
));
create policy users_read_own_occurred_events
on public.occurred_events for select to authenticated
using (exists (
  select 1
  from public.week_results
  join public.game_runs on game_runs.id = week_results.run_id
  where week_results.id = occurred_events.week_result_id
    and game_runs.user_id = auth.uid()
));
create policy users_read_own_game_terminations
on public.game_terminations for select to authenticated
using (exists (
  select 1 from public.game_runs
  where game_runs.id = game_terminations.run_id and game_runs.user_id = auth.uid()
));

grant select on table
  public.game_runs,
  public.run_state,
  public.run_abilities,
  public.run_equipment,
  public.run_feature_unlocks,
  public.run_conditions,
  public.run_goals,
  public.player_ideas,
  public.idea_queue_entries,
  public.weekly_actions,
  public.ability_point_grants,
  public.ability_allocations,
  public.equipment_purchases,
  public.system_idea_cycles,
  public.system_idea_cycle_entries,
  public.advance_week_executions,
  public.week_results,
  public.videos,
  public.video_calculations,
  public.occurred_events,
  public.game_terminations
to authenticated;

-- PostgreSQL grants EXECUTE to PUBLIC by default. Existing internal and trigger
-- functions are server-only, and future functions created by postgres inherit
-- the same deny-by-default client policy.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public
  grant execute on functions to service_role;
