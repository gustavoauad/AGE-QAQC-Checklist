-- Track completion per (checklist item, milestone) pair, not just a single
-- overall status on checklists. A project can have several deadlines (SD/DD/CD),
-- and an item can be signed off for one without being signed off for another —
-- this is the source of truth the app now reads to render per-milestone due
-- chips ("done" / "past due" / "no deadline") and to derive the item's overall
-- status when it's assigned to 2+ milestones.
ALTER TABLE milestone_items ADD COLUMN IF NOT EXISTS completed_at timestamptz;
ALTER TABLE milestone_items ADD COLUMN IF NOT EXISTS completed_by uuid REFERENCES auth.users(id);
