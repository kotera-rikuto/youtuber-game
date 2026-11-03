
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {

  "public": {
          Tables: {
            "ability_allocations": {
                  Row: {
                    "ability_code": string,"allocated_week": number,"created_at": string,"grant_id": string,"id": string,"points": number
                  }
                  ComputedFields: never
                  Insert: {
                    "ability_code": string,"allocated_week": number,"created_at"?: string,"grant_id": string,"id"?: string,"points": number
                  }
                  Update: {
                    "ability_code"?: string,"allocated_week"?: number,"created_at"?: string,"grant_id"?: string,"id"?: string,"points"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "ability_allocations_ability_code_fkey"
      columns: ["ability_code"]
isOneToOne: false
      referencedRelation: "ability_definitions"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "ability_allocations_grant_id_fkey"
      columns: ["grant_id"]
isOneToOne: false
      referencedRelation: "ability_point_grants"
      referencedColumns: ["id"]
    }
                  ]
                },"ability_definitions": {
                  Row: {
                    "code": string,"display_order": number,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"display_order": number,"name": string
                  }
                  Update: {
                    "code"?: string,"display_order"?: number,"name"?: string
                  }
                  Relationships: [

                  ]
                },"ability_point_grants": {
                  Row: {
                    "amount": number,"available_from_week": number,"created_at": string,"earned_week": number,"id": string,"run_id": string,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount": number,"available_from_week": number,"created_at"?: string,"earned_week": number,"id"?: string,"run_id": string,"status": string
                  }
                  Update: {
                    "amount"?: number,"available_from_week"?: number,"created_at"?: string,"earned_week"?: number,"id"?: string,"run_id"?: string,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ability_point_grants_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "ability_point_grants_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"action_definitions": {
                  Row: {
                    "code": string,"description": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"description": string,"name": string
                  }
                  Update: {
                    "code"?: string,"description"?: string,"name"?: string
                  }
                  Relationships: [

                  ]
                },"action_rules": {
                  Row: {
                    "action_code": string,"cooldown_weeks": number,"energy_delta": number,"fixed_cash_delta": number,"id": string,"required_feature_code": string | null,"rule_set_id": string,"video_view_multiplier": number
                  }
                  ComputedFields: never
                  Insert: {
                    "action_code": string,"cooldown_weeks": number,"energy_delta": number,"fixed_cash_delta": number,"id"?: string,"required_feature_code"?: string | null,"rule_set_id": string,"video_view_multiplier": number
                  }
                  Update: {
                    "action_code"?: string,"cooldown_weeks"?: number,"energy_delta"?: number,"fixed_cash_delta"?: number,"id"?: string,"required_feature_code"?: string | null,"rule_set_id"?: string,"video_view_multiplier"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "action_rules_action_code_fkey"
      columns: ["action_code"]
isOneToOne: false
      referencedRelation: "action_definitions"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "action_rules_action_code_fkey"
      columns: ["action_code"]
isOneToOne: false
      referencedRelation: "week_history_view"
      referencedColumns: ["action_code"]
    },{
      foreignKeyName: "action_rules_required_feature_code_fkey"
      columns: ["required_feature_code"]
isOneToOne: false
      referencedRelation: "feature_definitions"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "action_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"advance_week_executions": {
                  Row: {
                    "attempted_week": number,"created_at": string,"expected_state_version": number,"idempotency_key": string,"outcome": string,"run_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "attempted_week": number,"created_at"?: string,"expected_state_version": number,"idempotency_key": string,"outcome": string,"run_id": string
                  }
                  Update: {
                    "attempted_week"?: number,"created_at"?: string,"expected_state_version"?: number,"idempotency_key"?: string,"outcome"?: string,"run_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "advance_week_executions_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "advance_week_executions_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"channel_ability_weights": {
                  Row: {
                    "ability_code": string,"channel_rule_id": string,"id": string,"rule_set_id": string,"weight": number
                  }
                  ComputedFields: never
                  Insert: {
                    "ability_code": string,"channel_rule_id": string,"id"?: string,"rule_set_id": string,"weight": number
                  }
                  Update: {
                    "ability_code"?: string,"channel_rule_id"?: string,"id"?: string,"rule_set_id"?: string,"weight"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "channel_ability_weights_ability_code_fkey"
      columns: ["ability_code"]
isOneToOne: false
      referencedRelation: "ability_definitions"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "channel_ability_weights_rule_set_channel_rule_fkey"
      columns: ["rule_set_id","channel_rule_id"]
isOneToOne: false
      referencedRelation: "channel_rules"
      referencedColumns: ["rule_set_id","id"]
    },{
      foreignKeyName: "channel_ability_weights_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"channel_rules": {
                  Row: {
                    "channel_type_code": string,"id": string,"rule_set_id": string,"view_multiplier": number,"weekly_flame_probability": number
                  }
                  ComputedFields: never
                  Insert: {
                    "channel_type_code": string,"id"?: string,"rule_set_id": string,"view_multiplier": number,"weekly_flame_probability": number
                  }
                  Update: {
                    "channel_type_code"?: string,"id"?: string,"rule_set_id"?: string,"view_multiplier"?: number,"weekly_flame_probability"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "channel_rules_channel_type_code_fkey"
      columns: ["channel_type_code"]
isOneToOne: false
      referencedRelation: "channel_types"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "channel_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"channel_types": {
                  Row: {
                    "code": string,"display_order": number,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"display_order": number,"name": string
                  }
                  Update: {
                    "code"?: string,"display_order"?: number,"name"?: string
                  }
                  Relationships: [

                  ]
                },"equipment_purchases": {
                  Row: {
                    "created_at": string,"equipment_type_code": string,"from_tier_rule_id": string | null,"id": string,"price_paid": number,"purchased_week": number,"run_id": string,"to_tier_rule_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"equipment_type_code": string,"from_tier_rule_id"?: string | null,"id"?: string,"price_paid": number,"purchased_week": number,"run_id": string,"to_tier_rule_id": string
                  }
                  Update: {
                    "created_at"?: string,"equipment_type_code"?: string,"from_tier_rule_id"?: string | null,"id"?: string,"price_paid"?: number,"purchased_week"?: number,"run_id"?: string,"to_tier_rule_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "equipment_purchases_equipment_type_code_fkey"
      columns: ["equipment_type_code"]
isOneToOne: false
      referencedRelation: "equipment_types"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "equipment_purchases_from_tier_rule_id_fkey"
      columns: ["from_tier_rule_id"]
isOneToOne: false
      referencedRelation: "equipment_tier_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "equipment_purchases_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "equipment_purchases_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "equipment_purchases_to_tier_rule_id_fkey"
      columns: ["to_tier_rule_id"]
isOneToOne: false
      referencedRelation: "equipment_tier_rules"
      referencedColumns: ["id"]
    }
                  ]
                },"equipment_tier_rules": {
                  Row: {
                    "equipment_type_code": string,"id": string,"purchase_price": number,"rule_set_id": string,"tier": string,"view_bonus": number
                  }
                  ComputedFields: never
                  Insert: {
                    "equipment_type_code": string,"id"?: string,"purchase_price": number,"rule_set_id": string,"tier": string,"view_bonus": number
                  }
                  Update: {
                    "equipment_type_code"?: string,"id"?: string,"purchase_price"?: number,"rule_set_id"?: string,"tier"?: string,"view_bonus"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "equipment_tier_rules_equipment_type_code_fkey"
      columns: ["equipment_type_code"]
isOneToOne: false
      referencedRelation: "equipment_types"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "equipment_tier_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"equipment_types": {
                  Row: {
                    "code": string,"display_order": number,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"display_order": number,"name": string
                  }
                  Update: {
                    "code"?: string,"display_order"?: number,"name"?: string
                  }
                  Relationships: [

                  ]
                },"event_categories": {
                  Row: {
                    "code": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"name": string
                  }
                  Update: {
                    "code"?: string,"name"?: string
                  }
                  Relationships: [

                  ]
                },"event_category_rules": {
                  Row: {
                    "category_code": string,"id": string,"rule_set_id": string,"weekly_probability": number
                  }
                  ComputedFields: never
                  Insert: {
                    "category_code": string,"id"?: string,"rule_set_id": string,"weekly_probability": number
                  }
                  Update: {
                    "category_code"?: string,"id"?: string,"rule_set_id"?: string,"weekly_probability"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "event_category_rules_category_code_fkey"
      columns: ["category_code"]
isOneToOne: false
      referencedRelation: "event_categories"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "event_category_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"event_definitions": {
                  Row: {
                    "category_code": string,"code": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "category_code": string,"code": string,"name": string
                  }
                  Update: {
                    "category_code"?: string,"code"?: string,"name"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "event_definitions_category_code_fkey"
      columns: ["category_code"]
isOneToOne: false
      referencedRelation: "event_categories"
      referencedColumns: ["code"]
    }
                  ]
                },"event_rules": {
                  Row: {
                    "category_code": string,"event_definition_code": string,"fixed_cash_delta": number,"fixed_subscriber_delta": number,"id": string,"rule_set_id": string,"selection_weight": number,"subscriber_multiplier": number,"weekly_view_multiplier": number
                  }
                  ComputedFields: never
                  Insert: {
                    "category_code": string,"event_definition_code": string,"fixed_cash_delta": number,"fixed_subscriber_delta": number,"id"?: string,"rule_set_id": string,"selection_weight": number,"subscriber_multiplier": number,"weekly_view_multiplier": number
                  }
                  Update: {
                    "category_code"?: string,"event_definition_code"?: string,"fixed_cash_delta"?: number,"fixed_subscriber_delta"?: number,"id"?: string,"rule_set_id"?: string,"selection_weight"?: number,"subscriber_multiplier"?: number,"weekly_view_multiplier"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "event_rules_definition_category_fkey"
      columns: ["event_definition_code","category_code"]
isOneToOne: false
      referencedRelation: "event_definitions"
      referencedColumns: ["code","category_code"]
    },{
      foreignKeyName: "event_rules_rule_set_category_fkey"
      columns: ["rule_set_id","category_code"]
isOneToOne: false
      referencedRelation: "event_category_rules"
      referencedColumns: ["rule_set_id","category_code"]
    },{
      foreignKeyName: "event_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"feature_definitions": {
                  Row: {
                    "code": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"name": string
                  }
                  Update: {
                    "code"?: string,"name"?: string
                  }
                  Relationships: [

                  ]
                },"feature_rules": {
                  Row: {
                    "activation_delay_weeks": number,"feature_code": string,"id": string,"is_persistent": boolean,"rule_set_id": string,"unlock_subscribers": number
                  }
                  ComputedFields: never
                  Insert: {
                    "activation_delay_weeks": number,"feature_code": string,"id"?: string,"is_persistent": boolean,"rule_set_id": string,"unlock_subscribers": number
                  }
                  Update: {
                    "activation_delay_weeks"?: number,"feature_code"?: string,"id"?: string,"is_persistent"?: boolean,"rule_set_id"?: string,"unlock_subscribers"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "feature_rules_feature_code_fkey"
      columns: ["feature_code"]
isOneToOne: false
      referencedRelation: "feature_definitions"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "feature_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"game_runs": {
                  Row: {
                    "channel_name": string,"channel_rule_id": string,"completed_at": string | null,"created_at": string,"id": string,"rule_set_id": string,"specialty_code": string | null,"status": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "channel_name": string,"channel_rule_id": string,"completed_at"?: string | null,"created_at"?: string,"id"?: string,"rule_set_id": string,"specialty_code"?: string | null,"status"?: string,"user_id": string
                  }
                  Update: {
                    "channel_name"?: string,"channel_rule_id"?: string,"completed_at"?: string | null,"created_at"?: string,"id"?: string,"rule_set_id"?: string,"specialty_code"?: string | null,"status"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_runs_rule_set_channel_rule_fkey"
      columns: ["rule_set_id","channel_rule_id"]
isOneToOne: false
      referencedRelation: "channel_rules"
      referencedColumns: ["rule_set_id","id"]
    },{
      foreignKeyName: "game_runs_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "game_runs_rule_set_specialty_fkey"
      columns: ["rule_set_id","specialty_code"]
isOneToOne: false
      referencedRelation: "rule_set_specialties"
      referencedColumns: ["rule_set_id","specialty_code"]
    }
                  ]
                },"game_terminations": {
                  Row: {
                    "calculated_energy": number | null,"calculated_flame_count": number | null,"created_at": string,"execution_id": string | null,"id": string,"occurred_week": number,"reason": string,"run_id": string,"week_result_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "calculated_energy"?: number | null,"calculated_flame_count"?: number | null,"created_at"?: string,"execution_id"?: string | null,"id"?: string,"occurred_week": number,"reason": string,"run_id": string,"week_result_id"?: string | null
                  }
                  Update: {
                    "calculated_energy"?: number | null,"calculated_flame_count"?: number | null,"created_at"?: string,"execution_id"?: string | null,"id"?: string,"occurred_week"?: number,"reason"?: string,"run_id"?: string,"week_result_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "game_terminations_execution_id_fkey"
      columns: ["execution_id"]
isOneToOne: true
      referencedRelation: "advance_week_executions"
      referencedColumns: ["idempotency_key"]
    },{
      foreignKeyName: "game_terminations_run_id_fkey"
      columns: ["run_id"]
isOneToOne: true
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "game_terminations_run_id_fkey"
      columns: ["run_id"]
isOneToOne: true
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "game_terminations_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: true
      referencedRelation: "video_result_view"
      referencedColumns: ["week_result_id"]
    },{
      foreignKeyName: "game_terminations_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: true
      referencedRelation: "week_history_view"
      referencedColumns: ["week_result_id"]
    },{
      foreignKeyName: "game_terminations_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: true
      referencedRelation: "week_results"
      referencedColumns: ["id"]
    }
                  ]
                },"global_rules": {
                  Row: {
                    "ad_revenue_per_view": number,"ban_flame_count": number,"base_views_max": number,"base_views_min": number,"energy_max": number,"flame_energy_loss": number,"flame_subscriber_loss_rate": number,"idea_stock_max": number,"ideas_per_week": number,"rule_set_id": string,"system_idea_subscriber_conversion_rate": number,"system_idea_view_multiplier": number,"unavailable_energy_recovery": number
                  }
                  ComputedFields: never
                  Insert: {
                    "ad_revenue_per_view": number,"ban_flame_count": number,"base_views_max": number,"base_views_min": number,"energy_max": number,"flame_energy_loss": number,"flame_subscriber_loss_rate": number,"idea_stock_max": number,"ideas_per_week": number,"rule_set_id": string,"system_idea_subscriber_conversion_rate": number,"system_idea_view_multiplier": number,"unavailable_energy_recovery": number
                  }
                  Update: {
                    "ad_revenue_per_view"?: number,"ban_flame_count"?: number,"base_views_max"?: number,"base_views_min"?: number,"energy_max"?: number,"flame_energy_loss"?: number,"flame_subscriber_loss_rate"?: number,"idea_stock_max"?: number,"ideas_per_week"?: number,"rule_set_id"?: string,"system_idea_subscriber_conversion_rate"?: number,"system_idea_view_multiplier"?: number,"unavailable_energy_recovery"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "global_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: true
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"goal_rules": {
                  Row: {
                    "duration_weeks": number,"id": string,"is_final": boolean,"rule_set_id": string,"stage_number": number,"target_subscribers": number
                  }
                  ComputedFields: never
                  Insert: {
                    "duration_weeks": number,"id"?: string,"is_final": boolean,"rule_set_id": string,"stage_number": number,"target_subscribers": number
                  }
                  Update: {
                    "duration_weeks"?: number,"id"?: string,"is_final"?: boolean,"rule_set_id"?: string,"stage_number"?: number,"target_subscribers"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "goal_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"health_risk_rules": {
                  Row: {
                    "id": string,"max_energy": number,"max_unavailable_weeks": number,"min_energy": number,"min_unavailable_weeks": number,"occurrence_probability": number,"rule_set_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"max_energy": number,"max_unavailable_weeks": number,"min_energy": number,"min_unavailable_weeks": number,"occurrence_probability": number,"rule_set_id": string
                  }
                  Update: {
                    "id"?: string,"max_energy"?: number,"max_unavailable_weeks"?: number,"min_energy"?: number,"min_unavailable_weeks"?: number,"occurrence_probability"?: number,"rule_set_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "health_risk_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"idea_evaluations": {
                  Row: {
                    "evaluated_at": string,"evaluation_status": string,"idea_id": string,"model": string,"prompt_version": string,"score": number
                  }
                  ComputedFields: never
                  Insert: {
                    "evaluated_at"?: string,"evaluation_status": string,"idea_id": string,"model": string,"prompt_version": string,"score": number
                  }
                  Update: {
                    "evaluated_at"?: string,"evaluation_status"?: string,"idea_id"?: string,"model"?: string,"prompt_version"?: string,"score"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "idea_evaluations_idea_id_fkey"
      columns: ["idea_id"]
isOneToOne: true
      referencedRelation: "idea_stock_view"
      referencedColumns: ["idea_id"]
    },{
      foreignKeyName: "idea_evaluations_idea_id_fkey"
      columns: ["idea_id"]
isOneToOne: true
      referencedRelation: "player_ideas"
      referencedColumns: ["id"]
    }
                  ]
                },"idea_queue_entries": {
                  Row: {
                    "idea_id": string,"position": number,"queued_at": string,"run_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "idea_id": string,"position": number,"queued_at"?: string,"run_id": string
                  }
                  Update: {
                    "idea_id"?: string,"position"?: number,"queued_at"?: string,"run_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "idea_queue_entries_run_idea_fkey"
      columns: ["run_id","idea_id"]
isOneToOne: false
      referencedRelation: "player_ideas"
      referencedColumns: ["run_id","id"]
    }
                  ]
                },"idea_score_band_rules": {
                  Row: {
                    "id": string,"max_score": number,"min_score": number,"rule_set_id": string,"subscriber_conversion_rate": number,"view_multiplier": number
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"max_score": number,"min_score": number,"rule_set_id": string,"subscriber_conversion_rate": number,"view_multiplier": number
                  }
                  Update: {
                    "id"?: string,"max_score"?: number,"min_score"?: number,"rule_set_id"?: string,"subscriber_conversion_rate"?: number,"view_multiplier"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "idea_score_band_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"occurred_events": {
                  Row: {
                    "created_at": string,"display_metadata": NonNullable<Json>,"event_definition_code": string,"event_rule_id": string | null,"id": string,"sequence_number": number,"week_result_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"display_metadata"?: NonNullable<Json>,"event_definition_code": string,"event_rule_id"?: string | null,"id"?: string,"sequence_number": number,"week_result_id": string
                  }
                  Update: {
                    "created_at"?: string,"display_metadata"?: NonNullable<Json>,"event_definition_code"?: string,"event_rule_id"?: string | null,"id"?: string,"sequence_number"?: number,"week_result_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "occurred_events_event_definition_code_fkey"
      columns: ["event_definition_code"]
isOneToOne: false
      referencedRelation: "event_definitions"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "occurred_events_event_rule_id_fkey"
      columns: ["event_rule_id"]
isOneToOne: false
      referencedRelation: "event_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "occurred_events_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: false
      referencedRelation: "video_result_view"
      referencedColumns: ["week_result_id"]
    },{
      foreignKeyName: "occurred_events_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: false
      referencedRelation: "week_history_view"
      referencedColumns: ["week_result_id"]
    },{
      foreignKeyName: "occurred_events_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: false
      referencedRelation: "week_results"
      referencedColumns: ["id"]
    }
                  ]
                },"player_ideas": {
                  Row: {
                    "created_at": string,"created_week": number,"deleted_at": string | null,"description": string | null,"id": string,"run_id": string,"title": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_week": number,"deleted_at"?: string | null,"description"?: string | null,"id"?: string,"run_id": string,"title": string
                  }
                  Update: {
                    "created_at"?: string,"created_week"?: number,"deleted_at"?: string | null,"description"?: string | null,"id"?: string,"run_id"?: string,"title"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "player_ideas_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "player_ideas_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"posting_frequency_rules": {
                  Row: {
                    "ability_points_awarded": number,"energy_cost": number,"id": string,"rule_set_id": string,"videos_per_week": number,"view_multiplier": number
                  }
                  ComputedFields: never
                  Insert: {
                    "ability_points_awarded": number,"energy_cost": number,"id"?: string,"rule_set_id": string,"videos_per_week": number,"view_multiplier": number
                  }
                  Update: {
                    "ability_points_awarded"?: number,"energy_cost"?: number,"id"?: string,"rule_set_id"?: string,"videos_per_week"?: number,"view_multiplier"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "posting_frequency_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"profiles": {
                  Row: {
                    "created_at": string,"display_name": string | null,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"display_name"?: string | null,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"display_name"?: string | null,"user_id"?: string
                  }
                  Relationships: [

                  ]
                },"rule_set_specialties": {
                  Row: {
                    "rule_set_id": string,"specialty_code": string
                  }
                  ComputedFields: never
                  Insert: {
                    "rule_set_id": string,"specialty_code": string
                  }
                  Update: {
                    "rule_set_id"?: string,"specialty_code"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "rule_set_specialties_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "rule_set_specialties_specialty_code_fkey"
      columns: ["specialty_code"]
isOneToOne: false
      referencedRelation: "specialty_categories"
      referencedColumns: ["code"]
    }
                  ]
                },"rule_set_system_ideas": {
                  Row: {
                    "created_at": string,"enabled": boolean,"id": string,"rule_set_id": string,"system_idea_template_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"enabled"?: boolean,"id"?: string,"rule_set_id": string,"system_idea_template_id": string
                  }
                  Update: {
                    "created_at"?: string,"enabled"?: boolean,"id"?: string,"rule_set_id"?: string,"system_idea_template_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "rule_set_system_ideas_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "rule_set_system_ideas_system_idea_template_id_fkey"
      columns: ["system_idea_template_id"]
isOneToOne: false
      referencedRelation: "system_idea_templates"
      referencedColumns: ["id"]
    }
                  ]
                },"rule_sets": {
                  Row: {
                    "created_at": string,"id": string,"published_at": string | null,"status": string,"version": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"published_at"?: string | null,"status"?: string,"version": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"published_at"?: string | null,"status"?: string,"version"?: string
                  }
                  Relationships: [

                  ]
                },"run_abilities": {
                  Row: {
                    "ability_code": string,"run_id": string,"value": number
                  }
                  ComputedFields: never
                  Insert: {
                    "ability_code": string,"run_id": string,"value": number
                  }
                  Update: {
                    "ability_code"?: string,"run_id"?: string,"value"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "run_abilities_ability_code_fkey"
      columns: ["ability_code"]
isOneToOne: false
      referencedRelation: "ability_definitions"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "run_abilities_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "run_abilities_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"run_conditions": {
                  Row: {
                    "duration_weeks": number,"health_risk_rule_id": string,"id": string,"recovered_at": string | null,"run_id": string,"started_week": number,"unavailable_from_week": number,"unavailable_through_week": number
                  }
                  ComputedFields: never
                  Insert: {
                    "duration_weeks": number,"health_risk_rule_id": string,"id"?: string,"recovered_at"?: string | null,"run_id": string,"started_week": number,"unavailable_from_week": number,"unavailable_through_week": number
                  }
                  Update: {
                    "duration_weeks"?: number,"health_risk_rule_id"?: string,"id"?: string,"recovered_at"?: string | null,"run_id"?: string,"started_week"?: number,"unavailable_from_week"?: number,"unavailable_through_week"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "run_conditions_health_risk_rule_id_fkey"
      columns: ["health_risk_rule_id"]
isOneToOne: false
      referencedRelation: "health_risk_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "run_conditions_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "run_conditions_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"run_equipment": {
                  Row: {
                    "acquired_week": number,"equipment_tier_rule_id": string,"equipment_type_code": string,"run_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "acquired_week": number,"equipment_tier_rule_id": string,"equipment_type_code": string,"run_id": string
                  }
                  Update: {
                    "acquired_week"?: number,"equipment_tier_rule_id"?: string,"equipment_type_code"?: string,"run_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "run_equipment_equipment_tier_rule_id_fkey"
      columns: ["equipment_tier_rule_id"]
isOneToOne: false
      referencedRelation: "equipment_tier_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "run_equipment_equipment_type_code_fkey"
      columns: ["equipment_type_code"]
isOneToOne: false
      referencedRelation: "equipment_types"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "run_equipment_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "run_equipment_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"run_feature_unlocks": {
                  Row: {
                    "active_from_week": number,"feature_rule_id": string,"run_id": string,"unlocked_week": number
                  }
                  ComputedFields: never
                  Insert: {
                    "active_from_week": number,"feature_rule_id": string,"run_id": string,"unlocked_week": number
                  }
                  Update: {
                    "active_from_week"?: number,"feature_rule_id"?: string,"run_id"?: string,"unlocked_week"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "run_feature_unlocks_feature_rule_id_fkey"
      columns: ["feature_rule_id"]
isOneToOne: false
      referencedRelation: "feature_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "run_feature_unlocks_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "run_feature_unlocks_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"run_goals": {
                  Row: {
                    "achieved_week": number | null,"deadline_week": number,"goal_rule_id": string,"id": string,"run_id": string,"started_week": number,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "achieved_week"?: number | null,"deadline_week": number,"goal_rule_id": string,"id"?: string,"run_id": string,"started_week": number,"status": string
                  }
                  Update: {
                    "achieved_week"?: number | null,"deadline_week"?: number,"goal_rule_id"?: string,"id"?: string,"run_id"?: string,"started_week"?: number,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "run_goals_goal_rule_id_fkey"
      columns: ["goal_rule_id"]
isOneToOne: false
      referencedRelation: "goal_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "run_goals_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "run_goals_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"run_state": {
                  Row: {
                    "cash": number,"cumulative_views": number,"current_week": number,"energy": number,"flame_count": number,"posting_frequency_rule_id": string,"run_id": string,"state_version": number,"subscribers": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "cash"?: number,"cumulative_views"?: number,"current_week"?: number,"energy"?: number,"flame_count"?: number,"posting_frequency_rule_id": string,"run_id": string,"state_version"?: number,"subscribers"?: number,"updated_at"?: string
                  }
                  Update: {
                    "cash"?: number,"cumulative_views"?: number,"current_week"?: number,"energy"?: number,"flame_count"?: number,"posting_frequency_rule_id"?: string,"run_id"?: string,"state_version"?: number,"subscribers"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "run_state_posting_frequency_rule_id_fkey"
      columns: ["posting_frequency_rule_id"]
isOneToOne: false
      referencedRelation: "posting_frequency_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "run_state_run_id_fkey"
      columns: ["run_id"]
isOneToOne: true
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "run_state_run_id_fkey"
      columns: ["run_id"]
isOneToOne: true
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"specialty_categories": {
                  Row: {
                    "code": string,"display_order": number,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"display_order": number,"name": string
                  }
                  Update: {
                    "code"?: string,"display_order"?: number,"name"?: string
                  }
                  Relationships: [

                  ]
                },"sponsorship_reward_rules": {
                  Row: {
                    "id": string,"max_subscribers": number | null,"min_subscribers": number,"reward_amount": number,"rule_set_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"max_subscribers"?: number | null,"min_subscribers": number,"reward_amount": number,"rule_set_id": string
                  }
                  Update: {
                    "id"?: string,"max_subscribers"?: number | null,"min_subscribers"?: number,"reward_amount"?: number,"rule_set_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "sponsorship_reward_rules_rule_set_id_fkey"
      columns: ["rule_set_id"]
isOneToOne: false
      referencedRelation: "rule_sets"
      referencedColumns: ["id"]
    }
                  ]
                },"system_idea_cycle_entries": {
                  Row: {
                    "created_at": string,"cycle_id": string,"id": string,"position": number,"rule_set_system_idea_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"cycle_id": string,"id"?: string,"position": number,"rule_set_system_idea_id": string
                  }
                  Update: {
                    "created_at"?: string,"cycle_id"?: string,"id"?: string,"position"?: number,"rule_set_system_idea_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "system_idea_cycle_entries_cycle_id_fkey"
      columns: ["cycle_id"]
isOneToOne: false
      referencedRelation: "system_idea_cycles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "system_idea_cycle_entries_rule_set_system_idea_id_fkey"
      columns: ["rule_set_system_idea_id"]
isOneToOne: false
      referencedRelation: "rule_set_system_ideas"
      referencedColumns: ["id"]
    }
                  ]
                },"system_idea_cycles": {
                  Row: {
                    "created_at": string,"created_week": number,"cycle_number": number,"id": string,"run_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_week": number,"cycle_number": number,"id"?: string,"run_id": string
                  }
                  Update: {
                    "created_at"?: string,"created_week"?: number,"cycle_number"?: number,"id"?: string,"run_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "system_idea_cycles_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "system_idea_cycles_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"system_idea_templates": {
                  Row: {
                    "channel_type_code": string,"code": string,"created_at": string,"description": string,"enabled": boolean,"id": string,"specialty_code": string | null,"title": string
                  }
                  ComputedFields: never
                  Insert: {
                    "channel_type_code": string,"code": string,"created_at"?: string,"description": string,"enabled"?: boolean,"id"?: string,"specialty_code"?: string | null,"title": string
                  }
                  Update: {
                    "channel_type_code"?: string,"code"?: string,"created_at"?: string,"description"?: string,"enabled"?: boolean,"id"?: string,"specialty_code"?: string | null,"title"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "system_idea_templates_channel_type_code_fkey"
      columns: ["channel_type_code"]
isOneToOne: false
      referencedRelation: "channel_types"
      referencedColumns: ["code"]
    },{
      foreignKeyName: "system_idea_templates_specialty_code_fkey"
      columns: ["specialty_code"]
isOneToOne: false
      referencedRelation: "specialty_categories"
      referencedColumns: ["code"]
    }
                  ]
                },"video_calculations": {
                  Row: {
                    "ability_multiplier": number,"base_views": number,"channel_multiplier": number,"collaboration_multiplier": number,"conversion_rate": number,"created_at": string,"equipment_multiplier": number,"event_multiplier": number,"final_views": number,"idea_multiplier": number,"posting_frequency_multiplier": number,"subscriber_multiplier": number,"subscribers_gained": number,"video_id": string,"views_before_event": number
                  }
                  ComputedFields: never
                  Insert: {
                    "ability_multiplier": number,"base_views": number,"channel_multiplier": number,"collaboration_multiplier": number,"conversion_rate": number,"created_at"?: string,"equipment_multiplier": number,"event_multiplier": number,"final_views": number,"idea_multiplier": number,"posting_frequency_multiplier": number,"subscriber_multiplier": number,"subscribers_gained": number,"video_id": string,"views_before_event": number
                  }
                  Update: {
                    "ability_multiplier"?: number,"base_views"?: number,"channel_multiplier"?: number,"collaboration_multiplier"?: number,"conversion_rate"?: number,"created_at"?: string,"equipment_multiplier"?: number,"event_multiplier"?: number,"final_views"?: number,"idea_multiplier"?: number,"posting_frequency_multiplier"?: number,"subscriber_multiplier"?: number,"subscribers_gained"?: number,"video_id"?: string,"views_before_event"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "video_calculations_video_id_fkey"
      columns: ["video_id"]
isOneToOne: true
      referencedRelation: "video_result_view"
      referencedColumns: ["video_id"]
    },{
      foreignKeyName: "video_calculations_video_id_fkey"
      columns: ["video_id"]
isOneToOne: true
      referencedRelation: "videos"
      referencedColumns: ["id"]
    }
                  ]
                },"videos": {
                  Row: {
                    "created_at": string,"id": string,"player_idea_id": string | null,"sequence_number": number,"system_idea_cycle_entry_id": string | null,"title_snapshot": string,"week_result_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"player_idea_id"?: string | null,"sequence_number": number,"system_idea_cycle_entry_id"?: string | null,"title_snapshot": string,"week_result_id": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"player_idea_id"?: string | null,"sequence_number"?: number,"system_idea_cycle_entry_id"?: string | null,"title_snapshot"?: string,"week_result_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "videos_player_idea_id_fkey"
      columns: ["player_idea_id"]
isOneToOne: true
      referencedRelation: "idea_stock_view"
      referencedColumns: ["idea_id"]
    },{
      foreignKeyName: "videos_player_idea_id_fkey"
      columns: ["player_idea_id"]
isOneToOne: true
      referencedRelation: "player_ideas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "videos_system_idea_cycle_entry_id_fkey"
      columns: ["system_idea_cycle_entry_id"]
isOneToOne: true
      referencedRelation: "system_idea_cycle_entries"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "videos_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: false
      referencedRelation: "video_result_view"
      referencedColumns: ["week_result_id"]
    },{
      foreignKeyName: "videos_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: false
      referencedRelation: "week_history_view"
      referencedColumns: ["week_result_id"]
    },{
      foreignKeyName: "videos_week_result_id_fkey"
      columns: ["week_result_id"]
isOneToOne: false
      referencedRelation: "week_results"
      referencedColumns: ["id"]
    }
                  ]
                },"week_results": {
                  Row: {
                    "ad_revenue": number,"cash_after": number,"cash_before": number,"created_at": string,"energy_after": number,"energy_before": number,"execution_id": string,"final_views": number,"flame_count_after": number,"id": string,"max_subscribers_during_week": number,"posting_frequency_rule_id": string | null,"run_id": string,"run_status_after": string,"state_version_after": number,"subscribers_after": number,"subscribers_before": number,"views_before_event": number,"week_number": number,"weekly_action_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "ad_revenue": number,"cash_after": number,"cash_before": number,"created_at"?: string,"energy_after": number,"energy_before": number,"execution_id": string,"final_views": number,"flame_count_after": number,"id"?: string,"max_subscribers_during_week": number,"posting_frequency_rule_id"?: string | null,"run_id": string,"run_status_after": string,"state_version_after": number,"subscribers_after": number,"subscribers_before": number,"views_before_event": number,"week_number": number,"weekly_action_id"?: string | null
                  }
                  Update: {
                    "ad_revenue"?: number,"cash_after"?: number,"cash_before"?: number,"created_at"?: string,"energy_after"?: number,"energy_before"?: number,"execution_id"?: string,"final_views"?: number,"flame_count_after"?: number,"id"?: string,"max_subscribers_during_week"?: number,"posting_frequency_rule_id"?: string | null,"run_id"?: string,"run_status_after"?: string,"state_version_after"?: number,"subscribers_after"?: number,"subscribers_before"?: number,"views_before_event"?: number,"week_number"?: number,"weekly_action_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "week_results_execution_id_fkey"
      columns: ["execution_id"]
isOneToOne: true
      referencedRelation: "advance_week_executions"
      referencedColumns: ["idempotency_key"]
    },{
      foreignKeyName: "week_results_posting_frequency_rule_id_fkey"
      columns: ["posting_frequency_rule_id"]
isOneToOne: false
      referencedRelation: "posting_frequency_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "week_results_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "week_results_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "week_results_weekly_action_id_fkey"
      columns: ["weekly_action_id"]
isOneToOne: false
      referencedRelation: "weekly_actions"
      referencedColumns: ["id"]
    }
                  ]
                },"weekly_actions": {
                  Row: {
                    "action_rule_id": string,"id": string,"locked_at": string | null,"run_id": string,"selected_at": string,"week_number": number
                  }
                  ComputedFields: never
                  Insert: {
                    "action_rule_id": string,"id"?: string,"locked_at"?: string | null,"run_id": string,"selected_at"?: string,"week_number": number
                  }
                  Update: {
                    "action_rule_id"?: string,"id"?: string,"locked_at"?: string | null,"run_id"?: string,"selected_at"?: string,"week_number"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "weekly_actions_action_rule_id_fkey"
      columns: ["action_rule_id"]
isOneToOne: false
      referencedRelation: "action_rules"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "weekly_actions_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "weekly_actions_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            "current_game_view": {
                  Row: {
                    "abilities": Json | null,"cash": number,"channel_name": string,"channel_type_code": string,"channel_type_name": string,"completed_at": string | null,"created_at": string,"cumulative_views": number,"current_goal_deadline_week": number | null,"current_goal_started_week": number | null,"current_goal_status": string | null,"current_goal_target_subscribers": number | null,"current_stage_number": number | null,"current_week": number,"energy": number,"equipment": Json | null,"feature_unlocks": Json | null,"flame_count": number,"is_current_goal_final": boolean | null,"run_id": string,"specialty_code": string | null,"specialty_name": string | null,"state_version": number,"status": string,"subscribers": number,"updated_at": string,"videos_per_week": number
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "channel_rules_channel_type_code_fkey"
      columns: ["channel_type_code"]
isOneToOne: false
      referencedRelation: "channel_types"
      referencedColumns: ["code"]
    }
                  ]
                },"idea_stock_view": {
                  Row: {
                    "created_at": string,"created_week": number,"description": string | null,"idea_id": string,"idea_source": string | null,"is_pending": boolean | null,"position": number,"queued_at": string,"run_id": string,"stock_status": string | null,"title": string
                  }
                  ComputedFields: never
                  Relationships: [

                  ]
                },"video_result_view": {
                  Row: {
                    "ability_multiplier": number,"base_views": number,"channel_multiplier": number,"collaboration_multiplier": number,"conversion_rate": number,"created_at": string,"equipment_multiplier": number,"event_multiplier": number,"final_views": number,"idea_multiplier": number,"idea_source": string | null,"posting_frequency_multiplier": number,"run_id": string,"sequence_number": number,"subscriber_multiplier": number,"subscribers_gained": number,"title_snapshot": string,"video_id": string,"views_before_event": number,"week_number": number,"week_result_id": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "week_results_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "week_results_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"week_history_view": {
                  Row: {
                    "action_code": string | null,"action_name": string | null,"ad_revenue": number,"cash_after": number,"cash_before": number,"cash_change": number | null,"created_at": string,"energy_after": number,"energy_before": number,"energy_change": number | null,"event_view_change": number | null,"events": Json | null,"final_views": number,"flame_count_after": number,"flame_count_before": number | null,"flame_count_change": number | null,"had_flame": boolean | null,"health_condition_duration_weeks": number | null,"health_condition_started": boolean | null,"max_subscribers_during_week": number,"planned_video_count": number | null,"posted_video_count": number | null,"run_id": string,"run_status_after": string,"stage_number": number | null,"state_version_after": number,"subscriber_change": number | null,"subscribers_after": number,"subscribers_before": number,"unavailable_from_week": number | null,"unavailable_through_week": number | null,"views_before_event": number,"was_activity_unavailable": boolean | null,"week_number": number,"week_result_id": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "week_results_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "current_game_view"
      referencedColumns: ["run_id"]
    },{
      foreignKeyName: "week_results_run_id_fkey"
      columns: ["run_id"]
isOneToOne: false
      referencedRelation: "game_runs"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Functions: {
            "assert_rule_set_matches_run":
{ Args: { "reference_name": string,"referenced_rule_set_id": string,"target_run_id": string }; Returns: undefined
                           },
"commit_advance_week":
{ Args: { "p_command": Json }; Returns: Json
                           },
"commit_create_idea":
{ Args: { "p_actor_user_id": string,"p_description"?: string,"p_evaluation_status"?: string,"p_expected_version"?: number,"p_model"?: string,"p_prompt_version"?: string,"p_run_id": string,"p_score"?: number,"p_title": string }; Returns: string
                           },
"commit_start_game":
{ Args: { "p_actor_user_id": string,"p_channel_name": string,"p_posting_style": string,"p_specialty_code"?: string }; Returns: string
                           },
"commit_system_idea_cycle":
{ Args: { "p_actor_user_id": string,"p_ordered_rule_set_system_idea_ids": (string)[],"p_required_count": number,"p_run_id": string }; Returns: string
                           },
"delete_idea":
{ Args: { "p_actor_user_id": string,"p_expected_version": number,"p_idea_id": string,"p_run_id": string }; Returns: number
                           },
"get_advance_week_receipt":
{ Args: { "p_idempotency_key": string }; Returns: Json
                           },
"reorder_idea_stock":
{ Args: { "p_actor_user_id": string,"p_expected_version": number,"p_ordered_idea_ids": (string)[],"p_run_id": string }; Returns: number
                           },
"select_weekly_main_action":
{ Args: { "p_action": string,"p_actor_user_id": string,"p_expected_version": number,"p_run_id": string }; Returns: Json
                           },
"set_posting_frequency":
{ Args: { "p_actor_user_id": string,"p_expected_version": number,"p_run_id": string,"p_videos_per_week": number }; Returns: Json
                           },
"validate_rule_set_for_publication":
{ Args: { "target_rule_set_id": string }; Returns: undefined
                           },
"validate_rule_set_system_idea_pools":
{ Args: { "target_rule_set_id": string }; Returns: undefined
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {

          }
        }
} as const
