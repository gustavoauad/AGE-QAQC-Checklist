import { useState, useEffect } from "react";
import { supabase } from "./supabase";
import AuthScreen from "./components/AuthScreen";
import ProjectsDashboard from "./components/ProjectsDashboard";
import ChecklistView from "./components/ChecklistView";
import DashboardView from "./components/DashboardView";

export default function App() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [view, setView] = useState("projects");
  const [selectedProject, setSelectedProject] = useState(null);
  const [userRole, setUserRole] = useState(null);
  const [inviteToast, setInviteToast] = useState(null); // { type: "success"|"error", message }

  // Store pending invite token for users who aren't logged in yet
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const token = params.get("invite");
    if (token) localStorage.setItem("pending_invite", token);
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setLoading(false);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });
    return () => subscription.unsubscribe();
  }, []);

  // Process invite token once session is available
  useEffect(() => {
    if (!session) return;
    const urlToken = new URLSearchParams(window.location.search).get("invite");
    const storedToken = localStorage.getItem("pending_invite");
    const token = urlToken || storedToken;
    if (token) {
      localStorage.removeItem("pending_invite");
      window.history.replaceState({}, "", window.location.pathname);
      processInviteToken(token, session.user.id);
    }
  }, [session]);

  const processInviteToken = async (token, userId) => {
    const { data: tokenData, error } = await supabase
      .from("project_invite_tokens")
      .select("*, project:projects(id, name)")
      .eq("token", token)
      .gte("expires_at", new Date().toISOString())
      .single();

    if (error || !tokenData) {
      setInviteToast({ type: "error", message: "Invite link is invalid or has expired." });
      setTimeout(() => setInviteToast(null), 5000);
      return;
    }

    const { data: existing } = await supabase
      .from("project_members")
      .select("id")
      .eq("project_id", tokenData.project_id)
      .eq("user_id", userId)
      .single();

    if (existing) {
      setInviteToast({ type: "info", message: `You're already a member of "${tokenData.project?.name}".` });
      setTimeout(() => setInviteToast(null), 4000);
      return;
    }

    await supabase.from("project_members").insert({
      project_id: tokenData.project_id,
      user_id: userId,
      role: tokenData.role,
      invited_by: tokenData.created_by,
    });

    await supabase.from("notifications").insert({
      user_id: userId,
      project_id: tokenData.project_id,
      type: "project_join",
      title: `Joined "${tokenData.project?.name}"`,
      body: `You joined as ${tokenData.role.replace(/_/g, " ")}. The project is now in your list.`,
    });

    setInviteToast({ type: "success", message: `✅ You've joined "${tokenData.project?.name}"! It's now in your projects list.` });
    setTimeout(() => setInviteToast(null), 6000);
  };

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    setSelectedProject(null);
    setUserRole(null);
    setView("projects");
  };

  const goToProjects = () => setView("projects");

  if (loading) {
    return (
      <div style={{ minHeight: "100vh", background: "#0f172a", display: "flex", alignItems: "center", justifyContent: "center", color: "#94a3b8", fontFamily: "Manrope, sans-serif" }}>
        Loading...
      </div>
    );
  }

  if (!session) return <AuthScreen />;

  const toastColors = {
    success: { bg: "#1a3318", border: "#4da447", color: "#7ecb7b" },
    error:   { bg: "#450a0a", border: "#ef4444", color: "#fca5a5" },
    info:    { bg: "#011a3d", border: "#0095da", color: "#33bdef" },
  };

  return (
    <>
      {inviteToast && (
        <div style={{
          position: "fixed", top: "16px", left: "50%", transform: "translateX(-50%)",
          zIndex: 1000, padding: "12px 20px", borderRadius: "10px",
          background: toastColors[inviteToast.type].bg,
          border: `1px solid ${toastColors[inviteToast.type].border}`,
          color: toastColors[inviteToast.type].color,
          fontSize: "14px", fontWeight: "600", fontFamily: "Manrope, sans-serif",
          boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
          maxWidth: "calc(100vw - 32px)", textAlign: "center",
        }}>
          {inviteToast.message}
        </div>
      )}

      {view === "checklist" && selectedProject ? (
        <ChecklistView
          project={selectedProject}
          userRole={userRole}
          session={session}
          onBack={goToProjects}
          onSignOut={handleSignOut}
          onGoToProjects={goToProjects}
        />
      ) : view === "dashboard" ? (
        <DashboardView
          session={session}
          onBack={goToProjects}
          onSignOut={handleSignOut}
          onGoToProjects={goToProjects}
        />
      ) : (
        <ProjectsDashboard
          session={session}
          onSelectProject={(project, role) => {
            setSelectedProject(project);
            setUserRole(role);
            setView("checklist");
          }}
          onShowDashboard={() => setView("dashboard")}
          onSignOut={handleSignOut}
          onGoToProjects={goToProjects}
        />
      )}
    </>
  );
}
