import "server-only";

import type {
  SystemIdeaCycle,
  SystemIdeaCycleEntry,
  SystemIdeaPoolCandidate,
} from "@/backend/domain/game/system-idea-cycle";
import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";

export type SystemIdeaPoolRow = {
  id: string;
  system_idea_templates: {
    id: string;
    title: string;
  };
};

export type SystemIdeaCycleRow = { id: string; cycle_number: number };
export type SystemIdeaCycleEntryRow = {
  id: string;
  cycle_id: string;
  rule_set_system_idea_id: string;
  position: number;
};
export type SystemIdeaAssociationRow = {
  id: string;
  system_idea_template_id: string;
};
export type SystemIdeaTemplateRow = { id: string; title: string };

export function mapSystemIdeaPool(
  rows: readonly SystemIdeaPoolRow[],
): readonly SystemIdeaPoolCandidate[] {
  return rows.map((row) => ({
    ruleSetSystemIdeaId: row.id,
    templateId: row.system_idea_templates.id,
    title: row.system_idea_templates.title,
  }));
}

export function mapSystemIdeaCycles(
  cycles: readonly SystemIdeaCycleRow[],
  entries: readonly SystemIdeaCycleEntryRow[],
  associations: readonly SystemIdeaAssociationRow[],
  templates: readonly SystemIdeaTemplateRow[],
  usedEntryIds: ReadonlySet<string>,
): readonly SystemIdeaCycle[] {
  const associationById = new Map(
    associations.map((association) => [association.id, association]),
  );
  const templateById = new Map(
    templates.map((template) => [template.id, template]),
  );
  const entriesByCycleId = new Map<string, SystemIdeaCycleEntry[]>();

  for (const entry of entries) {
    const association = associationById.get(entry.rule_set_system_idea_id);
    const template = association
      ? templateById.get(association.system_idea_template_id)
      : undefined;
    if (!association || !template) {
      throw new DataIntegrityError(
        "A system idea cycle entry has a missing association.",
      );
    }

    const mappedEntry: SystemIdeaCycleEntry = {
      id: entry.id,
      ruleSetSystemIdeaId: association.id,
      templateId: template.id,
      title: template.title,
      position: entry.position,
      isUsed: usedEntryIds.has(entry.id),
    };
    const cycleEntries = entriesByCycleId.get(entry.cycle_id) ?? [];
    cycleEntries.push(mappedEntry);
    entriesByCycleId.set(entry.cycle_id, cycleEntries);
  }

  return cycles.map((cycle) => ({
    id: cycle.id,
    cycleNumber: cycle.cycle_number,
    entries: entriesByCycleId.get(cycle.id) ?? [],
  }));
}
