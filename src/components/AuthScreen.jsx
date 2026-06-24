import { useState } from "react";
import { supabase } from "../supabase";

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

export default function AuthScreen() {
  const [mode, setMode] = useState("login");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setError(error.message);
    setLoading(false);
  };

  const handleRegister = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    const { data, error } = await supabase.auth.signUp({ email, password });
    if (error) {
      setError(error.message);
    } else {
      await supabase.from("profiles").insert({
        id: data.user.id,
        full_name: fullName,
        email: email,
      });
      setMessage("✅ Account created! Please check your email and confirm your account before signing in.");
    }
    setLoading(false);
  };

  return (
    <div style={{ minHeight: "100vh", background: "#0f172a", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "Inter, sans-serif" }}>
      <div style={{ background: "#1e293b", borderRadius: "12px", padding: "40px", width: "100%", maxWidth: "400px", boxShadow: "0 4px 24px rgba(0,0,0,0.4)" }}>
        
        {/* Logo */}
        <div style={{ textAlign: "center", marginBottom: "32px" }}>
          <h1 style={{ color: "#f1f5f9", fontSize: "24px", fontWeight: "700", margin: 0 }}>AGE-QC-Checklist</h1>
          <p style={{ color: "#94a3b8", fontSize: "14px", marginTop: "8px" }}>Structural QA Management</p>
        </div>

        {/* Tabs */}
        <div style={{ display: "flex", marginBottom: "24px", background: "#0f172a", borderRadius: "8px", padding: "4px" }}>
          {["login", "register"].map((m) => (
            <button key={m}
              onClick={() => { setMode(m); setError(""); setMessage(""); }}
              style={{ flex: 1, padding: "8px", border: "none", borderRadius: "6px", cursor: "pointer", fontWeight: "600", fontSize: "14px", background: mode === m ? "#3b82f6" : "transparent", color: mode === m ? "white" : "#94a3b8" }}>
              {m === "login" ? "Sign In" : "Register"}
            </button>
          ))}
        </div>

        {/* Error / Message */}
        {error && (
          <div style={{ background: "#450a0a", border: "1px solid #ef4444", borderRadius: "8px", padding: "12px", marginBottom: "16px", color: "#fca5a5", fontSize: "14px" }}>
            {error}
          </div>
        )}
        {message && (
          <div style={{ background: "#052e16", border: "1px solid #22c55e", borderRadius: "8px", padding: "12px", marginBottom: "16px", color: "#86efac", fontSize: "14px" }}>
            {message}
          </div>
        )}

        {/* Form */}
        <form onSubmit={mode === "login" ? handleLogin : handleRegister}>
          {mode === "register" && (
            <div style={{ marginBottom: "16px" }}>
              <label style={{ display: "block", color: "#94a3b8", fontSize: "14px", marginBottom: "6px" }}>Full Name</label>
              <input type="text" value={fullName} onChange={(e) => setFullName(e.target.value)} required placeholder="John Smith" style={inputStyle} />
            </div>
          )}
          <div style={{ marginBottom: "16px" }}>
            <label style={{ display: "block", color: "#94a3b8", fontSize: "14px", marginBottom: "6px" }}>Email</label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required placeholder="you@example.com" style={inputStyle} />
          </div>
          <div style={{ marginBottom: "24px" }}>
            <label style={{ display: "block", color: "#94a3b8", fontSize: "14px", marginBottom: "6px" }}>Password</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required placeholder="••••••••" style={inputStyle} />
          </div>
          <button type="submit" disabled={loading}
            style={{ width: "100%", padding: "12px", background: loading ? "#1d4ed8" : "#3b82f6", color: "white", border: "none", borderRadius: "8px", fontSize: "16px", fontWeight: "600", cursor: loading ? "not-allowed" : "pointer" }}>
            {loading ? "Please wait..." : mode === "login" ? "Sign In" : "Create Account"}
          </button>
        </form>
      </div>
    </div>
  );
}