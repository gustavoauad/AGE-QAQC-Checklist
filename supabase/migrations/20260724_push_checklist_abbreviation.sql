-- push_checklist_to_projects never carried the category's reference-code abbreviation
-- (org_checklist_config.abbreviation) to the pushed project, so a custom abbreviation
-- set at the org level silently never reached project_checklist_config.abbreviation —
-- the project just kept whatever it already had (or the auto-derived default).
--
-- Adding a parameter creates a new overload rather than replacing the old one (the
-- parameter list changed), so the stale 5-arg version is dropped explicitly to avoid
-- two ambiguous overloads sitting side by side.
DROP FUNCTION IF EXISTS push_checklist_to_projects(uuid[], text, text, jsonb, text);

CREATE OR REPLACE FUNCTION public.push_checklist_to_projects(
  p_project_ids  uuid[],
  p_category     text,
  p_label        text,
  p_items        jsonb,
  p_action       text,
  p_abbreviation text DEFAULT NULL
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

    INSERT INTO project_checklist_config (project_id, category, enabled, label, abbreviation)
    VALUES (p_project_id, p_category, true, p_label, p_abbreviation)
    ON CONFLICT (project_id, category)
    DO UPDATE SET enabled = true, label = p_label, abbreviation = p_abbreviation;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION push_checklist_to_projects(uuid[], text, text, jsonb, text, text) TO authenticated;
