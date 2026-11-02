create table public.advance_week_executions (
  idempotency_key uuid primary key,
  run_id uuid not null,
  attempted_week integer not null,
  expected_state_version integer not null,
  outcome text not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint advance_week_executions_run_id_fkey
    foreign key (run_id)
    references public.game_runs (id)
    on update restrict
    on delete restrict,
  constraint advance_week_executions_attempted_week_positive_check
    check (attempted_week >= 1),
  constraint advance_week_executions_expected_state_version_nonnegative_check
    check (expected_state_version >= 0),
  constraint advance_week_executions_outcome_check
    check (outcome in ('week_committed', 'fatal_game_over'))
);

create index advance_week_executions_run_idx
  on public.advance_week_executions (run_id);

create table public.week_results (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  execution_id uuid not null unique,
  run_id uuid not null,
  week_number integer not null,
  weekly_action_id uuid,
  posting_frequency_rule_id uuid,
  views_before_event bigint not null,
  final_views bigint not null,
  subscribers_before bigint not null,
  max_subscribers_during_week bigint not null,
  subscribers_after bigint not null,
  energy_before smallint not null,
  energy_after smallint not null,
  cash_before bigint not null,
  cash_after bigint not null,
  ad_revenue bigint not null,
  flame_count_after smallint not null,
  run_status_after text not null,
  state_version_after integer not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint week_results_execution_id_fkey
    foreign key (execution_id)
    references public.advance_week_executions (idempotency_key)
    on update restrict
    on delete restrict,
  constraint week_results_run_id_fkey
    foreign key (run_id)
    references public.game_runs (id)
    on update restrict
    on delete restrict,
  constraint week_results_weekly_action_id_fkey
    foreign key (weekly_action_id)
    references public.weekly_actions (id)
    on update restrict
    on delete restrict,
  constraint week_results_posting_frequency_rule_id_fkey
    foreign key (posting_frequency_rule_id)
    references public.posting_frequency_rules (id)
    on update restrict
    on delete restrict,
  constraint week_results_run_week_key unique (run_id, week_number),
  constraint week_results_week_number_positive_check check (week_number >= 1),
  constraint week_results_views_nonnegative_check
    check (views_before_event >= 0 and final_views >= 0),
  constraint week_results_subscribers_nonnegative_check
    check (
      subscribers_before >= 0
      and max_subscribers_during_week >= 0
      and subscribers_after >= 0
    ),
  constraint week_results_max_subscribers_consistent_check
    check (
      max_subscribers_during_week >= subscribers_before
      and max_subscribers_during_week >= subscribers_after
    ),
  constraint week_results_energy_nonnegative_check
    check (energy_before >= 0 and energy_after >= 0),
  constraint week_results_cash_nonnegative_check
    check (cash_before >= 0 and cash_after >= 0 and ad_revenue >= 0),
  constraint week_results_flame_count_nonnegative_check check (flame_count_after >= 0),
  constraint week_results_run_status_after_check
    check (run_status_after in ('playing', 'stage_cleared', 'cleared', 'game_over', 'abandoned')),
  constraint week_results_state_version_after_nonnegative_check
    check (state_version_after >= 0)
);

create index week_results_weekly_action_idx
  on public.week_results (weekly_action_id)
  where weekly_action_id is not null;

create index week_results_posting_frequency_rule_idx
  on public.week_results (posting_frequency_rule_id)
  where posting_frequency_rule_id is not null;

comment on table public.week_results is
  'Immutable normal-week snapshots. Normal posting weeks require action and frequency references; unavailable weeks omit both. BE-009 or commit_advance_week will enforce those semantics plus cross-table run, week, and rule-version agreement.';

create table public.videos (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  week_result_id uuid not null,
  sequence_number smallint not null,
  player_idea_id uuid unique,
  system_idea_cycle_entry_id uuid unique,
  title_snapshot text not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint videos_week_result_id_fkey
    foreign key (week_result_id)
    references public.week_results (id)
    on update restrict
    on delete restrict,
  constraint videos_player_idea_id_fkey
    foreign key (player_idea_id)
    references public.player_ideas (id)
    on update restrict
    on delete restrict,
  constraint videos_system_idea_cycle_entry_id_fkey
    foreign key (system_idea_cycle_entry_id)
    references public.system_idea_cycle_entries (id)
    on update restrict
    on delete restrict,
  constraint videos_week_result_sequence_key unique (week_result_id, sequence_number),
  constraint videos_sequence_number_check check (sequence_number between 1 and 7),
  constraint videos_title_snapshot_check
    check (char_length(title_snapshot) between 1 and 100 and title_snapshot ~ '[^[:space:]]'),
  constraint videos_idea_source_check
    check ((player_idea_id is null) <> (system_idea_cycle_entry_id is null))
);

comment on constraint videos_idea_source_check on public.videos is
  'Each published video must reference exactly one player or system idea source.';

comment on table public.videos is
  'Immutable published-video facts. BE-009 will enforce run agreement among the week result and selected idea source.';

create table public.video_calculations (
  video_id uuid primary key,
  base_views bigint not null,
  subscriber_multiplier numeric not null,
  ability_multiplier numeric not null,
  idea_multiplier numeric not null,
  posting_frequency_multiplier numeric not null,
  channel_multiplier numeric not null,
  equipment_multiplier numeric not null,
  collaboration_multiplier numeric not null,
  views_before_event bigint not null,
  event_multiplier numeric not null,
  final_views bigint not null,
  conversion_rate numeric not null,
  subscribers_gained bigint not null,
  created_at timestamptz not null default statement_timestamp(),
  constraint video_calculations_video_id_fkey
    foreign key (video_id)
    references public.videos (id)
    on update restrict
    on delete restrict,
  constraint video_calculations_base_views_nonnegative_check check (base_views >= 0),
  constraint video_calculations_multipliers_nonnegative_check
    check (
      subscriber_multiplier >= 0
      and ability_multiplier >= 0
      and idea_multiplier >= 0
      and posting_frequency_multiplier >= 0
      and channel_multiplier >= 0
      and equipment_multiplier >= 0
      and collaboration_multiplier >= 0
      and event_multiplier >= 0
    ),
  constraint video_calculations_views_nonnegative_check
    check (views_before_event >= 0 and final_views >= 0),
  constraint video_calculations_conversion_rate_check
    check (conversion_rate between 0 and 1),
  constraint video_calculations_subscribers_gained_nonnegative_check
    check (subscribers_gained >= 0)
);

comment on table public.video_calculations is
  'Immutable calculation inputs and outputs; formula agreement is enforced by the later calculation and commit workflow.';

create table public.occurred_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  week_result_id uuid not null,
  event_definition_code text not null,
  event_rule_id uuid,
  sequence_number smallint not null,
  display_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default statement_timestamp(),
  constraint occurred_events_week_result_id_fkey
    foreign key (week_result_id)
    references public.week_results (id)
    on update restrict
    on delete restrict,
  constraint occurred_events_event_definition_code_fkey
    foreign key (event_definition_code)
    references public.event_definitions (code)
    on update restrict
    on delete restrict,
  constraint occurred_events_event_rule_id_fkey
    foreign key (event_rule_id)
    references public.event_rules (id)
    on update restrict
    on delete restrict,
  constraint occurred_events_week_result_sequence_key
    unique (week_result_id, sequence_number),
  constraint occurred_events_week_result_definition_key
    unique (week_result_id, event_definition_code),
  constraint occurred_events_sequence_number_positive_check check (sequence_number >= 1),
  constraint occurred_events_display_metadata_object_check
    check (jsonb_typeof(display_metadata) = 'object'),
  constraint occurred_events_definition_rule_shape_check
    check (
      (event_definition_code = 'flame' and event_rule_id is null)
      or (
        event_definition_code in (
          'featured_in_recommendations',
          'introduced_by_celebrity',
          'temporary_bonus',
          'poorly_received_video',
          'equipment_trouble',
          'criticized_on_social_media'
        )
        and event_rule_id is not null
      )
    )
);

-- Random events and flame are independent weekly decisions. The definition
-- uniqueness already limits flame to one row, while this partial index limits
-- all six random-event definitions collectively to one row per week result.
create unique index occurred_events_one_random_per_week_idx
  on public.occurred_events (week_result_id)
  where event_definition_code <> 'flame';

create index occurred_events_event_definition_idx
  on public.occurred_events (event_definition_code);

create index occurred_events_event_rule_idx
  on public.occurred_events (event_rule_id)
  where event_rule_id is not null;

comment on column public.occurred_events.event_rule_id is
  'Required for one of the six random events and NULL for flame. BE-009 will enforce definition and rule-set agreement.';

create table public.game_terminations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null unique,
  execution_id uuid unique,
  week_result_id uuid unique,
  reason text not null,
  occurred_week integer not null,
  calculated_energy smallint,
  calculated_flame_count smallint,
  created_at timestamptz not null default statement_timestamp(),
  constraint game_terminations_run_id_fkey
    foreign key (run_id)
    references public.game_runs (id)
    on update restrict
    on delete restrict,
  constraint game_terminations_execution_id_fkey
    foreign key (execution_id)
    references public.advance_week_executions (idempotency_key)
    on update restrict
    on delete restrict,
  constraint game_terminations_week_result_id_fkey
    foreign key (week_result_id)
    references public.week_results (id)
    on update restrict
    on delete restrict,
  constraint game_terminations_reason_check
    check (reason in ('death', 'flame_ban', 'deadline', 'abandoned')),
  constraint game_terminations_occurred_week_positive_check check (occurred_week >= 1),
  constraint game_terminations_calculated_flame_count_nonnegative_check
    check (calculated_flame_count is null or calculated_flame_count >= 0),
  constraint game_terminations_reason_shape_check
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
        and (calculated_energy is null or calculated_energy <= 0)
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
    )
);

comment on table public.game_terminations is
  'One immutable terminal fact per game run. BE-009 will enforce run agreement with the referenced execution or week result.';

create trigger protect_advance_week_execution_history
before update or delete on public.advance_week_executions
for each row
execute function public.reject_immutable_history_change();

create trigger protect_week_result_history
before update or delete on public.week_results
for each row
execute function public.reject_immutable_history_change();

create trigger protect_video_history
before update or delete on public.videos
for each row
execute function public.reject_immutable_history_change();

create trigger protect_video_calculation_history
before update or delete on public.video_calculations
for each row
execute function public.reject_immutable_history_change();

create trigger protect_occurred_event_history
before update or delete on public.occurred_events
for each row
execute function public.reject_immutable_history_change();

create trigger protect_game_termination_history
before update or delete on public.game_terminations
for each row
execute function public.reject_immutable_history_change();

comment on function public.reject_immutable_history_change() is
  'Shared trigger guard for append-only facts whose UPDATE and DELETE prohibition cannot be expressed by CHECK constraints.';

-- The BE-004 publication check originally treated every event definition as a
-- random-event rule. Flame is a system event backed by channel/global rules,
-- so only definitions in the good and bad categories belong to that pool.
create or replace function public.validate_rule_set_for_publication(target_rule_set_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  rule_count integer;
begin
  select count(*) into rule_count from public.global_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 1 then raise exception 'Rule set must contain exactly one global rule'; end if;

  select count(*) into rule_count from public.channel_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 4 or exists (
    select 1 from (values ('mainstream'), ('specialized'), ('controversial'), ('idol')) as required(code)
    where not exists (
      select 1 from public.channel_rules where rule_set_id = target_rule_set_id and channel_type_code = required.code
    )
  ) then raise exception 'Rule set must contain all four channel rules'; end if;

  if exists (
    select 1
    from public.channel_rules as channel_rule
    left join public.channel_ability_weights as ability_weight on ability_weight.channel_rule_id = channel_rule.id
    where channel_rule.rule_set_id = target_rule_set_id
    group by channel_rule.id
    having count(ability_weight.id) <> 2 or sum(ability_weight.weight) <> 1
  ) then raise exception 'Each channel rule must contain two ability weights totaling one'; end if;

  select count(*) into rule_count from public.rule_set_specialties where rule_set_id = target_rule_set_id;
  if rule_count <> 10 or exists (
    select 1 from (values
      ('baseball'), ('soccer'), ('gaming'), ('pc_gadgets'), ('science'),
      ('history_culture'), ('occult'), ('nature'), ('food_culture'), ('outdoor_survival')
    ) as required(code)
    where not exists (
      select 1 from public.rule_set_specialties
      where rule_set_id = target_rule_set_id and specialty_code = required.code
    )
  ) then raise exception 'Rule set must enable all ten initial specialties'; end if;

  select count(*) into rule_count from public.posting_frequency_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 3 or exists (
    select 1 from (values (1), (3), (7)) as required(videos)
    where not exists (
      select 1 from public.posting_frequency_rules where rule_set_id = target_rule_set_id and videos_per_week = required.videos
    )
  ) then raise exception 'Rule set must contain posting frequencies 1, 3, and 7'; end if;

  select count(*) into rule_count from public.idea_score_band_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 5 or exists (
    select 1 from pg_catalog.generate_series(0, 100) as score(value)
    where not exists (
      select 1 from public.idea_score_band_rules
      where rule_set_id = target_rule_set_id and score.value between min_score and max_score
    )
  ) then raise exception 'Idea score bands must cover every score from 0 through 100'; end if;

  select count(*) into rule_count from public.equipment_tier_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 12 or exists (
    select 1
    from (values ('camera'), ('microphone'), ('editing_pc')) as equipment(code)
    cross join (values ('none'), ('beginner'), ('intermediate'), ('advanced')) as required_tier(tier)
    where not exists (
      select 1 from public.equipment_tier_rules
      where rule_set_id = target_rule_set_id
        and equipment_type_code = equipment.code
        and equipment_tier_rules.tier = required_tier.tier
    )
  ) then raise exception 'Rule set must contain all twelve equipment tiers'; end if;

  select count(*) into rule_count from public.action_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 4 or exists (
    select 1 from (values ('part_time_job'), ('rest'), ('collaboration'), ('sponsorship')) as required(code)
    where not exists (
      select 1 from public.action_rules where rule_set_id = target_rule_set_id and action_code = required.code
    )
  ) then raise exception 'Rule set must contain all four action rules'; end if;

  select count(*) into rule_count from public.sponsorship_reward_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 6 or (
    select min(min_subscribers) <> 100000 or count(*) filter (where max_subscribers is null) <> 1
    from public.sponsorship_reward_rules where rule_set_id = target_rule_set_id
  ) or exists (
    select 1
    from (
      select min_subscribers, max_subscribers,
        lead(min_subscribers) over (order by min_subscribers) as next_min_subscribers
      from public.sponsorship_reward_rules where rule_set_id = target_rule_set_id
    ) as reward_band
    where (next_min_subscribers is null) <> (max_subscribers is null)
      or (next_min_subscribers is not null and next_min_subscribers <> max_subscribers + 1)
  ) then raise exception 'Sponsorship reward bands must form the complete configured ladder'; end if;

  select count(*) into rule_count from public.feature_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 3 or exists (
    select 1 from (values ('ad_revenue'), ('collaboration'), ('sponsorship')) as required(code)
    where not exists (
      select 1 from public.feature_rules where rule_set_id = target_rule_set_id and feature_code = required.code
    )
  ) then raise exception 'Rule set must contain all three feature rules'; end if;

  select count(*) into rule_count from public.goal_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 5 or exists (
    select 1 from pg_catalog.generate_series(1, 5) as stage(value)
    where not exists (
      select 1 from public.goal_rules where rule_set_id = target_rule_set_id and stage_number = stage.value
    )
  ) or (select count(*) from public.goal_rules where rule_set_id = target_rule_set_id and is_final) <> 1
    or not exists (
      select 1 from public.goal_rules where rule_set_id = target_rule_set_id and stage_number = 5 and is_final
    )
  then raise exception 'Rule set must contain stages 1 through 5 with stage 5 final'; end if;

  select count(*) into rule_count from public.event_category_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 2 or exists (
    select 1 from (values ('good'), ('bad')) as required(code)
    where not exists (
      select 1 from public.event_category_rules where rule_set_id = target_rule_set_id and category_code = required.code
    )
  ) then raise exception 'Rule set must contain good and bad event categories'; end if;

  select count(*) into rule_count from public.event_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 6 or exists (
    select 1
    from public.event_definitions as definition
    where definition.category_code in ('good', 'bad')
      and not exists (
        select 1 from public.event_rules
        where rule_set_id = target_rule_set_id and event_definition_code = definition.code
      )
  ) then raise exception 'Rule set must contain all six random event rules'; end if;

  select count(*) into rule_count from public.health_risk_rules where rule_set_id = target_rule_set_id;
  if rule_count <> 4 or exists (
    select 1 from pg_catalog.generate_series(1, 100) as energy(value)
    where not exists (
      select 1 from public.health_risk_rules
      where rule_set_id = target_rule_set_id and energy.value between min_energy and max_energy
    )
  ) then raise exception 'Health risk bands must cover every energy value from 1 through 100'; end if;
end;
$$;

comment on function public.validate_rule_set_for_publication(uuid) is
  'Validates versioned rule families while excluding system events such as flame from the six-rule random-event pool.';
