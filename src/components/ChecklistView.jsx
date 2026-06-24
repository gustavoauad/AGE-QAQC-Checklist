import { useState, useEffect } from "react";
import { supabase } from "../supabase";
import { CATEGORIES } from "../checklistTemplate";

const CATEGORY_PERMISSIONS = {
  project_manager: "all",
  engineer: "non-drafting",
  drafter: "drafting-only",
};

export default function ChecklistView({ project, userRole, session, onBack, onSignOut }) {
  const [checklists, setChecklists] = useState([]);
  const [loading, setLoading] = useState(true);
  const [activeCategory, setActiveCategory] = useState("general");
  const [updating, setUpdating] = useState(null);

  useEffect(() => {
    fetchChecklists();
  }, []);

  const fetchChecklists = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("checklists")
      .select("*")
      .eq("project_id", project.id)
      .order("category")
      .order("item_id");
    if (!error) setChecklists(data || []);
    setLoading(false);
  };

  const canEdit = (category) => {
    if (userRole === "project_manager") return true;
    if (userRole === "engineer") return category !== "drafting";
    if (userRole === "drafter") return category === "drafting";
    return false;
  };

  const handleStatusChange = async (item, newStatus) => {
    if (!canEdit(item.category)) return;
    setUpdating(item.id);
    const { error } = await supabase
      .from("checklists")
      .update({
        status: newStatus,
        updated_by: session.user.id,
        updated_at: new Date().toISOString(),
      })
      .eq("id", item.id);
    if (!error) {
      setChecklists((prev) =>
        prev.map((c) => c.id === item.id ? { ...c, status: newStatus } : c)
      );
    }
    setUpdating(null);
  };

  const categoryItems = checklists.filter((c) => c.category === activeCategory);
  const groupedItems = categoryItems.reduce((acc, item) => {
    const key = item.sub_section || "General";
    if (!acc[key]) acc[key] = [];
    acc[key].push(item);
    return acc;
  }, {});

  const getCategoryProgress = (categoryId) => {
    const items = checklists.filter((c) => c.category === categoryId);
    if (items.length === 0) return 0;
    const done = items.filter((c) => c.status === "complete" || c.status === "na").length;
    return Math.round((done / items.length) * 100);
  };

  const totalItems = checklists.length;
  const completedItems = checklists.filter((c) => c.status === "complete").length;
  const naItems = checklists.filter((c) => c.status === "na").length;
  const pendingItems = checklists.filter((c) => c.status === "pending").length;
  const overallProgress = totalItems ? Math.round(((completedItems + naItems) / totalItems) * 100) : 0;

  const statusColors = {
    complete: { bg: "#052e16", border: "#22c55e", color: "#4ade80", label: "Complete" },
    na: { bg: "#1c1917", border: "#78716c", color: "#a8a29e", label: "N/A" },
    pending: { bg: "#0c1a2e", border: "#334155", color: "#94a3b8", label: "Pending" },
  };

  return (
    <div style={{ minHeight: "100vh", background: "#0f172a", fontFamily: "Inter, sans-serif", display: "flex", flexDirection: "column" }}>
      
      {/* Header */}
      <div style={{ background: "#1e293b", borderBottom: "1px solid #334155", padding: "16px 24px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <button onClick={onBack}
            style={{ background: "#334155", color: "#f1f5f9", border: "none", borderRadius: "6px", padding: "6px 12px", cursor: "pointer", fontSize: "14px" }}>
            ← Back
          </button>
          <div>
            <h1 style={{ margin: 0, fontSize: "18px", fontWeight: "700", color: "#f1f5f9" }}>{project.name}</h1>
            <p style={{ margin: 0, fontSize: "12px", color: "#94a3b8" }}>
              {completedItems} done · {naItems} N/A · {pendingItems} pending · {overallProgress}% complete
            </p>
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <span style={{ fontSize: "12px", color: "#94a3b8" }}>
            Role: <strong style={{ color: "#f1f5f9" }}>{userRole.replace("_", " ")}</strong>
          </span>
          <button onClick={onSignOut}
            style={{ padding: "8px 16px", background: "#ef4444", color: "white", border: "none", borderRadius: "6px", cursor: "pointer", fontSize: "14px" }}>
            Sign Out
          </button>
        </div>
      </div>

      <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>
        
        {/* Sidebar */}
        <div style={{ width: "220px", background: "#1e293b", borderRight: "1px solid #334155", overflowY: "auto", padding: "12px" }}>
          {CATEGORIES.map((cat) => {
            const progress = getCategoryProgress(cat.id);
            const isActive = activeCategory === cat.id;
            const editable = canEdit(cat.id);
            return (
              <button
                key={cat.id}
                onClick={() => setActiveCategory(cat.id)}
                style={{
                  width: "100%", display: "flex", justifyContent: "space-between", alignItems: "center",
                  padding: "8px 10px", marginBottom: "4px", border: "none", borderRadius: "8px",
                  background: isActive ? "#3b82f6" : "transparent",
                  color: isActive ? "white" : editable ? "#f1f5f9" : "#64748b",
                  cursor: "pointer", fontSize: "13px", textAlign: "left",
                }}>
                <span style={{ flex: 1 }}>{cat.label}</span>
                <span style={{ fontSize: "11px", fontWeight: "600", color: isActive ? "white" : progress === 100 ? "#4ade80" : "#94a3b8" }}>
                  {progress}%
                </span>
              </button>
            );
          })}
        </div>

        {/* Main content */}
        <div style={{ flex: 1, overflowY: "auto", padding: "24px" }}>
          {loading ? (
            <p style={{ color: "#94a3b8" }}>Loading checklist...</p>
          ) : categoryItems.length === 0 ? (
            <p style={{ color: "#94a3b8" }}>No items in this category.</p>
          ) : (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "20px" }}>
                <h2 style={{ color: "#f1f5f9", margin: 0, fontSize: "20px" }}>
                  {CATEGORIES.find((c) => c.id === activeCategory)?.label}
                </h2>
                {!canEdit(activeCategory) && (
                  <span style={{ fontSize: "12px", color: "#f59e0b", background: "#451a03", padding: "4px 10px", borderRadius: "20px", border: "1px solid #f59e0b" }}>
                    View only — your role cannot edit this section
                  </span>
                )}
              </div>

              {Object.entries(groupedItems).map(([subSection, items]) => (
                <div key={subSection} style={{ marginBottom: "24px" }}>
                  {subSection !== "General" && (
                    <div style={{ background: "#1e293b", borderLeft: "3px solid #3b82f6", padding: "8px 14px", marginBottom: "8px", borderRadius: "0 6px 6px 0" }}>
                      <span style={{ color: "#60a5fa", fontSize: "12px", fontWeight: "700", textTransform: "uppercase", letterSpacing: "0.05em" }}>
                        {subSection}
                      </span>
                    </div>
                  )}

                  <div style={{ background: "#1e293b", borderRadius: "12px", border: "1px solid #334155", overflow: "hidden" }}>
                    {items.map((item, idx) => {
                      const editable = canEdit(item.category);
                      const status = item.status || "pending";
                      const isUpdating = updating === item.id;

                      return (
                        <div key={item.id} style={{
                          padding: "16px", display: "flex", alignItems: "flex-start", gap: "16px",
                          borderBottom: idx < items.length - 1 ? "1px solid #1e293b" : "none",
                          background: idx % 2 === 0 ? "#1e293b" : "#172032",
                        }}>
                          {/* Status buttons */}
                          <div style={{ display: "flex", gap: "6px", flexShrink: 0 }}>
                            {["complete", "na", "pending"].map((s) => {
                              const sc = statusColors[s];
                              const isActive = status === s;
                              return (
                                <button
                                  key={s}
                                  onClick={() => editable && !isUpdating && handleStatusChange(item, s)}
                                  disabled={!editable || isUpdating}
                                  style={{
                                    padding: "4px 10px", border: `1px solid ${isActive ? sc.border : "#334155"}`,
                                    borderRadius: "6px", fontSize: "11px", fontWeight: "600",
                                    background: isActive ? sc.bg : "transparent",
                                    color: isActive ? sc.color : "#64748b",
                                    cursor: editable && !isUpdating ? "pointer" : "not-allowed",
                                  }}>
                                  {sc.label}
                                </button>
                              );
                            })}
                          </div>

                          {/* Item text and phase */}
                          <div style={{ flex: 1 }}>
                            <p style={{
                              margin: 0, fontSize: "14px", lineHeight: "1.5",
                              color: status === "na" ? "#64748b" : "#f1f5f9",
                              textDecoration: status === "na" ? "line-through" : "none",
                            }}>
                              {item.item_text}
                            </p>
                            {item.phase && (
                              <span style={{ fontSize: "11px", color: "#3b82f6", fontWeight: "600", marginTop: "4px", display: "inline-block" }}>
                                Phase: {item.phase}
                              </span>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  );
}