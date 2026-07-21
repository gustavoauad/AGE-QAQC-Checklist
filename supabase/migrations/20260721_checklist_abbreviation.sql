-- Lets a PM (project level) or org admin (organization level) override the
-- auto-derived reference-code prefix (e.g. "GENE") for a checklist with a
-- custom abbreviation of their choosing. Falls back to the auto-derived
-- prefix from the label when not set. Existing table-level GRANTs already
-- cover new columns, so no additional grants are needed here.
ALTER TABLE project_checklist_config ADD COLUMN IF NOT EXISTS abbreviation text;
ALTER TABLE org_checklist_config      ADD COLUMN IF NOT EXISTS abbreviation text;
