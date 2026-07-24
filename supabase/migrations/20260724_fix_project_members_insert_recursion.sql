-- The new "creator, pm, or org admin can add project members" INSERT policy
-- (added in pre_pilot_security_hardening) directly queried project_members
-- from inside its own WITH CHECK (to test "is the caller already a PM of
-- this project"). Postgres refuses this with "infinite recursion detected
-- in policy for relation project_members" — evaluating that subquery would
-- require re-applying project_members' own RLS policies, which Postgres
-- can't prove terminates, even though this particular case isn't actually
-- unbounded. Same fix pattern as the existing get_my_project_ids()/
-- get_my_admin_org_ids() helpers: move the self-lookup into a SECURITY
-- DEFINER function, which bypasses RLS entirely.
CREATE OR REPLACE FUNCTION public.is_project_manager_of(p_project_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM project_members
    WHERE project_id = p_project_id AND user_id = auth.uid() AND role = 'project_manager'
  );
$$;

GRANT EXECUTE ON FUNCTION is_project_manager_of(uuid) TO authenticated;

DROP POLICY IF EXISTS "creator, pm, or org admin can add project members" ON project_members;

CREATE POLICY "creator, pm, or org admin can add project members" ON project_members
  FOR INSERT WITH CHECK (
    (user_id = auth.uid() AND EXISTS (SELECT 1 FROM projects p WHERE p.id = project_members.project_id AND p.created_by = auth.uid()))
    OR is_project_manager_of(project_members.project_id)
    OR EXISTS (SELECT 1 FROM projects p WHERE p.id = project_members.project_id AND p.organization_id IN (SELECT get_my_admin_org_ids()))
  );
