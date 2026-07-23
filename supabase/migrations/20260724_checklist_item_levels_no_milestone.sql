-- Per-level completion for a level-based item that has NO milestone assigned.
-- milestone_item_levels can't represent this (milestone_id is NOT NULL there), and most
-- level-based items in practice never get a milestone assignment at all — this table lets
-- level gating apply directly to the item's own completion in that case.
CREATE TABLE IF NOT EXISTS checklist_item_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  checklist_item_id uuid NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  level_id uuid NOT NULL REFERENCES project_levels(id) ON DELETE CASCADE,
  completed_at timestamptz,
  completed_by uuid REFERENCES auth.users(id),
  UNIQUE (checklist_item_id, level_id)
);
ALTER TABLE checklist_item_levels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read checklist item levels" ON checklist_item_levels FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM checklists c JOIN project_members mbr ON mbr.project_id = c.project_id
    WHERE c.id = checklist_item_levels.checklist_item_id AND mbr.user_id = auth.uid()
  )
);
CREATE POLICY "members write checklist item levels" ON checklist_item_levels FOR ALL USING (
  EXISTS (
    SELECT 1 FROM checklists c JOIN project_members mbr ON mbr.project_id = c.project_id
    WHERE c.id = checklist_item_levels.checklist_item_id AND mbr.user_id = auth.uid()
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM checklists c JOIN project_members mbr ON mbr.project_id = c.project_id
    WHERE c.id = checklist_item_levels.checklist_item_id AND mbr.user_id = auth.uid()
  )
);
GRANT SELECT, INSERT, UPDATE, DELETE ON checklist_item_levels TO authenticated;
