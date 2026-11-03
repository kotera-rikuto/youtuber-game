begin;

set local search_path = extensions, public, pg_catalog;

select plan(75);

create function pg_temp.create_advance_week_run(
  target_user_id uuid,
  target_run_id uuid,
  target_week integer default 1,
  target_version integer default 0,
  target_subscribers bigint default 0,
  target_energy integer default 100,
  target_cash bigint default 100000,
  target_flame_count integer default 0,
  videos_per_week integer default 1,
  goal_deadline integer default 156,
  include_action boolean default true,
  action_code text default 'part_time_job'
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  frequency_rule_id uuid;
  selected_action_rule_id uuid;
begin
  insert into auth.users (id) values (target_user_id);

  insert into public.game_runs (
    id, user_id, rule_set_id, channel_rule_id, channel_name
  ) values (
    target_run_id,
    target_user_id,
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8100-000000001001',
    'BE-029 test channel'
  );

  select id into frequency_rule_id
  from public.posting_frequency_rules
  where rule_set_id = '00000000-0000-4000-8000-000000000001'
    and posting_frequency_rules.videos_per_week = create_advance_week_run.videos_per_week;

  insert into public.run_state (
    run_id, current_week, posting_frequency_rule_id, cash, energy,
    subscribers, cumulative_views, flame_count, state_version
  ) values (
    target_run_id, target_week, frequency_rule_id, target_cash, target_energy,
    target_subscribers, 0, target_flame_count, target_version
  );

  insert into public.run_abilities (run_id, ability_code, value)
  select target_run_id, code, 10 from public.ability_definitions;

  insert into public.run_goals (
    run_id, goal_rule_id, started_week, deadline_week, status
  ) values (
    target_run_id,
    '00000000-0000-4000-8100-000000001801',
    1,
    goal_deadline,
    'active'
  );

  if include_action then
    select id into selected_action_rule_id
    from public.action_rules
    where rule_set_id = '00000000-0000-4000-8000-000000000001'
      and action_rules.action_code = create_advance_week_run.action_code;

    insert into public.weekly_actions (run_id, week_number, action_rule_id)
    values (
      target_run_id,
      target_week,
      selected_action_rule_id
    );
  end if;
end;
$$;

create function pg_temp.add_player_ideas(target_run_id uuid, idea_count integer)
returns void
language plpgsql
set search_path = ''
as $$
declare
  idea_id uuid;
  item_number integer;
begin
  for item_number in 1..idea_count loop
    idea_id := pg_catalog.gen_random_uuid();
    insert into public.player_ideas (id, run_id, title, created_week)
    values (idea_id, target_run_id, 'Player idea ' || item_number, 1);
    insert into public.idea_evaluations (
      idea_id, score, evaluation_status, model, prompt_version
    ) values (idea_id, 60, 'completed', 'test-model', 'be029');
    insert into public.idea_queue_entries (idea_id, run_id, position)
    values (idea_id, target_run_id, item_number);
  end loop;
end;
$$;

create function pg_temp.add_system_idea_entries(target_run_id uuid, entry_count integer)
returns void
language plpgsql
set search_path = ''
as $$
declare
  cycle_id uuid := pg_catalog.gen_random_uuid();
begin
  insert into public.system_idea_cycles (id, run_id, cycle_number, created_week)
  values (cycle_id, target_run_id, 1, 1);

  insert into public.system_idea_cycle_entries (
    cycle_id, rule_set_system_idea_id, position
  )
  select cycle_id, association.id, row_number() over (order by template.code)
  from public.rule_set_system_ideas as association
  join public.system_idea_templates as template
    on template.id = association.system_idea_template_id
  where association.rule_set_id = '00000000-0000-4000-8000-000000000001'
    and association.enabled
    and template.enabled
    and template.channel_type_code = 'mainstream'
  order by template.code
  limit entry_count;
end;
$$;

create function pg_temp.make_normal_command(
  target_user_id uuid,
  target_run_id uuid,
  target_idempotency_key uuid,
  random_event_code text default null,
  has_flame boolean default false,
  health_duration integer default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  state public.run_state%rowtype;
  frequency public.posting_frequency_rules%rowtype;
  action public.weekly_actions%rowtype;
  action_rule public.action_rules%rowtype;
  global_rule public.global_rules%rowtype;
  random_rule public.event_rules%rowtype;
  health_rule_id uuid;
  videos jsonb;
  events jsonb := '[]'::jsonb;
  feature_ids jsonb;
  player_count integer;
  total_before bigint;
  total_final bigint;
  subscriber_gain bigint;
  subscriber_after_videos bigint;
  subscriber_after_event bigint;
  final_subscribers bigint;
  cash_before_event bigint;
  final_cash bigint;
  energy_before_flame integer;
  final_energy integer;
  final_flame_count integer;
  max_subscribers bigint;
  sponsorship_reward bigint := 0;
  expected_ad_revenue bigint;
  event_multiplier numeric := 1;
  goal_result text;
begin
  select * into state from public.run_state where run_id = target_run_id;
  select * into frequency from public.posting_frequency_rules
  where id = state.posting_frequency_rule_id;
  select * into action from public.weekly_actions
  where run_id = target_run_id and week_number = state.current_week;
  select * into action_rule from public.action_rules where id = action.action_rule_id;
  select * into global_rule from public.global_rules
  where rule_set_id = '00000000-0000-4000-8000-000000000001';

  select count(*)::integer into player_count
  from public.idea_queue_entries where run_id = target_run_id;
  player_count := least(player_count, frequency.videos_per_week);

  if random_event_code is not null then
    select * into random_rule from public.event_rules
    where rule_set_id = '00000000-0000-4000-8000-000000000001'
      and event_definition_code = random_event_code;
    event_multiplier := random_rule.weekly_view_multiplier;
  end if;

  with player_sources as (
    select
      row_number() over (order by queue.position)::integer as sequence_number,
      'player'::text as source,
      idea.id as player_idea_id,
      null::uuid as system_entry_id,
      idea.title,
      band.view_multiplier as idea_multiplier,
      band.subscriber_conversion_rate as conversion_rate
    from public.idea_queue_entries as queue
    join public.player_ideas as idea on idea.id = queue.idea_id
    join public.idea_evaluations as evaluation on evaluation.idea_id = idea.id
    join public.idea_score_band_rules as band
      on band.rule_set_id = '00000000-0000-4000-8000-000000000001'
     and evaluation.score between band.min_score and band.max_score
    where queue.run_id = target_run_id
    order by queue.position
    limit frequency.videos_per_week
  ),
  system_sources as (
    select
      player_count + row_number() over (
        order by cycle.cycle_number, entry.position
      )::integer as sequence_number,
      'system'::text as source,
      null::uuid as player_idea_id,
      entry.id as system_entry_id,
      template.title,
      global_rule.system_idea_view_multiplier as idea_multiplier,
      global_rule.system_idea_subscriber_conversion_rate as conversion_rate
    from public.system_idea_cycle_entries as entry
    join public.system_idea_cycles as cycle on cycle.id = entry.cycle_id
    join public.rule_set_system_ideas as association
      on association.id = entry.rule_set_system_idea_id
    join public.system_idea_templates as template
      on template.id = association.system_idea_template_id
    where cycle.run_id = target_run_id
    order by cycle.cycle_number, entry.position
    limit frequency.videos_per_week - player_count
  ),
  sources as (
    select * from player_sources
    union all
    select * from system_sources
  ),
  calculated as (
    select *, floor(
      100::numeric
      * (1 + floor(state.subscribers::numeric / 100000) * 0.5)
      * 1
      * idea_multiplier
      * frequency.view_multiplier
      * 1
      * 1
      * action_rule.video_view_multiplier
    )::bigint as views_before
    from sources
  ),
  totals as (
    select sum(views_before)::bigint as before_total from calculated
  ),
  allocated as (
    select calculated.*,
      floor((totals.before_total * event_multiplier) / frequency.videos_per_week)::bigint
      + case when sequence_number <= mod(
          floor(totals.before_total * event_multiplier)::bigint,
          frequency.videos_per_week
        ) then 1 else 0 end as final_video_views
    from calculated cross join totals
  )
  select
    jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'sequenceNumber', sequence_number,
        'source', source,
        'playerIdeaId', player_idea_id,
        'systemIdeaCycleEntryId', system_entry_id,
        'titleSnapshot', title,
        'calculation', jsonb_build_object(
          'baseViews', 100,
          'subscriberMultiplier', 1 + floor(state.subscribers::numeric / 100000) * 0.5,
          'abilityMultiplier', 1,
          'ideaMultiplier', idea_multiplier,
          'postingFrequencyMultiplier', frequency.view_multiplier,
          'channelMultiplier', 1,
          'equipmentMultiplier', 1,
          'collaborationMultiplier', action_rule.video_view_multiplier,
          'viewsBeforeEvent', views_before,
          'eventMultiplier', event_multiplier,
          'finalViews', final_video_views,
          'conversionRate', conversion_rate,
          'subscribersGained', floor(final_video_views * conversion_rate)::bigint
        )
      )) order by sequence_number
    ),
    sum(views_before)::bigint,
    sum(final_video_views)::bigint,
    sum(floor(final_video_views * conversion_rate))::bigint
  into videos, total_before, total_final, subscriber_gain
  from allocated;

  subscriber_after_videos := state.subscribers + subscriber_gain;
  subscriber_after_event := subscriber_after_videos;
  if action_rule.action_code = 'sponsorship' then
    select reward_amount into sponsorship_reward
    from public.sponsorship_reward_rules as reward_rule
    where reward_rule.rule_set_id = '00000000-0000-4000-8000-000000000001'
      and state.subscribers >= reward_rule.min_subscribers
      and (
        reward_rule.max_subscribers is null
        or state.subscribers <= reward_rule.max_subscribers
      );
  end if;

  expected_ad_revenue := case
    when exists (
      select 1
      from public.run_feature_unlocks as unlock
      join public.feature_rules as feature on feature.id = unlock.feature_rule_id
      where unlock.run_id = target_run_id
        and feature.feature_code = 'ad_revenue'
        and unlock.active_from_week <= state.current_week
    ) then floor(total_final * global_rule.ad_revenue_per_view)::bigint
    else 0
  end;

  cash_before_event := greatest(
    0,
    state.cash + action_rule.fixed_cash_delta + sponsorship_reward
  ) + expected_ad_revenue;
  final_cash := cash_before_event;

  if random_event_code is not null then
    subscriber_after_event := greatest(
      0,
      floor(subscriber_after_videos * random_rule.subscriber_multiplier)::bigint
        + random_rule.fixed_subscriber_delta
    );
    final_cash := greatest(0, cash_before_event + random_rule.fixed_cash_delta);
    events := events || jsonb_build_array(jsonb_build_object(
      'kind', 'random',
      'eventRuleId', random_rule.id,
      'cashBefore', cash_before_event,
      'cashAfter', final_cash,
      'subscribersBefore', subscriber_after_videos,
      'subscribersAfter', subscriber_after_event
    ));
  end if;

  energy_before_flame := case
    when action_rule.energy_delta > 0 then least(
      global_rule.energy_max,
      state.energy + action_rule.energy_delta
    )
    else state.energy + action_rule.energy_delta
  end - frequency.energy_cost;
  final_energy := energy_before_flame;
  final_subscribers := subscriber_after_event;
  final_flame_count := state.flame_count;

  if has_flame then
    final_subscribers := floor(
      subscriber_after_event * (1 - global_rule.flame_subscriber_loss_rate)
    )::bigint;
    final_energy := energy_before_flame - global_rule.flame_energy_loss;
    final_flame_count := state.flame_count + 1;
    events := events || jsonb_build_array(jsonb_build_object(
      'kind', 'flame',
      'subscribersBefore', subscriber_after_event,
      'subscribersAfter', final_subscribers,
      'energyBefore', energy_before_flame,
      'energyAfter', final_energy,
      'flameCountBefore', state.flame_count,
      'flameCountAfter', final_flame_count
    ));
  end if;

  max_subscribers := greatest(
    state.subscribers,
    subscriber_after_videos,
    subscriber_after_event,
    final_subscribers
  );

  select coalesce(jsonb_agg(id order by id), '[]'::jsonb)
  into feature_ids
  from public.feature_rules as feature
  where feature.rule_set_id = '00000000-0000-4000-8000-000000000001'
    and feature.unlock_subscribers <= max_subscribers
    and not exists (
      select 1 from public.run_feature_unlocks as unlock
      where unlock.run_id = target_run_id and unlock.feature_rule_id = feature.id
    );

  if final_subscribers >= 100000 then
    goal_result := 'achieved';
  elsif state.current_week >= (
    select deadline_week from public.run_goals
    where run_id = target_run_id and status = 'active'
  ) then
    goal_result := 'deadline';
  else
    goal_result := 'active';
  end if;

  if health_duration is not null then
    select id into health_rule_id
    from public.health_risk_rules
    where rule_set_id = '00000000-0000-4000-8000-000000000001'
      and final_energy between min_energy and max_energy;
  end if;

  return jsonb_build_object(
    'kind', 'normal',
    'actorUserId', target_user_id,
    'runId', target_run_id,
    'attemptedWeek', state.current_week,
    'expectedVersion', state.state_version,
    'idempotencyKey', target_idempotency_key,
    'weeklyActionId', action.id,
    'postingFrequencyRuleId', frequency.id,
    'weekResult', jsonb_build_object(
      'viewsBeforeEvent', total_before,
      'finalViews', total_final,
      'subscribersBefore', state.subscribers,
      'maxSubscribersDuringWeek', max_subscribers,
      'subscribersAfter', final_subscribers,
      'energyBefore', state.energy,
      'energyAfter', final_energy,
      'cashBefore', state.cash,
      'cashAfter', final_cash,
      'adRevenue', expected_ad_revenue,
      'flameCountAfter', final_flame_count
    ),
    'stateAfter', jsonb_build_object(
      'cash', final_cash,
      'energy', final_energy,
      'subscribers', final_subscribers,
      'cumulativeViews', state.cumulative_views + total_final,
      'flameCount', final_flame_count
    ),
    'videos', videos,
    'events', events,
    'featureUnlockRuleIds', feature_ids,
    'healthCondition', case when health_duration is null then 'null'::jsonb else
      jsonb_build_object('healthRiskRuleId', health_rule_id, 'durationWeeks', health_duration)
    end,
    'abilityPointsAwarded', frequency.ability_points_awarded,
    'abilityPointGrantStatus', case when health_duration is null then 'available' else 'held' end,
    'goalOutcome', goal_result
  );
end;
$$;

create function pg_temp.make_unavailable_command(
  target_user_id uuid,
  target_run_id uuid,
  target_idempotency_key uuid
)
returns jsonb
language sql
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'kind', 'activity_unavailable',
    'actorUserId', target_user_id,
    'runId', target_run_id,
    'attemptedWeek', state.current_week,
    'expectedVersion', state.state_version,
    'idempotencyKey', target_idempotency_key,
    'weekResult', pg_catalog.jsonb_build_object(
      'viewsBeforeEvent', 0,
      'finalViews', 0,
      'subscribersBefore', state.subscribers,
      'maxSubscribersDuringWeek', state.subscribers,
      'subscribersAfter', state.subscribers,
      'energyBefore', state.energy,
      'energyAfter', least(global_rule.energy_max, state.energy + global_rule.unavailable_energy_recovery),
      'cashBefore', state.cash,
      'cashAfter', state.cash,
      'adRevenue', 0,
      'flameCountAfter', state.flame_count
    ),
    'stateAfter', pg_catalog.jsonb_build_object(
      'cash', state.cash,
      'energy', least(global_rule.energy_max, state.energy + global_rule.unavailable_energy_recovery),
      'subscribers', state.subscribers,
      'cumulativeViews', state.cumulative_views,
      'flameCount', state.flame_count
    ),
    'goalOutcome', case
      when state.subscribers >= goal_rule.target_subscribers then 'achieved'
      when state.current_week >= goal.deadline_week then 'deadline'
      else 'active'
    end
  )
  from public.run_state as state
  join public.game_runs as game_run on game_run.id = state.run_id
  join public.global_rules as global_rule on global_rule.rule_set_id = game_run.rule_set_id
  join public.run_goals as goal on goal.run_id = state.run_id and goal.status = 'active'
  join public.goal_rules as goal_rule on goal_rule.id = goal.goal_rule_id
  where state.run_id = target_run_id;
$$;

create function pg_temp.set_week_and_state_value(
  command jsonb,
  week_result_field text,
  state_field text,
  replacement bigint
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(
      command,
      array['weekResult', week_result_field],
      pg_catalog.to_jsonb(replacement)
    ),
    array['stateAfter', state_field],
    pg_catalog.to_jsonb(replacement)
  );
$$;

select has_function(
  'public',
  'commit_advance_week',
  array['jsonb'],
  'commit_advance_week(jsonb) exists'
);

select function_returns(
  'public',
  'commit_advance_week',
  array['jsonb'],
  'jsonb',
  'commit_advance_week returns a typed JSON receipt'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as function_row
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_row.proacl,
        pg_catalog.acldefault('f', function_row.proowner)
      )
    ) as privilege
    where function_row.oid = 'public.commit_advance_week(jsonb)'::regprocedure
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute commit_advance_week'
);
select ok(
  not has_function_privilege('anon', 'public.commit_advance_week(jsonb)', 'EXECUTE'),
  'anon cannot execute commit_advance_week'
);
select ok(
  not has_function_privilege('authenticated', 'public.commit_advance_week(jsonb)', 'EXECUTE'),
  'authenticated cannot execute commit_advance_week'
);
select ok(
  has_function_privilege('service_role', 'public.commit_advance_week(jsonb)', 'EXECUTE'),
  'service_role can execute commit_advance_week'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000001',
  'b2900000-0000-4000-8000-000000000001'
);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000001', 1);

select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000001',
    'b2900000-0000-4000-8000-000000000001',
    'c2900000-0000-4000-8000-000000000001'
  ))$$,
  'a normal one-video week commits atomically'
);
select is(
  (select count(*)::integer from public.videos where week_result_id = (
    select id from public.week_results where run_id = 'b2900000-0000-4000-8000-000000000001'
  )),
  1,
  'one video is stored'
);
select is(
  (select count(*)::integer from public.video_calculations where video_id in (
    select id from public.videos where week_result_id = (
      select id from public.week_results where run_id = 'b2900000-0000-4000-8000-000000000001'
    )
  )),
  1,
  'the video calculation snapshot is stored'
);
select is(
  (select count(*)::integer from public.idea_queue_entries where run_id = 'b2900000-0000-4000-8000-000000000001'),
  0,
  'the consumed queue head is removed'
);
select ok(
  (select locked_at is not null from public.weekly_actions where run_id = 'b2900000-0000-4000-8000-000000000001'),
  'the weekly action is locked'
);
select is(
  (select jsonb_build_array(current_week, state_version, cumulative_views)
   from public.run_state where run_id = 'b2900000-0000-4000-8000-000000000001'),
  '[2,1,120]'::jsonb,
  'current week and state version advance exactly once'
);
select is(
  (select amount from public.ability_point_grants where run_id = 'b2900000-0000-4000-8000-000000000001'),
  3::smallint,
  'the next-week ability points are awarded'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000003',
  'b2900000-0000-4000-8000-000000000003',
  videos_per_week => 3
);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000003', 3);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000003',
    'b2900000-0000-4000-8000-000000000003',
    'c2900000-0000-4000-8000-000000000003'
  ))$$,
  'a three-video week commits'
);
select is(
  (select count(*)::integer from public.videos join public.week_results on week_results.id = videos.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000003'),
  3,
  'three videos are stored'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000007',
  'b2900000-0000-4000-8000-000000000007',
  videos_per_week => 7
);
select pg_temp.add_system_idea_entries('b2900000-0000-4000-8000-000000000007', 7);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000007',
    'b2900000-0000-4000-8000-000000000007',
    'c2900000-0000-4000-8000-000000000007'
  ))$$,
  'a seven-video system-idea week commits'
);
select is(
  (select count(*)::integer from public.videos join public.week_results on week_results.id = videos.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000007'),
  7,
  'seven system idea entries are used once'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000010', 'b2900000-0000-4000-8000-000000000010');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000010', 1);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000010','b2900000-0000-4000-8000-000000000010','c2900000-0000-4000-8000-000000000010','featured_in_recommendations',false,null))$$,
  'a random-event-only week commits'
);
select is(
  (select count(*)::integer from public.occurred_events join public.week_results on week_results.id = occurred_events.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000010'),
  1,
  'one random event is stored'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000011', 'b2900000-0000-4000-8000-000000000011');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000011', 1);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000011','b2900000-0000-4000-8000-000000000011','c2900000-0000-4000-8000-000000000011',null,true,null))$$,
  'a flame-only week commits'
);
select is(
  (select event_definition_code from public.occurred_events join public.week_results on week_results.id = occurred_events.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000011'),
  'flame',
  'flame is stored without a random-event rule'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000012', 'b2900000-0000-4000-8000-000000000012');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000012', 1);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000012','b2900000-0000-4000-8000-000000000012','c2900000-0000-4000-8000-000000000012','temporary_bonus',true,null))$$,
  'random event and flame can coexist'
);
select is(
  (select count(*)::integer from public.occurred_events join public.week_results on week_results.id = occurred_events.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000012'),
  2,
  'both independent events are stored'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000013',
  'b2900000-0000-4000-8000-000000000013',
  target_subscribers => 99997
);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000013', 1);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000013','b2900000-0000-4000-8000-000000000013','c2900000-0000-4000-8000-000000000013'))$$,
  'a goal-achieving and feature-unlocking week commits'
);
select is(
  (select count(*)::integer from public.run_feature_unlocks where run_id = 'b2900000-0000-4000-8000-000000000013'),
  3,
  'all newly reached features are unlocked'
);
select is(
  (select status from public.game_runs where id = 'b2900000-0000-4000-8000-000000000013'),
  'stage_cleared',
  'the achieved non-final stage is marked cleared'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000014',
  'b2900000-0000-4000-8000-000000000014',
  target_week => 2,
  target_energy => 50
);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000014', 1);
insert into public.ability_point_grants (run_id, earned_week, available_from_week, amount, status)
values ('b2900000-0000-4000-8000-000000000014', 1, 2, 5, 'available');
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000014','b2900000-0000-4000-8000-000000000014','c2900000-0000-4000-8000-000000000014',null,false,1))$$,
  'a health condition and ability-point replacement commit together'
);
select is(
  (select duration_weeks from public.run_conditions where run_id = 'b2900000-0000-4000-8000-000000000014'),
  1::smallint,
  'the computed health condition is stored'
);
select is(
  (select status from public.ability_point_grants where run_id = 'b2900000-0000-4000-8000-000000000014' and earned_week = 1),
  'expired',
  'the unused prior ability grant expires'
);
select is(
  (select status from public.ability_point_grants where run_id = 'b2900000-0000-4000-8000-000000000014' and earned_week = 2),
  'held',
  'new points are held while the next week is unavailable'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000015',
  'b2900000-0000-4000-8000-000000000015',
  goal_deadline => 1
);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000015', 1);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000015','b2900000-0000-4000-8000-000000000015','c2900000-0000-4000-8000-000000000015'))$$,
  'an unmet final deadline commits the week before game over'
);
select is(
  (select reason from public.game_terminations where run_id = 'b2900000-0000-4000-8000-000000000015'),
  'deadline',
  'deadline termination references the committed week'
);
select is(
  (select count(*)::integer from public.week_results where run_id = 'b2900000-0000-4000-8000-000000000015'),
  1,
  'deadline game over retains the final normal week result'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000016',
  'b2900000-0000-4000-8000-000000000016',
  target_subscribers => 99997,
  goal_deadline => 1
);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000016', 1);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000016','b2900000-0000-4000-8000-000000000016','c2900000-0000-4000-8000-000000000016'))$$,
  'the final deadline week may still achieve the goal'
);
select is(
  (select count(*)::integer from public.game_terminations where run_id = 'b2900000-0000-4000-8000-000000000016'),
  0,
  'a deadline-week achievement is not terminated'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000017',
  'b2900000-0000-4000-8000-000000000017',
  target_week => 2,
  target_energy => 40,
  include_action => false
);
insert into public.run_conditions (
  run_id, health_risk_rule_id, started_week, duration_weeks,
  unavailable_from_week, unavailable_through_week
) values (
  'b2900000-0000-4000-8000-000000000017',
  '00000000-0000-4000-8100-000000002102',
  1, 1, 2, 2
);
insert into public.ability_point_grants (run_id, earned_week, available_from_week, amount, status)
values ('b2900000-0000-4000-8000-000000000017', 1, 2, 3, 'held');
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_unavailable_command('a2900000-0000-4000-8000-000000000017','b2900000-0000-4000-8000-000000000017','c2900000-0000-4000-8000-000000000017'))$$,
  'an activity-unavailable recovery week commits'
);
select is(
  (select jsonb_build_array(current_week, energy, state_version) from public.run_state where run_id = 'b2900000-0000-4000-8000-000000000017'),
  '[3,50,1]'::jsonb,
  'an unavailable week only recovers energy and advances state'
);
select is(
  (select count(*)::integer from public.videos join public.week_results on week_results.id = videos.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000017'),
  0,
  'an unavailable week stores no videos'
);
select is(
  (select status from public.ability_point_grants where run_id = 'b2900000-0000-4000-8000-000000000017'),
  'available',
  'held points become available when recovery completes'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000020', 'b2900000-0000-4000-8000-000000000020');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000020', 1);
select lives_ok(
  $$select public.commit_advance_week(jsonb_build_object(
    'kind','fatal_game_over','actorUserId','a2900000-0000-4000-8000-000000000020',
    'runId','b2900000-0000-4000-8000-000000000020','attemptedWeek',1,
    'expectedVersion',0,'idempotencyKey','c2900000-0000-4000-8000-000000000020',
    'reason','death','calculatedEnergy',0,'calculatedFlameCount',0
  ))$$,
  'death commits only a fatal termination'
);
select is(
  (select count(*)::integer from public.week_results where run_id = 'b2900000-0000-4000-8000-000000000020'),
  0,
  'death stores no normal week result'
);
select is(
  (select jsonb_build_array(current_week,cash,energy,subscribers,state_version) from public.run_state where run_id = 'b2900000-0000-4000-8000-000000000020'),
  '[1,100000,100,0,0]'::jsonb,
  'death leaves run state unchanged'
);
select ok(
  (select locked_at is null from public.weekly_actions where run_id = 'b2900000-0000-4000-8000-000000000020'),
  'death does not lock or apply the weekly action'
);
select is(
  (select count(*)::integer from public.idea_queue_entries where run_id = 'b2900000-0000-4000-8000-000000000020'),
  1,
  'death does not consume ideas'
);
select is(
  (select jsonb_build_array(
    (select count(*) from public.run_feature_unlocks where run_id = 'b2900000-0000-4000-8000-000000000020'),
    (select count(*) from public.ability_point_grants where run_id = 'b2900000-0000-4000-8000-000000000020'),
    (select count(*) from public.run_conditions where run_id = 'b2900000-0000-4000-8000-000000000020')
  )),
  '[0,0,0]'::jsonb,
  'death does not add unlocks, ability points, or health conditions'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000021', 'b2900000-0000-4000-8000-000000000021', target_flame_count => 2);
select lives_ok(
  $$select public.commit_advance_week(jsonb_build_object(
    'kind','fatal_game_over','actorUserId','a2900000-0000-4000-8000-000000000021',
    'runId','b2900000-0000-4000-8000-000000000021','attemptedWeek',1,
    'expectedVersion',0,'idempotencyKey','c2900000-0000-4000-8000-000000000021',
    'reason','flame_ban','calculatedEnergy',50,'calculatedFlameCount',3
  ))$$,
  'the third flame commits a ban'
);
select is(
  (select reason from public.game_terminations where run_id = 'b2900000-0000-4000-8000-000000000021'),
  'flame_ban',
  'flame ban is the stored fatal reason'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000022', 'b2900000-0000-4000-8000-000000000022', target_flame_count => 2);
select lives_ok(
  $$select public.commit_advance_week(jsonb_build_object(
    'kind','fatal_game_over','actorUserId','a2900000-0000-4000-8000-000000000022',
    'runId','b2900000-0000-4000-8000-000000000022','attemptedWeek',1,
    'expectedVersion',0,'idempotencyKey','c2900000-0000-4000-8000-000000000022',
    'reason','flame_ban','calculatedEnergy',0,'calculatedFlameCount',3
  ))$$,
  'simultaneous death and third flame commit successfully'
);
select is(
  (select reason from public.game_terminations where run_id = 'b2900000-0000-4000-8000-000000000022'),
  'flame_ban',
  'ban takes priority over simultaneous death'
);

select is(
  public.commit_advance_week(jsonb_build_object(
    'kind','fatal_game_over','actorUserId','a2900000-0000-4000-8000-000000000022',
    'runId','b2900000-0000-4000-8000-000000000022','attemptedWeek',1,
    'expectedVersion',0,'idempotencyKey','c2900000-0000-4000-8000-000000000022',
    'reason','flame_ban','calculatedEnergy',0,'calculatedFlameCount',3
  )),
  public.get_advance_week_receipt('c2900000-0000-4000-8000-000000000022'),
  'an idempotent retry returns the original receipt'
);
select is(
  (select count(*)::integer from public.game_terminations where run_id = 'b2900000-0000-4000-8000-000000000022'),
  1,
  'an idempotent retry adds no side effect'
);

select throws_ok(
  $$select public.commit_advance_week(jsonb_build_object(
    'kind','fatal_game_over','actorUserId','a2900000-0000-4000-8000-000000000022',
    'runId','b2900000-0000-4000-8000-000000000022','attemptedWeek',1,
    'expectedVersion',1,'idempotencyKey','c2900000-0000-4000-8000-000000000022',
    'reason','flame_ban','calculatedEnergy',0,'calculatedFlameCount',3
  ))$$,
  'P0001', 'ADVANCE_WEEK_IDEMPOTENCY_KEY_REUSED',
  'reusing a key with different conditions is rejected'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000023', 'b2900000-0000-4000-8000-000000000023', target_version => 2);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000023', 1);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000023','b2900000-0000-4000-8000-000000000023','c2900000-0000-4000-8000-000000000023'),
    '{expectedVersion}','1'
  ))$$,
  'P0001', 'ADVANCE_WEEK_STALE_STATE',
  'a stale state version is rejected'
);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000023','b2900000-0000-4000-8000-000000000023','c2900000-0000-4000-8000-000000000024'),
    '{actorUserId}','"a2900000-0000-4000-8000-000000000001"'
  ))$$,
  'P0001', 'ADVANCE_WEEK_FORBIDDEN',
  'another user cannot commit the run'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000024', 'b2900000-0000-4000-8000-000000000024');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000024', 1);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000024','b2900000-0000-4000-8000-000000000024','c2900000-0000-4000-8000-000000000025'),
    '{videos,0,calculation,viewsBeforeEvent}','999'
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'an inconsistent video calculation is rejected'
);
select is(
  (select count(*)::integer from public.advance_week_executions where run_id = 'b2900000-0000-4000-8000-000000000024'),
  0,
  'a mid-command validation failure leaves no execution row'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000025', 'b2900000-0000-4000-8000-000000000025', videos_per_week => 3);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000025', 3);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000025','b2900000-0000-4000-8000-000000000025','c2900000-0000-4000-8000-000000000026'),
    '{videos,1,sequenceNumber}','1'
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'duplicate non-contiguous video sequence numbers are rejected'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000028', 'b2900000-0000-4000-8000-000000000028', videos_per_week => 3);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000028', 3);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    command,
    '{videos}',
    (command -> 'videos') - 2
  )) from (select pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000028',
    'b2900000-0000-4000-8000-000000000028',
    'c2900000-0000-4000-8000-000000000030'
  ) as command) as prepared$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'a video count that differs from the posting frequency is rejected'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000026', 'b2900000-0000-4000-8000-000000000026');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000026', 2);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000026','b2900000-0000-4000-8000-000000000026','c2900000-0000-4000-8000-000000000027'),
    '{videos,0,playerIdeaId}',
    to_jsonb((select idea_id from public.idea_queue_entries where run_id = 'b2900000-0000-4000-8000-000000000026' order by position desc limit 1))
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'a player idea outside queue-head order is rejected'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000027', 'b2900000-0000-4000-8000-000000000027');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000027', 1);
select lives_ok(
  $$select public.commit_advance_week(pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000027','b2900000-0000-4000-8000-000000000027','c2900000-0000-4000-8000-000000000028'))$$,
  'the first key commits a week'
);
select throws_ok(
  $$select public.commit_advance_week(jsonb_build_object(
    'kind','fatal_game_over','actorUserId','a2900000-0000-4000-8000-000000000027',
    'runId','b2900000-0000-4000-8000-000000000027','attemptedWeek',1,
    'expectedVersion',0,'idempotencyKey','c2900000-0000-4000-8000-000000000029',
    'reason','death','calculatedEnergy',0,'calculatedFlameCount',0
  ))$$,
  'P0001', 'ADVANCE_WEEK_WEEK_ALREADY_COMMITTED',
  'a different key cannot commit the same week twice'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000101', 'b2900000-0000-4000-8000-000000000101');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000101', 1);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.set_week_and_state_value(
      pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000101','b2900000-0000-4000-8000-000000000101','c2900000-0000-4000-8000-000000000101'),
      'subscribersAfter', 'subscribers', 4
    ),
    '{weekResult,maxSubscribersDuringWeek}', '4'
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'subscribersAfter must equal the sum of validated video subscriber gains'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000102', 'b2900000-0000-4000-8000-000000000102');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000102', 1);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000102','b2900000-0000-4000-8000-000000000102','c2900000-0000-4000-8000-000000000102'),
    '{weekResult,maxSubscribersDuringWeek}', '1000'
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'maxSubscribersDuringWeek cannot exceed the actual weekly checkpoints'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000103', 'b2900000-0000-4000-8000-000000000103');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000103', 1);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    jsonb_set(
      pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000103','b2900000-0000-4000-8000-000000000103','c2900000-0000-4000-8000-000000000103'),
      '{weekResult,maxSubscribersDuringWeek}', '3000'
    ),
    '{featureUnlockRuleIds}',
    to_jsonb(array['00000000-0000-4000-8100-000000001501'::uuid])
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'a fabricated weekly maximum cannot unlock a feature early'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000104', 'b2900000-0000-4000-8000-000000000104');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000104', 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000104','b2900000-0000-4000-8000-000000000104','c2900000-0000-4000-8000-000000000104'),
    'cashAfter', 'cash', 100000
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'cashAfter must include the main action cash delta'
);

select pg_temp.create_advance_week_run(
  'a2900000-0000-4000-8000-000000000105',
  'b2900000-0000-4000-8000-000000000105',
  target_subscribers => 100000,
  action_code => 'sponsorship'
);
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000105', 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000105','b2900000-0000-4000-8000-000000000105','c2900000-0000-4000-8000-000000000105'),
    'cashAfter', 'cash', 100000
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'cashAfter must include the sponsorship reward resolved from week-start subscribers'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000106', 'b2900000-0000-4000-8000-000000000106');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000106', 1);
insert into public.run_feature_unlocks (run_id, feature_rule_id, unlocked_week, active_from_week)
values ('b2900000-0000-4000-8000-000000000106', '00000000-0000-4000-8100-000000001501', 1, 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000106','b2900000-0000-4000-8000-000000000106','c2900000-0000-4000-8000-000000000106'),
    'cashAfter', 'cash', 110000
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'cashAfter must include validated advertising revenue'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000107', 'b2900000-0000-4000-8000-000000000107');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000107', 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    jsonb_set(
      jsonb_set(command, '{events,0,cashBefore}', '110001'),
      '{events,0,cashAfter}', '160001'
    ),
    'cashAfter', 'cash', 160001
  )) from (select pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000107',
    'b2900000-0000-4000-8000-000000000107',
    'c2900000-0000-4000-8000-000000000107',
    'temporary_bonus'
  ) as command) as prepared$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'random-event cashBefore must connect to action cash and advertising revenue'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000108', 'b2900000-0000-4000-8000-000000000108');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000108', 1);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.set_week_and_state_value(
      jsonb_set(
        jsonb_set(command, '{events,0,subscribersBefore}', '4'),
        '{events,0,subscribersAfter}', '5004'
      ),
      'subscribersAfter', 'subscribers', 5004
    ),
    '{weekResult,maxSubscribersDuringWeek}', '5004'
  )) from (select pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000108',
    'b2900000-0000-4000-8000-000000000108',
    'c2900000-0000-4000-8000-000000000108',
    'introduced_by_celebrity'
  ) as command) as prepared$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'random-event subscribersBefore must equal subscribers after videos'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000109', 'b2900000-0000-4000-8000-000000000109');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000109', 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000109','b2900000-0000-4000-8000-000000000109','c2900000-0000-4000-8000-000000000109'),
    'energyAfter', 'energy', 97
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'energyAfter must include the main action energy delta'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000110', 'b2900000-0000-4000-8000-000000000110');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000110', 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000110','b2900000-0000-4000-8000-000000000110','c2900000-0000-4000-8000-000000000110'),
    'energyAfter', 'energy', 90
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'energyAfter must include posting-frequency energy cost'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000111', 'b2900000-0000-4000-8000-000000000111');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000111', 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    jsonb_set(
      jsonb_set(command, '{events,0,energyBefore}', '88'),
      '{events,0,energyAfter}', '68'
    ),
    'energyAfter', 'energy', 68
  )) from (select pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000111',
    'b2900000-0000-4000-8000-000000000111',
    'c2900000-0000-4000-8000-000000000111',
    null, true
  ) as command) as prepared$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'flame energyBefore must connect to action and posting energy changes'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000112', 'b2900000-0000-4000-8000-000000000112');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000112', 1);
select throws_ok(
  $$select public.commit_advance_week(jsonb_set(
    pg_temp.set_week_and_state_value(
      jsonb_set(
        jsonb_set(command, '{events,0,subscribersBefore}', '4'),
        '{events,0,subscribersAfter}', '3'
      ),
      'subscribersAfter', 'subscribers', 3
    ),
    '{weekResult,maxSubscribersDuringWeek}', '4'
  )) from (select pg_temp.make_normal_command(
    'a2900000-0000-4000-8000-000000000112',
    'b2900000-0000-4000-8000-000000000112',
    'c2900000-0000-4000-8000-000000000112',
    null, true
  ) as command) as prepared$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'flame subscribersBefore must connect to subscribers after prior effects'
);

select pg_temp.create_advance_week_run('a2900000-0000-4000-8000-000000000113', 'b2900000-0000-4000-8000-000000000113');
select pg_temp.add_player_ideas('b2900000-0000-4000-8000-000000000113', 1);
select throws_ok(
  $$select public.commit_advance_week(pg_temp.set_week_and_state_value(
    pg_temp.make_normal_command('a2900000-0000-4000-8000-000000000113','b2900000-0000-4000-8000-000000000113','c2900000-0000-4000-8000-000000000113'),
    'cashAfter', 'cash', 100000
  ))$$,
  'P0001', 'ADVANCE_WEEK_VALIDATION_ERROR',
  'a tampered weekly aggregate rejects the complete command'
);
select is(
  (select jsonb_build_array(
    (select count(*) from public.advance_week_executions where run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select count(*) from public.week_results where run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select count(*) from public.videos join public.week_results on week_results.id = videos.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select count(*) from public.occurred_events join public.week_results on week_results.id = occurred_events.week_result_id where week_results.run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select count(*) from public.idea_queue_entries where run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select jsonb_build_array(current_week, cash, energy, subscribers, state_version) from public.run_state where run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select locked_at is null from public.weekly_actions where run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select count(*) from public.run_feature_unlocks where run_id = 'b2900000-0000-4000-8000-000000000113'),
    (select count(*) from public.ability_point_grants where run_id = 'b2900000-0000-4000-8000-000000000113')
  )),
  '[0,0,0,0,1,[1,100000,100,0,0],true,0,0]'::jsonb,
  'tamper rejection rolls back every BE-029 side effect'
);

select * from finish();

rollback;
