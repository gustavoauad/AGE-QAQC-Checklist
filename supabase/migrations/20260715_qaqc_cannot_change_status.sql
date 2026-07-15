-- QAQC must not be able to change a checklist item's status, even by calling
-- the Supabase API directly (bypassing the UI's client-side canChangeStatus
-- check). RLS alone can't express "this role may UPDATE the row but not this
-- column" since all authenticated users share the same Postgres role — the
-- qaqc/project_manager/engineer/drafter distinction lives in project_members,
-- not in Postgres roles. A BEFORE UPDATE trigger is the enforcement point
-- that actually can't be bypassed from the client.

CREATE OR REPLACE FUNCTION prevent_qaqc_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  SELECT role INTO v_role
    FROM project_members
   WHERE project_id = NEW.project_id
     AND user_id = auth.uid();

  IF v_role = 'qaqc' AND (
       NEW.status         IS DISTINCT FROM OLD.status OR
       NEW.completed_by   IS DISTINCT FROM OLD.completed_by OR
       NEW.completed_at   IS DISTINCT FROM OLD.completed_at OR
       NEW.in_progress_by IS DISTINCT FROM OLD.in_progress_by OR
       NEW.in_progress_at IS DISTINCT FROM OLD.in_progress_at
     ) THEN
    RAISE EXCEPTION 'QA/QC role cannot change checklist item status';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_qaqc_status_change ON checklists;

CREATE TRIGGER trg_prevent_qaqc_status_change
  BEFORE UPDATE ON checklists
  FOR EACH ROW
  EXECUTE FUNCTION prevent_qaqc_status_change();
