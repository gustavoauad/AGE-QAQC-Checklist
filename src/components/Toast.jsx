import { useRef, useState } from "react";

// Shared toast so failed Supabase writes (RLS denial, network blip) surface to the
// user instead of silently leaving the UI out of sync with the DB until reload.
export function useToast() {
  const [toast, setToast] = useState(null);
  const timerRef = useRef(null);

  const showToast = (type, message) => {
    if (timerRef.current) clearTimeout(timerRef.current);
    setToast({ type, message });
    timerRef.current = setTimeout(() => setToast(null), 4000);
  };

  return [toast, showToast];
}

export default function Toast({ toast }) {
  if (!toast) return null;
  const colors = {
    success: { bg: "var(--c-ok-bg)", border: "var(--c-ok)", color: "var(--c-ok-text)" },
    error:   { bg: "var(--c-err-bg)", border: "var(--c-err)", color: "var(--c-err-text)" },
    info:    { bg: "var(--c-accent-dk)", border: "var(--c-accent)", color: "var(--c-accent-lt)" },
  };
  const c = colors[toast.type] || colors.info;
  return (
    <div style={{
      position: "fixed", top: "16px", left: "50%", transform: "translateX(-50%)",
      zIndex: 2000, padding: "12px 20px", borderRadius: "10px",
      background: c.bg, border: `1px solid ${c.border}`, color: c.color,
      fontSize: "14px", fontWeight: "600", fontFamily: "Manrope, sans-serif",
      boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
      maxWidth: "calc(100vw - 32px)", textAlign: "center",
    }}>
      {toast.message}
    </div>
  );
}
