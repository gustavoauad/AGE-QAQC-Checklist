-- Lets a PM set a default "days before milestone" value for a whole checklist
-- (category) even for milestones that aren't yet assigned to any of its items.
-- When an item is later assigned to that milestone, it inherits this default
-- instead of starting with no deadline. Scoped by category (not project_id
-- alone) since the "apply to all" action in Project Setup is per-checklist.
CREATE TABLE IF NOT EXISTS project_checklist_milestone_defaults (
  project_id   uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  category     text NOT NULL,
  milestone_id uuid NOT NULL REFERENCES project_milestones(id) ON DELETE CASCADE,
  days_before  int,
  PRIMARY KEY (category, milestone_id)
);

ALTER TABLE project_checklist_milestone_defaults ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read checklist milestone defaults" ON project_checklist_milestone_defaults
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM project_members mbr
      WHERE mbr.project_id = project_checklist_milestone_defaults.project_id
        AND mbr.user_id = auth.uid()
    )
  );

CREATE POLICY "pm and qaqc write checklist milestone defaults" ON project_checklist_milestone_defaults
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM project_members mbr
      WHERE mbr.project_id = project_checklist_milestone_defaults.project_id
        AND mbr.user_id = auth.uid()
        AND mbr.role IN ('project_manager', 'qaqc')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM project_members mbr
      WHERE mbr.project_id = project_checklist_milestone_defaults.project_id
        AND mbr.user_id = auth.uid()
        AND mbr.role IN ('project_manager', 'qaqc')
    )
  );

-- RLS restricts which ROWS a role can touch; the role still needs the base SQL
-- privilege on the table itself, or every write fails with 42501 regardless of policy.
GRANT SELECT, INSERT, UPDATE, DELETE ON project_checklist_milestone_defaults TO authenticated;
