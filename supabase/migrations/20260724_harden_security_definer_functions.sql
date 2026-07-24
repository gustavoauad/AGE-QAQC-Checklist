-- Two defense-in-depth gaps flagged by the Supabase security linter, both
-- affecting every SECURITY DEFINER function in the schema:
--
-- 1) Postgres grants EXECUTE on new functions to PUBLIC by default. Our
--    GRANT ... TO authenticated calls never revoked that implicit PUBLIC
--    grant, so every one of these functions (including redeem_project_invite,
--    create_organization, and the get_my_*_ids() helpers used throughout RLS)
--    is also callable by the unauthenticated `anon` role. Most just no-op
--    for anon since auth.uid() is null, but it's unnecessary surface area —
--    revoke PUBLIC/anon explicitly and keep only the authenticated grant.
--
-- 2) None of these functions pin search_path, so if a lower-privileged role
--    could ever create objects in a schema earlier in the caller's
--    search_path, a SECURITY DEFINER function could be tricked into
--    resolving an attacker-controlled object instead of the intended one.
--    Pin search_path = public, pg_temp on each.
DO $$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid, p.proname,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef = true
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public, pg_temp', fn.proname, fn.args);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC', fn.proname, fn.args);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM anon', fn.proname, fn.args);
  END LOOP;
END $$;

-- Re-grant EXECUTE to authenticated for the functions the app actually calls
-- from the client (handle_new_user/rls_auto_enable/prevent_* are trigger-only
-- and need no direct grant).
GRANT EXECUTE ON FUNCTION create_organization(text) TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_org_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_admin_org_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_project_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION is_project_manager_of(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION redeem_project_invite(text) TO authenticated;
GRANT EXECUTE ON FUNCTION push_checklist_to_project(uuid, text, text, jsonb, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION push_checklist_to_projects(uuid[], text, text, jsonb, text, text) TO authenticated;
