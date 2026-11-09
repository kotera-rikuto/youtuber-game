create function public.purchase_equipment(
  p_actor_user_id uuid,
  p_run_id uuid,
  p_equipment_type text,
  p_level text,
  p_expected_version integer
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  locked_state public.run_state%rowtype;
  locked_run public.game_runs%rowtype;
  current_equipment public.run_equipment%rowtype;
  current_rule public.equipment_tier_rules%rowtype;
  target_rule public.equipment_tier_rules%rowtype;
  has_current_equipment boolean := false;
  previous_level text := 'none';
  previous_rank integer := 0;
  target_rank integer;
  next_state_version integer;
  cash_after bigint;
begin
  if p_equipment_type is null or p_equipment_type not in (
    'camera', 'microphone', 'editing_pc'
  ) then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_INVALID_EQUIPMENT_TYPE';
  end if;

  if p_level is null or p_level not in (
    'beginner', 'intermediate', 'advanced'
  ) then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_INVALID_EQUIPMENT_LEVEL';
  end if;

  if p_actor_user_id is null or p_run_id is null then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_RUN_NOT_FOUND';
  end if;

  if p_expected_version is null or p_expected_version < 0 then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_STALE_STATE';
  end if;

  select * into locked_state
  from public.run_state where run_id = p_run_id for update;
  if not found then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_RUN_NOT_FOUND';
  end if;

  select * into locked_run from public.game_runs where id = p_run_id;
  if locked_run.id is null then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_COMMIT_FAILED';
  end if;
  if locked_run.user_id is distinct from p_actor_user_id then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_FORBIDDEN';
  end if;
  if locked_run.status <> 'playing' then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_RUN_NOT_PLAYABLE';
  end if;
  if locked_state.state_version is distinct from p_expected_version then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_STALE_STATE';
  end if;

  if exists (
    select 1 from public.run_conditions as condition
    where condition.run_id = p_run_id
      and condition.recovered_at is null
      and locked_state.current_week between condition.unavailable_from_week
        and condition.unavailable_through_week
  ) then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_ACTIVITY_UNAVAILABLE';
  end if;

  select * into target_rule
  from public.equipment_tier_rules
  where rule_set_id = locked_run.rule_set_id
    and equipment_type_code = p_equipment_type
    and tier = p_level;
  if not found then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_EQUIPMENT_RULE_UNAVAILABLE';
  end if;

  select * into current_equipment
  from public.run_equipment
  where run_id = p_run_id and equipment_type_code = p_equipment_type
  for update;
  has_current_equipment := found;

  if has_current_equipment then
    select * into current_rule
    from public.equipment_tier_rules
    where id = current_equipment.equipment_tier_rule_id
      and rule_set_id = locked_run.rule_set_id
      and equipment_type_code = p_equipment_type
    for update;
    if not found then
      raise exception using errcode = 'P0001',
        message = 'PURCHASE_EQUIPMENT_EQUIPMENT_RULE_UNAVAILABLE';
    end if;

    previous_level := current_rule.tier;
    previous_rank := case current_rule.tier
      when 'none' then 0 when 'beginner' then 1
      when 'intermediate' then 2 when 'advanced' then 3 else -1 end;
  end if;

  target_rank := case target_rule.tier
    when 'beginner' then 1 when 'intermediate' then 2
    when 'advanced' then 3 else -1 end;
  if target_rank <= previous_rank then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_SAME_OR_LOWER_TIER';
  end if;
  if locked_state.cash < target_rule.purchase_price then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_INSUFFICIENT_CASH';
  end if;

  cash_after := locked_state.cash - target_rule.purchase_price;
  next_state_version := locked_state.state_version + 1;
  update public.run_state set cash = cash_after,
    state_version = next_state_version,
    updated_at = pg_catalog.statement_timestamp()
  where run_id = p_run_id;

  if has_current_equipment then
    update public.run_equipment set equipment_tier_rule_id = target_rule.id,
      acquired_week = locked_state.current_week
    where run_id = p_run_id and equipment_type_code = p_equipment_type;
  else
    insert into public.run_equipment (
      run_id, equipment_type_code, equipment_tier_rule_id, acquired_week
    ) values (
      p_run_id, p_equipment_type, target_rule.id, locked_state.current_week
    );
  end if;

  insert into public.equipment_purchases (
    run_id, equipment_type_code, from_tier_rule_id, to_tier_rule_id,
    price_paid, purchased_week
  ) values (
    p_run_id, p_equipment_type,
    case when has_current_equipment then current_rule.id else null end,
    target_rule.id, target_rule.purchase_price, locked_state.current_week
  );

  return pg_catalog.jsonb_build_object(
    'equipmentType', p_equipment_type,
    'previousLevel', previous_level,
    'purchasedLevel', target_rule.tier,
    'pricePaid', target_rule.purchase_price,
    'cashAfter', cash_after,
    'purchasedWeek', locked_state.current_week,
    'nextStateVersion', next_state_version
  );
exception
  when sqlstate 'P0001' then raise;
  when others then
    raise exception using errcode = 'P0001',
      message = 'PURCHASE_EQUIPMENT_COMMIT_FAILED';
end;
$$;

comment on function public.purchase_equipment(uuid, uuid, text, text, integer) is
  'Atomically purchases a higher equipment tier using the run-owned rule set and locks the run state and current equipment row.';

revoke execute on function public.purchase_equipment(uuid, uuid, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.purchase_equipment(uuid, uuid, text, text, integer)
  to service_role;