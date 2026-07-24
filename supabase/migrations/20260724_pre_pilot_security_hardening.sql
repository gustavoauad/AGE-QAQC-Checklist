-- ============================================================================
-- Pre-pilot security hardening. Several tables had a leftover, overly-broad
-- policy (from early development) sitting alongside proper scoped ones —
-- since Postgres RLS OR's every applicable policy together, the broad one
-- silently granted full cross-tenant access regardless of the narrow ones.
-- ============================================================================

-- ── projects: ANY authenticated user had full CRUD on every project in every
-- organization. Replace with real ownership/membership-scoped policies.
DROP POLICY IF EXISTS "Authenticated full access to projects" ON projects;

CREATE POLICY "creator can create projects" ON projects
  FOR INSERT WITH CHECK (
    created_by = auth.uid()
    AND organization_id IN (SELECT get_my_org_ids())
  );

CREATE POLICY "pm or org admin can update projects" ON projects
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM project_members pm WHERE pm.project_id = projects.id AND pm.user_id = auth.uid() AND pm.role = 'project_manager')
    OR organization_id IN (SELECT get_my_admin_org_ids())
  );

-- ── checklists: same issue — any authenticated user could read/write/delete
-- every checklist item in every project. checklists had NO other policy at
-- all, so this replaces it with the only real access pattern the app uses:
-- project members, the project's creator (covers the create-project race
-- where checklists are seeded in parallel with the member row), or an org
-- admin of that project's org (Project Setup is reachable by org admins).
DROP POLICY IF EXISTS "Authenticated full access to checklists" ON checklists;

CREATE POLICY "project members or org admins manage checklists" ON checklists
  FOR ALL USING (
    project_id IN (SELECT get_my_project_ids())
    OR EXISTS (SELECT 1 FROM projects p WHERE p.id = checklists.project_id AND p.created_by = auth.uid())
    OR EXISTS (SELECT 1 FROM projects p WHERE p.id = checklists.project_id AND p.organization_id IN (SELECT get_my_admin_org_ids()))
  ) WITH CHECK (
    project_id IN (SELECT get_my_project_ids())
    OR EXISTS (SELECT 1 FROM projects p WHERE p.id = checklists.project_id AND p.created_by = auth.uid())
    OR EXISTS (SELECT 1 FROM projects p WHERE p.id = checklists.project_id AND p.organization_id IN (SELECT get_my_admin_org_ids()))
  );

-- ── organization_members: "insert own or admin inserts" had WITH CHECK(true) —
-- ANY authenticated user could insert THEMSELVES as 'admin' of ANY
-- organization, then use that to escalate into every org-scoped table
-- (org checklists, org members, projects). The founding-admin case is
-- already handled by the SECURITY DEFINER create_organization() RPC, which
-- bypasses RLS — this policy had zero legitimate remaining use.
DROP POLICY IF EXISTS "insert own or admin inserts" ON organization_members;

-- ── project_members: "Anyone can insert project members" had WITH CHECK(true) —
-- any authenticated user could add themselves (or anyone) to any project
-- with any role, incl. project_manager. Replace with the three real patterns:
-- the project's own creator, an existing PM of that project, or an org admin.
DROP POLICY IF EXISTS "Anyone can insert project members" ON project_members;

CREATE POLICY "creator, pm, or org admin can add project members" ON project_members
  FOR INSERT WITH CHECK (
    (user_id = auth.uid() AND EXISTS (SELECT 1 FROM projects p WHERE p.id = project_members.project_id AND p.created_by = auth.uid()))
    OR EXISTS (SELECT 1 FROM project_members pm WHERE pm.project_id = project_members.project_id AND pm.user_id = auth.uid() AND pm.role = 'project_manager')
    OR EXISTS (SELECT 1 FROM projects p WHERE p.id = project_members.project_id AND p.organization_id IN (SELECT get_my_admin_org_ids()))
  );

-- ── checklist_comments: "members can update comments" was USING(true)/CHECK(true) —
-- any authenticated user could edit or un/resolve QA/QC flags on any comment
-- anywhere. Scope to the same "project member of that item's project" rule
-- already used by the read/insert policies on this table.
DROP POLICY IF EXISTS "members can update comments" ON checklist_comments;

CREATE POLICY "project members update comments" ON checklist_comments
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM checklists c JOIN project_members pm ON pm.project_id = c.project_id WHERE c.id = checklist_comments.checklist_item_id AND pm.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM checklists c JOIN project_members pm ON pm.project_id = c.project_id WHERE c.id = checklist_comments.checklist_item_id AND pm.user_id = auth.uid())
  );

-- ── notifications: "auth_insert" allowed any authenticated user to forge a
-- notification for ANY other user (phishing/spam risk). Scope INSERT to the
-- three real callers: notifying yourself, a PM notifying someone they just
-- added to their project, or an org admin notifying someone they just added
-- to their org.
DROP POLICY IF EXISTS "auth_insert" ON notifications;

CREATE POLICY "self, pm, or org admin can insert notifications" ON notifications
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM project_members pm WHERE pm.project_id = notifications.project_id AND pm.user_id = auth.uid() AND pm.role = 'project_manager')
    OR EXISTS (SELECT 1 FROM organization_members om WHERE om.user_id = auth.uid() AND om.role = 'admin')
  );

-- ── project_invite_tokens: two duplicate SELECT policies with qual=true let
-- ANY authenticated user list every invite token (and its plaintext secret)
-- for every project across every org, defeating the whole point of the
-- token being a secret. Redemption moves to a SECURITY DEFINER RPC below
-- that validates the token server-side, so the client no longer needs
-- direct SELECT access to tokens by value — only the creator does, to show/
-- copy/revoke their own generated links (already covered by the existing
-- "manage_own_tokens" / "pm manage own tokens" ALL policies).
DROP POLICY IF EXISTS "anyone can read tokens" ON project_invite_tokens;
DROP POLICY IF EXISTS "read_tokens" ON project_invite_tokens;

-- SECURITY DEFINER: validates the token server-side (expiry, existence) and
-- performs the join atomically, so the client never needs broad SELECT
-- access to the tokens table to redeem an invite link.
CREATE OR REPLACE FUNCTION public.redeem_project_invite(p_token text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_token   project_invite_tokens;
  v_project projects;
  v_already_member boolean;
BEGIN
  SELECT * INTO v_token FROM project_invite_tokens
   WHERE token = p_token AND expires_at >= now();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_or_expired_token';
  END IF;

  SELECT * INTO v_project FROM projects WHERE id = v_token.project_id;

  SELECT EXISTS(
    SELECT 1 FROM project_members WHERE project_id = v_token.project_id AND user_id = auth.uid()
  ) INTO v_already_member;

  IF NOT v_already_member THEN
    INSERT INTO project_members (project_id, user_id, role, invited_by)
    VALUES (v_token.project_id, auth.uid(), v_token.role, v_token.created_by)
    ON CONFLICT (project_id, user_id) DO NOTHING;

    INSERT INTO notifications (user_id, project_id, type, title, body)
    VALUES (
      auth.uid(), v_token.project_id, 'project_join',
      'Joined "' || v_project.name || '"',
      'You joined as ' || replace(v_token.role, '_', ' ') || '. The project is now in your list.'
    );
  END IF;

  RETURN json_build_object(
    'project_id', v_project.id,
    'project_name', v_project.name,
    'role', v_token.role,
    'already_member', v_already_member
  );
END;
$$;

GRANT EXECUTE ON FUNCTION redeem_project_invite(text) TO authenticated;
