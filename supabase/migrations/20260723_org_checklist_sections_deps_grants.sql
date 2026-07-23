-- org_checklist_sections has RLS policies (20260626_sections.sql) but was missing the
-- table-level GRANT for the authenticated role — the same root cause fixed earlier this
-- session for milestone_items and checklist_item_dependencies. Without the GRANT, every
-- read/write silently fails with 42501 (permission denied), which meant the org-level
-- "Sections" feature never actually loaded any data.
GRANT SELECT, INSERT, UPDATE, DELETE ON org_checklist_sections TO authenticated;

-- org_checklist_item_dependencies (20260629_checklist_item_deps.sql) never had RLS
-- enabled or any policies at all, on top of missing the GRANT — org-level template
-- item dependencies could never be read or written by any user.
ALTER TABLE org_checklist_item_dependencies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "org members read checklist item dependencies" ON org_checklist_item_dependencies;
CREATE POLICY "org members read checklist item dependencies" ON org_checklist_item_dependencies
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM organization_members
      WHERE organization_members.organization_id = org_checklist_item_dependencies.org_id
        AND organization_members.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "org admins write checklist item dependencies" ON org_checklist_item_dependencies;
CREATE POLICY "org admins write checklist item dependencies" ON org_checklist_item_dependencies
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM organization_members
      WHERE organization_members.organization_id = org_checklist_item_dependencies.org_id
        AND organization_members.user_id = auth.uid()
        AND organization_members.role = 'admin'
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM organization_members
      WHERE organization_members.organization_id = org_checklist_item_dependencies.org_id
        AND organization_members.user_id = auth.uid()
        AND organization_members.role = 'admin'
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON org_checklist_item_dependencies TO authenticated;
