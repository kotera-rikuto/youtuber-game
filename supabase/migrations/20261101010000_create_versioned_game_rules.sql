create table public.global_rules (
  rule_set_id uuid primary key,
  base_views_min bigint not null,
  base_views_max bigint not null,
  energy_max smallint not null,
  unavailable_energy_recovery smallint not null,
  ideas_per_week smallint not null,
  idea_stock_max smallint not null,
  flame_subscriber_loss_rate numeric not null,
  flame_energy_loss smallint not null,
  ban_flame_count smallint not null,
  ad_revenue_per_view numeric not null,
  system_idea_view_multiplier numeric not null,
  system_idea_subscriber_conversion_rate numeric not null,
  constraint global_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint global_rules_base_views_range_check
    check (base_views_min >= 0 and base_views_max >= base_views_min),
  constraint global_rules_energy_max_positive_check check (energy_max > 0),
  constraint global_rules_unavailable_energy_recovery_nonnegative_check check (unavailable_energy_recovery >= 0),
  constraint global_rules_ideas_per_week_positive_check check (ideas_per_week > 0),
  constraint global_rules_idea_stock_max_positive_check check (idea_stock_max > 0),
  constraint global_rules_flame_subscriber_loss_rate_check check (flame_subscriber_loss_rate between 0 and 1),
  constraint global_rules_flame_energy_loss_nonnegative_check check (flame_energy_loss >= 0),
  constraint global_rules_ban_flame_count_positive_check check (ban_flame_count > 0),
  constraint global_rules_ad_revenue_per_view_nonnegative_check check (ad_revenue_per_view >= 0),
  constraint global_rules_system_idea_view_multiplier_nonnegative_check check (system_idea_view_multiplier >= 0),
  constraint global_rules_system_idea_subscriber_conversion_rate_check
    check (system_idea_subscriber_conversion_rate between 0 and 1)
);

comment on table public.global_rules is 'One row per rule set containing game-wide numeric rules.';
comment on column public.global_rules.base_views_min is 'Inclusive minimum random base views per video.';
comment on column public.global_rules.base_views_max is 'Inclusive maximum random base views per video.';
comment on column public.global_rules.ad_revenue_per_view is 'Advertising revenue in yen per eligible view.';

create table public.channel_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  channel_type_code text not null,
  view_multiplier numeric not null,
  weekly_flame_probability numeric not null,
  constraint channel_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint channel_rules_channel_type_code_fkey
    foreign key (channel_type_code) references public.channel_types (code) on update restrict on delete restrict,
  constraint channel_rules_rule_set_channel_type_key unique (rule_set_id, channel_type_code),
  constraint channel_rules_rule_set_id_id_key unique (rule_set_id, id),
  constraint channel_rules_view_multiplier_nonnegative_check check (view_multiplier >= 0),
  constraint channel_rules_weekly_flame_probability_check check (weekly_flame_probability between 0 and 1)
);

create table public.channel_ability_weights (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  channel_rule_id uuid not null,
  ability_code text not null,
  weight numeric not null,
  constraint channel_ability_weights_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint channel_ability_weights_rule_set_channel_rule_fkey
    foreign key (rule_set_id, channel_rule_id)
    references public.channel_rules (rule_set_id, id) on update restrict on delete restrict,
  constraint channel_ability_weights_ability_code_fkey
    foreign key (ability_code) references public.ability_definitions (code) on update restrict on delete restrict,
  constraint channel_ability_weights_channel_rule_ability_key unique (channel_rule_id, ability_code),
  constraint channel_ability_weights_weight_positive_check check (weight > 0)
);

create table public.rule_set_specialties (
  rule_set_id uuid not null,
  specialty_code text not null,
  constraint rule_set_specialties_pkey primary key (rule_set_id, specialty_code),
  constraint rule_set_specialties_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint rule_set_specialties_specialty_code_fkey
    foreign key (specialty_code) references public.specialty_categories (code) on update restrict on delete restrict
);

create table public.posting_frequency_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  videos_per_week smallint not null,
  view_multiplier numeric not null,
  energy_cost smallint not null,
  ability_points_awarded smallint not null,
  constraint posting_frequency_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint posting_frequency_rules_rule_set_videos_key unique (rule_set_id, videos_per_week),
  constraint posting_frequency_rules_videos_per_week_positive_check check (videos_per_week > 0),
  constraint posting_frequency_rules_view_multiplier_nonnegative_check check (view_multiplier >= 0),
  constraint posting_frequency_rules_energy_cost_nonnegative_check check (energy_cost >= 0),
  constraint posting_frequency_rules_ability_points_nonnegative_check check (ability_points_awarded >= 0)
);

create table public.idea_score_band_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  min_score smallint not null,
  max_score smallint not null,
  view_multiplier numeric not null,
  subscriber_conversion_rate numeric not null,
  constraint idea_score_band_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint idea_score_band_rules_score_range_check
    check (min_score between 0 and 100 and max_score between 0 and 100 and min_score <= max_score),
  constraint idea_score_band_rules_view_multiplier_nonnegative_check check (view_multiplier >= 0),
  constraint idea_score_band_rules_subscriber_conversion_rate_check check (subscriber_conversion_rate between 0 and 1),
  constraint idea_score_band_rules_score_overlap_excl
    exclude using gist (rule_set_id with =, int4range(min_score, max_score, '[]') with &&)
);

create table public.equipment_tier_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  equipment_type_code text not null,
  tier text not null,
  purchase_price bigint not null,
  view_bonus numeric not null,
  constraint equipment_tier_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint equipment_tier_rules_equipment_type_code_fkey
    foreign key (equipment_type_code) references public.equipment_types (code) on update restrict on delete restrict,
  constraint equipment_tier_rules_rule_set_type_tier_key unique (rule_set_id, equipment_type_code, tier),
  constraint equipment_tier_rules_tier_check check (tier in ('none', 'beginner', 'intermediate', 'advanced')),
  constraint equipment_tier_rules_purchase_price_nonnegative_check check (purchase_price >= 0),
  constraint equipment_tier_rules_view_bonus_nonnegative_check check (view_bonus >= 0)
);

create table public.feature_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  feature_code text not null,
  unlock_subscribers bigint not null,
  activation_delay_weeks smallint not null,
  is_persistent boolean not null,
  constraint feature_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint feature_rules_feature_code_fkey
    foreign key (feature_code) references public.feature_definitions (code) on update restrict on delete restrict,
  constraint feature_rules_rule_set_feature_key unique (rule_set_id, feature_code),
  constraint feature_rules_unlock_subscribers_nonnegative_check check (unlock_subscribers >= 0),
  constraint feature_rules_activation_delay_weeks_nonnegative_check check (activation_delay_weeks >= 0)
);

create table public.action_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  action_code text not null,
  required_feature_code text,
  cooldown_weeks smallint not null,
  fixed_cash_delta bigint not null,
  energy_delta smallint not null,
  video_view_multiplier numeric not null,
  constraint action_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint action_rules_action_code_fkey
    foreign key (action_code) references public.action_definitions (code) on update restrict on delete restrict,
  constraint action_rules_required_feature_code_fkey
    foreign key (required_feature_code) references public.feature_definitions (code) on update restrict on delete restrict,
  constraint action_rules_rule_set_action_key unique (rule_set_id, action_code),
  constraint action_rules_cooldown_weeks_nonnegative_check check (cooldown_weeks >= 0),
  constraint action_rules_video_view_multiplier_nonnegative_check check (video_view_multiplier >= 0)
);

create table public.sponsorship_reward_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  min_subscribers bigint not null,
  max_subscribers bigint,
  reward_amount bigint not null,
  constraint sponsorship_reward_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint sponsorship_reward_rules_subscriber_range_check
    check (min_subscribers >= 0 and (max_subscribers is null or max_subscribers >= min_subscribers)),
  constraint sponsorship_reward_rules_reward_amount_nonnegative_check check (reward_amount >= 0),
  constraint sponsorship_reward_rules_subscriber_overlap_excl
    exclude using gist (rule_set_id with =, int8range(min_subscribers, max_subscribers, '[]') with &&)
);

create table public.goal_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  stage_number smallint not null,
  target_subscribers bigint not null,
  duration_weeks integer not null,
  is_final boolean not null,
  constraint goal_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint goal_rules_rule_set_stage_key unique (rule_set_id, stage_number),
  constraint goal_rules_stage_number_positive_check check (stage_number > 0),
  constraint goal_rules_target_subscribers_positive_check check (target_subscribers > 0),
  constraint goal_rules_duration_weeks_positive_check check (duration_weeks > 0)
);

create table public.event_category_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  category_code text not null,
  weekly_probability numeric not null,
  constraint event_category_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint event_category_rules_category_code_fkey
    foreign key (category_code) references public.event_categories (code) on update restrict on delete restrict,
  constraint event_category_rules_rule_set_category_key unique (rule_set_id, category_code),
  constraint event_category_rules_weekly_probability_check check (weekly_probability between 0 and 1)
);

alter table public.event_definitions
  add constraint event_definitions_code_category_key unique (code, category_code);

create table public.event_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  event_definition_code text not null,
  category_code text not null,
  selection_weight integer not null,
  weekly_view_multiplier numeric not null,
  fixed_cash_delta bigint not null,
  fixed_subscriber_delta bigint not null,
  subscriber_multiplier numeric not null,
  constraint event_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint event_rules_definition_category_fkey
    foreign key (event_definition_code, category_code)
    references public.event_definitions (code, category_code) on update restrict on delete restrict,
  constraint event_rules_rule_set_category_fkey
    foreign key (rule_set_id, category_code)
    references public.event_category_rules (rule_set_id, category_code) on update restrict on delete restrict,
  constraint event_rules_rule_set_event_key unique (rule_set_id, event_definition_code),
  constraint event_rules_selection_weight_positive_check check (selection_weight > 0),
  constraint event_rules_weekly_view_multiplier_nonnegative_check check (weekly_view_multiplier >= 0),
  constraint event_rules_subscriber_multiplier_nonnegative_check check (subscriber_multiplier >= 0),
  constraint event_rules_effect_direction_check check (
    (
      category_code <> 'good'
      or (
        weekly_view_multiplier >= 1
        and fixed_cash_delta >= 0
        and fixed_subscriber_delta >= 0
        and subscriber_multiplier >= 1
      )
    )
    and (
      category_code <> 'bad'
      or (
        weekly_view_multiplier <= 1
        and fixed_cash_delta <= 0
        and fixed_subscriber_delta <= 0
        and subscriber_multiplier <= 1
      )
    )
  )
);

create table public.health_risk_rules (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  rule_set_id uuid not null,
  min_energy smallint not null,
  max_energy smallint not null,
  occurrence_probability numeric not null,
  min_unavailable_weeks smallint not null,
  max_unavailable_weeks smallint not null,
  constraint health_risk_rules_rule_set_id_fkey
    foreign key (rule_set_id) references public.rule_sets (id) on update restrict on delete restrict,
  constraint health_risk_rules_energy_range_check
    check (min_energy >= 1 and max_energy >= min_energy),
  constraint health_risk_rules_occurrence_probability_check check (occurrence_probability between 0 and 1),
  constraint health_risk_rules_unavailable_week_range_check
    check (min_unavailable_weeks >= 0 and max_unavailable_weeks >= min_unavailable_weeks),
  constraint health_risk_rules_energy_overlap_excl
    exclude using gist (rule_set_id with =, int4range(min_energy, max_energy, '[]') with &&)
);

comment on column public.action_rules.fixed_cash_delta is 'Signed change in yen applied by the action.';
comment on column public.action_rules.energy_delta is 'Signed energy change applied before posting energy cost.';
comment on column public.sponsorship_reward_rules.max_subscribers is 'Inclusive upper bound; NULL represents no upper limit.';
comment on column public.health_risk_rules.min_unavailable_weeks is 'Inclusive minimum unavailable duration in weeks.';
comment on column public.health_risk_rules.max_unavailable_weeks is 'Inclusive maximum unavailable duration in weeks.';

create function public.protect_versioned_rule_row()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_rule_set_id uuid;
  new_rule_set_id uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    old_rule_set_id := old.rule_set_id;

    if not exists (
      select 1 from public.rule_sets
      where id = old_rule_set_id and status = 'draft' and published_at is null
    ) then
      raise exception 'Rules belonging to published rule sets are immutable';
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    new_rule_set_id := new.rule_set_id;

    if not exists (
      select 1 from public.rule_sets
      where id = new_rule_set_id and status = 'draft' and published_at is null
    ) then
      raise exception 'Rules can only be written under draft rule sets';
    end if;

    return new;
  end if;

  return old;
end;
$$;

comment on function public.protect_versioned_rule_row() is
  'Shared trigger guard that allows rule rows to change only while their parent rule set is draft.';

create trigger protect_published_global_rules before insert or update or delete on public.global_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_channel_rules before insert or update or delete on public.channel_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_channel_ability_weights before insert or update or delete on public.channel_ability_weights for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_rule_set_specialties before insert or update or delete on public.rule_set_specialties for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_posting_frequency_rules before insert or update or delete on public.posting_frequency_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_idea_score_band_rules before insert or update or delete on public.idea_score_band_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_equipment_tier_rules before insert or update or delete on public.equipment_tier_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_action_rules before insert or update or delete on public.action_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_sponsorship_reward_rules before insert or update or delete on public.sponsorship_reward_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_feature_rules before insert or update or delete on public.feature_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_goal_rules before insert or update or delete on public.goal_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_event_category_rules before insert or update or delete on public.event_category_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_event_rules before insert or update or delete on public.event_rules for each row execute function public.protect_versioned_rule_row();
create trigger protect_published_health_risk_rules before insert or update or delete on public.health_risk_rules for each row execute function public.protect_versioned_rule_row();

create function public.validate_rule_set_for_publication(target_rule_set_id uuid)
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
    select 1 from public.event_definitions as definition
    where not exists (
      select 1 from public.event_rules
      where rule_set_id = target_rule_set_id and event_definition_code = definition.code
    )
  ) then raise exception 'Rule set must contain all six event rules'; end if;

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
  'Validates the BE-004 rule families before publication. Later rule tickets extend this publication gate.';

create function public.validate_rule_set_before_publish()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'draft' and new.status = 'active' then
    perform public.validate_rule_set_for_publication(new.id);
  end if;

  return new;
end;
$$;

create trigger validate_rule_set_before_publish
before update on public.rule_sets
for each row
execute function public.validate_rule_set_before_publish();
