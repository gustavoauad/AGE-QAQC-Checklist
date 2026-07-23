-- Project levels (building floors) — a simple ordered per-project list, set up
-- in Project Setup like milestones but without dates.
CREATE TABLE IF NOT EXISTS project_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE project_levels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read levels" ON project_levels FOR SELECT USING (
  EXISTS (SELECT 1 FROM project_members WHERE project_members.project_id = project_levels.project_id AND project_members.user_id = auth.uid())
);
CREATE POLICY "managers write levels" ON project_levels FOR ALL USING (
  EXISTS (SELECT 1 FROM project_members WHERE project_members.project_id = project_levels.project_id AND project_members.user_id = auth.uid() AND project_members.role = 'project_manager')
) WITH CHECK (
  EXISTS (SELECT 1 FROM project_members WHERE project_members.project_id = project_levels.project_id AND project_members.user_id = auth.uid() AND project_members.role = 'project_manager')
);
GRANT SELECT, INSERT, UPDATE, DELETE ON project_levels TO authenticated;

-- Per-level completion for a level-based item, scoped to a specific milestone —
-- mirrors milestone_items but adds the level dimension. milestone_items.completed_at
-- for a level-based item is only ever set once every current project level has a row
-- here with completed_at set; that keeps every existing milestone-completion rule
-- (due dates, effective-status reconciliation, dashboards) working unchanged, since
-- they all just read milestone_items.completed_at as ground truth.
CREATE TABLE IF NOT EXISTS milestone_item_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  milestone_id uuid NOT NULL REFERENCES project_milestones(id) ON DELETE CASCADE,
  checklist_item_id uuid NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  level_id uuid NOT NULL REFERENCES project_levels(id) ON DELETE CASCADE,
  completed_at timestamptz,
  completed_by uuid REFERENCES auth.users(id),
  UNIQUE (milestone_id, checklist_item_id, level_id)
);
ALTER TABLE milestone_item_levels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read milestone item levels" ON milestone_item_levels FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM project_milestones pm JOIN project_members mbr ON mbr.project_id = pm.project_id
    WHERE pm.id = milestone_item_levels.milestone_id AND mbr.user_id = auth.uid()
  )
);
CREATE POLICY "members write milestone item levels" ON milestone_item_levels FOR ALL USING (
  EXISTS (
    SELECT 1 FROM project_milestones pm JOIN project_members mbr ON mbr.project_id = pm.project_id
    WHERE pm.id = milestone_item_levels.milestone_id AND mbr.user_id = auth.uid()
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM project_milestones pm JOIN project_members mbr ON mbr.project_id = pm.project_id
    WHERE pm.id = milestone_item_levels.milestone_id AND mbr.user_id = auth.uid()
  )
);
GRANT SELECT, INSERT, UPDATE, DELETE ON milestone_item_levels TO authenticated;

-- Level-based flag: set on the org template (pushed to projects like everything else).
ALTER TABLE org_checklist_items ADD COLUMN IF NOT EXISTS is_level_based boolean NOT NULL DEFAULT false;
ALTER TABLE checklists          ADD COLUMN IF NOT EXISTS is_level_based boolean NOT NULL DEFAULT false;

-- Carry is_level_based through push_checklist_to_projects.
CREATE OR REPLACE FUNCTION public.push_checklist_to_projects(
  p_project_ids  uuid[],
  p_category     text,
  p_label        text,
  p_items        jsonb,
  p_action       text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  p_project_id  uuid;
  item          jsonb;
  item_idx      int;
BEGIN
  IF EXISTS (
    SELECT 1 FROM unnest(p_project_ids) AS pid
    WHERE pid NOT IN (
      SELECT p.id FROM projects p
      JOIN organization_members om ON om.organization_id = p.organization_id
      WHERE om.user_id = auth.uid() AND om.role = 'admin'
    )
  ) THEN
    RAISE EXCEPTION 'permission denied: not an org admin for one or more target projects';
  END IF;

  FOREACH p_project_id IN ARRAY p_project_ids
  LOOP
    item_idx := 0;
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      INSERT INTO checklists
        (project_id, item_id, category, item_text, status,
         completed_by, completed_at, in_progress_by, in_progress_at,
         sub_section, sort_order, help_text, days_before_milestone, is_level_based)
      VALUES
        (p_project_id,
         item->>'item_id',
         p_category,
         item->>'item_text',
         'pending', NULL, NULL, NULL, NULL,
         NULLIF(item->>'section', ''),
         item_idx,
         NULLIF(item->>'help_text', ''),
         (item->>'days_before_milestone')::int,
         COALESCE((item->>'is_level_based')::boolean, false))
      ON CONFLICT (project_id, item_id) DO UPDATE SET
        category               = EXCLUDED.category,
        item_text               = EXCLUDED.item_text,
        sub_section             = EXCLUDED.sub_section,
        sort_order               = EXCLUDED.sort_order,
        help_text               = EXCLUDED.help_text,
        days_before_milestone   = EXCLUDED.days_before_milestone,
        is_level_based           = EXCLUDED.is_level_based,
        status         = CASE WHEN p_action = 'overwrite_keep' THEN checklists.status         ELSE 'pending' END,
        completed_by   = CASE WHEN p_action = 'overwrite_keep' THEN checklists.completed_by   ELSE NULL END,
        completed_at   = CASE WHEN p_action = 'overwrite_keep' THEN checklists.completed_at   ELSE NULL END,
        in_progress_by = CASE WHEN p_action = 'overwrite_keep' THEN checklists.in_progress_by ELSE NULL END,
        in_progress_at = CASE WHEN p_action = 'overwrite_keep' THEN checklists.in_progress_at ELSE NULL END;

      item_idx := item_idx + 1;
    END LOOP;

    DELETE FROM checklists
     WHERE project_id = p_project_id
       AND category   = p_category
       AND item_id NOT IN (
         SELECT value->>'item_id' FROM jsonb_array_elements(p_items)
       );

    INSERT INTO project_checklist_config (project_id, category, enabled, label)
    VALUES (p_project_id, p_category, true, p_label)
    ON CONFLICT (project_id, category)
    DO UPDATE SET enabled = true, label = p_label;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION push_checklist_to_projects(uuid[], text, text, jsonb, text) TO authenticated;
