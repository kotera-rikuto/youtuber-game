import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateSystemIdeas } from "./validate-system-ideas.mjs";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outputPath = path.join(repoRoot, "supabase", "seeds", "010_system_ideas.sql");
const initialRuleSetId = "00000000-0000-4000-8000-000000000001";

function escapeSqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function renderNullableSqlString(value) {
  return value === null ? "null" : escapeSqlString(value);
}

function renderSeedRow(idea) {
  return `  (${[
    escapeSqlString(idea.code),
    escapeSqlString(idea.channelTypeCode),
    renderNullableSqlString(idea.specialtyCode),
    escapeSqlString(idea.title),
    escapeSqlString(idea.description),
    idea.enabled ? "true" : "false",
  ].join(", ")})`;
}

export function renderSystemIdeasSeed(collections) {
  const ideas = collections.flatMap((collection) =>
    collection.data.ideas.map((idea) => ({
      ...idea,
      channelTypeCode: collection.data.channelTypeCode,
      specialtyCode: collection.data.specialtyCode ?? null,
    })),
  );
  const rows = ideas.map(renderSeedRow).join(",\n");

  return `-- This file is generated from data/system-ideas/**/*.json.
-- Do not edit it manually. Run npm run system-ideas:seed:generate instead.

begin;

create temporary table expected_system_ideas (
  code text primary key,
  channel_type_code text not null,
  specialty_code text,
  title text not null,
  description text not null,
  enabled boolean not null
) on commit drop;

insert into expected_system_ideas (
  code, channel_type_code, specialty_code, title, description, enabled
)
values
${rows};

do $seed_guard$
declare
  initial_status text;
begin
  select status into initial_status
  from public.rule_sets
  where id = '${initialRuleSetId}';

  if initial_status is null then
    raise exception 'Initial rule set ${initialRuleSetId} does not exist';
  end if;

  if initial_status = 'retired' then
    raise exception 'Initial rule set 1.0.0 is retired and cannot be reseeded';
  end if;

  if exists (
    select 1
    from expected_system_ideas as expected
    join public.system_idea_templates as actual on actual.code = expected.code
    where row(
      actual.channel_type_code,
      actual.specialty_code,
      actual.title,
      actual.description,
      actual.enabled
    ) is distinct from row(
      expected.channel_type_code,
      expected.specialty_code,
      expected.title,
      expected.description,
      expected.enabled
    )
      and exists (
        select 1
        from public.rule_set_system_ideas as association
        join public.rule_sets as referenced_rule_set on referenced_rule_set.id = association.rule_set_id
        where association.system_idea_template_id = actual.id
          and referenced_rule_set.status <> 'draft'
      )
  ) then
    raise exception 'A published system idea differs from the JSON seed';
  end if;
end;
$seed_guard$;

insert into public.system_idea_templates (
  code, channel_type_code, specialty_code, title, description, enabled
)
select
  expected.code,
  expected.channel_type_code,
  expected.specialty_code,
  expected.title,
  expected.description,
  expected.enabled
from expected_system_ideas as expected
where exists (
  select 1
  from public.rule_sets
  where id = '${initialRuleSetId}'
    and status = 'draft'
)
on conflict (code) do update
set
  channel_type_code = excluded.channel_type_code,
  specialty_code = excluded.specialty_code,
  title = excluded.title,
  description = excluded.description,
  enabled = excluded.enabled
where row(
  system_idea_templates.channel_type_code,
  system_idea_templates.specialty_code,
  system_idea_templates.title,
  system_idea_templates.description,
  system_idea_templates.enabled
) is distinct from row(
  excluded.channel_type_code,
  excluded.specialty_code,
  excluded.title,
  excluded.description,
  excluded.enabled
);

insert into public.rule_set_system_ideas (
  rule_set_id, system_idea_template_id, enabled
)
select
  '${initialRuleSetId}',
  template.id,
  true
from expected_system_ideas as expected
join public.system_idea_templates as template on template.code = expected.code
where exists (
  select 1
  from public.rule_sets
  where id = '${initialRuleSetId}'
    and status = 'draft'
)
on conflict (rule_set_id, system_idea_template_id) do update
set enabled = excluded.enabled
where rule_set_system_ideas.enabled is distinct from excluded.enabled;

do $seed_validation$
begin
  if (select count(*) from expected_system_ideas) <> 650 then
    raise exception 'System idea seed must contain exactly 650 ideas';
  end if;

  if exists (
    select 1
    from expected_system_ideas as expected
    left join public.system_idea_templates as actual on actual.code = expected.code
    where actual.id is null
      or row(
        actual.channel_type_code,
        actual.specialty_code,
        actual.title,
        actual.description,
        actual.enabled
      ) is distinct from row(
        expected.channel_type_code,
        expected.specialty_code,
        expected.title,
        expected.description,
        expected.enabled
      )
  ) then
    raise exception 'Database system ideas do not match the JSON seed';
  end if;

  if (
    select count(*)
    from public.rule_set_system_ideas
    where rule_set_id = '${initialRuleSetId}'
  ) <> 650 or exists (
    select 1
    from public.rule_set_system_ideas as association
    join public.system_idea_templates as template on template.id = association.system_idea_template_id
    left join expected_system_ideas as expected on expected.code = template.code
    where association.rule_set_id = '${initialRuleSetId}'
      and (expected.code is null or not association.enabled)
  ) then
    raise exception 'Initial rule set associations do not exactly match the 650 JSON ideas';
  end if;
end;
$seed_validation$;

commit;
`;
}

async function generateExpectedSql() {
  const { collections, errors } = await validateSystemIdeas();
  if (errors.length > 0) {
    throw new Error(
      `System idea validation failed:\n${errors.map((error) => `- ${error}`).join("\n")}`,
    );
  }

  return renderSystemIdeasSeed(collections);
}

async function main() {
  const expectedSql = await generateExpectedSql();
  const isCheck = process.argv.includes("--check");

  if (isCheck) {
    let actualSql = "";
    try {
      actualSql = await readFile(outputPath, "utf8");
    } catch {
      // A missing generated file is reported by the same sync error below.
    }

    if (actualSql !== expectedSql) {
      console.error(
        "supabase/seeds/010_system_ideas.sql is out of date; run npm run system-ideas:seed:generate",
      );
      process.exitCode = 1;
      return;
    }

    console.log("System idea seed SQL is synchronized with the JSON source.");
    return;
  }

  await writeFile(outputPath, expectedSql, "utf8");
  console.log("Generated supabase/seeds/010_system_ideas.sql from 650 validated ideas.");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
