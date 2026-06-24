import { useState } from "react";
import { supabase } from "../supabase";
import { CHECKLIST_TEMPLATE } from "../checklistTemplate";

const inputStyle = {
  width: "100%",
  padding: "10px 12px",
  background: "#0f172a",
  border: "1px solid #334155",
  borderRadius: "8px",
  color: "#f1f5f9",
  fontSize: "14px",
  boxSizing: "border-box",
};

export default function CreateProjectModal({ onClose, onCreated, userId }) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [progress, setProgress] = useState("");

  const handleCreate = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");

    // Step 1: Create project
    setProgress("Creating project...");
    const { data: project, error: projError } = await supabase
      .from("projects")
      .insert({ name, description, created_by: userId })
      .select()
      .single();

    if (projError) {
      setError(projError.message);
      setLoading(false);
      setProgress("");
      return;
    }

    // Step 2: Add creator as project_manager
    setProgress("Setting up team...");
    const { error: memberError } = await supabase
      .from("project_members")
      .insert({
        project_id: project.id,
        user_id: userId,
        role: "project_manager",
        invited_by: userId,
      });

    if (memberError) {
      setError(memberError.message);
      setLoading(false);
      setProgress("");
      return;
    }

    // Step 3: Auto-populate checklist items
    setProgress("Populating checklist items...");
    const checklistItems = CHECKLIST_TEMPLATE.map((item) => ({
      project_id: project.id,
      item_id: item.item_id,
      category: item.category,
      sub_section: item.sub_section || null,
      phase: item.phase || null,
      item_text: item.text,
      status: "pending",
    }));

    // Insert in batches of 50 to avoid limits
    const batchSize = 50;
    for (let i = 0; i < checklistItems.length; i += batchSize) {
      const batch = checklistItems.slice(i, i + batchSize);
      const { error: checklistError } = await supabase
        .from("checklists")
        .insert(batch);

      if (checklistError) {
        setError(checklistError.message);
        setLoading(false);
        setProgress("");
        return;
      }
      setProgress(`Populating checklist... ${Math.min(i + batchSize, checklistItems.length)}/${checklistItems.length} items`);
    }

    setLoading(false);
    setProgress("");
    onCreated();
  };

  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.7)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 50 }}>
      <div style={{ background: "#1e293b", borderRadius: "12px", padding: "32px", width: "100%", maxWidth: "480px", boxShadow: "0 4px 24px rgba(0,0,0,0.4)" }}>

        <h2 style={{ color: "#f1f5f9", margin: "0 0 24px", fontSize: "20px" }}>
          Create New Project
        </h2>

        {error && (
          <div style={{ background: "#450a0a", border: "1px solid #ef4444", borderRadius: "8px", padding: "12px", marginBottom: "16px", color: "#fca5a5", fontSize: "14px" }}>
            {error}
          </div>
        )}

        {progress && (
          <div style={{ background: "#0c1a2e", border: "1px solid #3b82f6", borderRadius: "8px", padding: "12px", marginBottom: "16px", color: "#93c5fd", fontSize: "14px" }}>
            ⏳ {progress}
          </div>
        )}

        <form onSubmit={handleCreate}>
          <div style={{ marginBottom: "16px" }}>
            <label style={{ display: "block", color: "#94a3b8", fontSize: "14px", marginBottom: "6px" }}>
              Project Name *
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              placeholder="e.g. Office Building QC"
              style={inputStyle}
              disabled={loading}
            />
          </div>

          <div style={{ marginBottom: "24px" }}>
            <label style={{ display: "block", color: "#94a3b8", fontSize: "14px", marginBottom: "6px" }}>
              Description
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Optional project description..."
              rows={3}
              style={{ ...inputStyle, resize: "vertical" }}
              disabled={loading}
            />
          </div>

          <div style={{ display: "flex", gap: "12px" }}>
            <button
              type="button"
              onClick={onClose}
              disabled={loading}
              style={{ flex: 1, padding: "12px", background: "#334155", color: "#f1f5f9", border: "none", borderRadius: "8px", fontSize: "14px", cursor: loading ? "not-allowed" : "pointer" }}>
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading}
              style={{ flex: 1, padding: "12px", background: "#3b82f6", color: "white", border: "none", borderRadius: "8px", fontSize: "14px", fontWeight: "600", cursor: loading ? "not-allowed" : "pointer" }}>
              {loading ? "Creating..." : "Create Project"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}