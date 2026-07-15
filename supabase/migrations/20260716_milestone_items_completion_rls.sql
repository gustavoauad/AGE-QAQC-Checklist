-- Engineers/drafters now need to stamp completed_at/completed_by on
-- milestone_items when marking their own checklist items complete — but the
-- existing "pm and qaqc write milestone items" policy restricts ALL writes
-- (insert/update/delete) to project_manager/qaqc, which would silently block
-- their completion writes via RLS.
--
-- Split the policy: INSERT/DELETE (assigning items to milestones, a Project
-- Setup concern) stay PM/QAQC-only. UPDATE opens to any project member, but a
-- trigger enforces the same two invariants RLS can't express at column level:
--   1. Only PM/QAQC may change days_before (a deadline-configuration field).
--   2. QAQC may never set completed_at/completed_by — mirrors the checklists
--      status lock (see 20260715_qaqc_cannot_change_status.sql) so QAQC can't
--      achieve the same effect by writing milestone completion directly.

DROP POLICY IF EXISTS "pm and qaqc write milestone items" ON milestone_items;

CREATE POLICY "pm and qaqc assign milestone items" ON milestone_items
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM project_milestones pm
      JOIN project_members mbr ON mbr.project_id = pm.project_id
      WHERE pm.id = milestone_items.milestone_id
        AND mbr.user_id = auth.uid()
        AND mbr.role IN ('project_manager', 'qaqc')
    )
  );

CREATE POLICY "pm and qaqc unassign milestone items" ON milestone_items
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM project_milestones pm
      JOIN project_members mbr ON mbr.project_id = pm.project_id
      WHERE pm.id = milestone_items.milestone_id
        AND mbr.user_id = auth.uid()
        AND mbr.role IN ('project_manager', 'qaqc')
    )
  );

CREATE POLICY "project members update milestone items" ON milestone_items
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM project_milestones pm
      JOIN project_members mbr ON mbr.project_id = pm.project_id
      WHERE pm.id = milestone_items.milestone_id
        AND mbr.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM project_milestones pm
      JOIN project_members mbr ON mbr.project_id = pm.project_id
      WHERE pm.id = milestone_items.milestone_id
        AND mbr.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION prevent_invalid_milestone_item_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_project_id uuid;
BEGIN
  SELECT project_id INTO v_project_id FROM project_milestones WHERE id = NEW.milestone_id;
  SELECT role INTO v_role FROM project_members WHERE project_id = v_project_id AND user_id = auth.uid();

  IF NEW.days_before IS DISTINCT FROM OLD.days_before AND COALESCE(v_role, '') NOT IN ('project_manager', 'qaqc') THEN
    RAISE EXCEPTION 'Only project managers or QA/QC may change milestone deadlines';
  END IF;

  IF v_role = 'qaqc' AND (
       NEW.completed_at IS DISTINCT FROM OLD.completed_at OR
       NEW.completed_by IS DISTINCT FROM OLD.completed_by
     ) THEN
    RAISE EXCEPTION 'QA/QC role cannot change milestone completion';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_invalid_milestone_item_update ON milestone_items;

CREATE TRIGGER trg_prevent_invalid_milestone_item_update
  BEFORE UPDATE ON milestone_items
  FOR EACH ROW
  EXECUTE FUNCTION prevent_invalid_milestone_item_update();
