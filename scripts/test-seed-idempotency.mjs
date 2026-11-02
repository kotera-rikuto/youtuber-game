import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const supabaseDirectory = path.join(repoRoot, "supabase");
const initialRuleSetId = "00000000-0000-4000-8000-000000000001";

function run(command, args, options = {}) {
  const execution = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });

  if (execution.status !== 0) {
    const detail = options.capture ? `\n${execution.stderr || execution.stdout}` : "";
    throw new Error(`${command} ${args.join(" ")} failed${detail}`);
  }

  return execution.stdout?.trim() ?? "";
}

async function readLocalSeedConfiguration() {
  const config = await readFile(path.join(supabaseDirectory, "config.toml"), "utf8");
  const seedSection = config.match(/\[db\.seed\]([\s\S]*?)(?=\n\[|$)/u)?.[1];
  const configuredPaths = seedSection?.match(/sql_paths\s*=\s*\[([\s\S]*?)\]/u)?.[1];
  const relativePaths = [...(configuredPaths?.matchAll(/"([^"]+)"/gu) ?? [])].map(
    (match) => match[1],
  );

  if (relativePaths.length === 0) {
    throw new Error("No db.seed.sql_paths were found in supabase/config.toml");
  }

  const databaseSection = config.match(/\[db\]([\s\S]*?)(?=\n\[|$)/u)?.[1];
  const port = databaseSection?.match(/^port\s*=\s*(\d+)$/mu)?.[1];
  if (!port) {
    throw new Error("No db.port was found in supabase/config.toml");
  }

  return {
    databaseUrl: `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`,
    seedPaths: relativePaths.map((relativePath) =>
      path.resolve(supabaseDirectory, relativePath),
    ),
  };
}

const snapshotQuery = `
select jsonb_build_object(
  'rule_set', (
    select to_jsonb(rule_set) from public.rule_sets as rule_set
    where id = '${initialRuleSetId}'
  ),
  'global_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.rule_set_id)
    from public.global_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'channel_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.channel_type_code)
    from public.channel_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'channel_ability_weights', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.id)
    from public.channel_ability_weights as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'rule_set_specialties', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.specialty_code)
    from public.rule_set_specialties as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'posting_frequency_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.videos_per_week)
    from public.posting_frequency_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'idea_score_band_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.min_score)
    from public.idea_score_band_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'equipment_tier_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.equipment_type_code, rule_row.tier)
    from public.equipment_tier_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'feature_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.feature_code)
    from public.feature_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'action_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.action_code)
    from public.action_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'sponsorship_reward_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.min_subscribers)
    from public.sponsorship_reward_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'goal_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.stage_number)
    from public.goal_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'event_category_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.category_code)
    from public.event_category_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'event_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.event_definition_code)
    from public.event_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'health_risk_rules', (
    select jsonb_agg(to_jsonb(rule_row) order by rule_row.min_energy)
    from public.health_risk_rules as rule_row where rule_set_id = '${initialRuleSetId}'
  ),
  'system_idea_templates', (
    select jsonb_agg(to_jsonb(template) order by template.code)
    from public.system_idea_templates as template
    where exists (
      select 1 from public.rule_set_system_ideas as association
      where association.rule_set_id = '${initialRuleSetId}'
        and association.system_idea_template_id = template.id
    )
  ),
  'rule_set_system_ideas', (
    select jsonb_agg(to_jsonb(association) order by template.code)
    from public.rule_set_system_ideas as association
    join public.system_idea_templates as template on template.id = association.system_idea_template_id
    where association.rule_set_id = '${initialRuleSetId}'
  )
)::text;
`;

function takeSnapshot(databaseUrl) {
  return run(
    "psql",
    [databaseUrl, "--no-psqlrc", "--tuples-only", "--no-align", "--set", "ON_ERROR_STOP=1", "--command", snapshotQuery],
    { capture: true },
  );
}

async function main() {
  const { databaseUrl, seedPaths } = await readLocalSeedConfiguration();
  console.log("Resetting the local database and applying the first seed...");
  run("supabase", ["db", "reset", "--local"]);

  console.log("Capturing the first seed snapshot...");
  const firstSnapshot = takeSnapshot(databaseUrl);
  const parsedSnapshot = JSON.parse(firstSnapshot);

  if (
    parsedSnapshot.rule_set?.status !== "active" ||
    parsedSnapshot.system_idea_templates?.length !== 650 ||
    parsedSnapshot.rule_set_system_ideas?.length !== 650
  ) {
    throw new Error("The first seed did not create an active rule set with 650 ideas and associations");
  }

  console.log("Applying the same seed files to the same database a second time...");
  run("psql", [
    databaseUrl,
    "--no-psqlrc",
    "--set",
    "ON_ERROR_STOP=1",
    ...seedPaths.flatMap((seedPath) => ["--file", seedPath]),
  ]);

  console.log("Comparing the second seed snapshot...");
  const secondSnapshot = takeSnapshot(databaseUrl);
  if (secondSnapshot !== firstSnapshot) {
    throw new Error("Seed snapshot changed after the second execution");
  }

  console.log("Seed idempotency passed: counts, UUIDs, contents, status, and published_at are unchanged.");
}

await main();
