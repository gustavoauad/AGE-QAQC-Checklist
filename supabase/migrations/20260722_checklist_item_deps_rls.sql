-- checklist_item_dependencies was created (20260629_checklist_item_deps.sql) without
-- RLS policies or table-level GRANTs. A later security pass enabled RLS ad hoc via the
-- SQL editor, but no matching GRANT was added — so every write silently failed with
-- 42501 (permission denied), which is why dependencies disappeared after closing and
-- reopening Project Setup. This migration makes both the policies and the grant
-- explicit and idempotent.

ALTER TABLE checklist_item_dependencies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members read checklist item dependencies" ON checklist_item_dependencies;
CREATE POLICY "members read checklist item dependencies" ON checklist_item_dependencies
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM checklists c
      JOIN project_members mbr ON mbr.project_id = c.project_id
      WHERE c.id = checklist_item_dependencies.item_id
        AND mbr.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "pm and qaqc write checklist item dependencies" ON checklist_item_dependencies;
CREATE POLICY "pm and qaqc write checklist item dependencies" ON checklist_item_dependencies
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM checklists c
      JOIN project_members mbr ON mbr.project_id = c.project_id
      WHERE c.id = checklist_item_dependencies.item_id
        AND mbr.user_id = auth.uid()
        AND mbr.role IN ('project_manager', 'qaqc')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM checklists c
      JOIN project_members mbr ON mbr.project_id = c.project_id
      WHERE c.id = checklist_item_dependencies.item_id
        AND mbr.user_id = auth.uid()
        AND mbr.role IN ('project_manager', 'qaqc')
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON checklist_item_dependencies TO authenticated;

-- Needed so the INSERT ... ON CONFLICT (item_id, depends_on_item_id) upsert used by
-- toggleDep() resolves to the existing UNIQUE(item_id, depends_on_item_id) constraint.
