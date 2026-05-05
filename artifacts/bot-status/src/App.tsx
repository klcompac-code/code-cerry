import { useEffect, useState } from "react";

const COMMANDS = [
  { cmd: ".help", desc: "Show all commands", cost: "free" },
  { cmd: ".l <code>", desc: "Convert Luau → Lua 5.3", cost: "1 token" },
  { cmd: ".detect <code>", desc: "Detect obfuscator used", cost: "1 token" },
  { cmd: ".obf <code>", desc: "Obfuscate Lua code", cost: "1 token" },
  { cmd: ".info [@user]", desc: "View role, tokens & blacklist status", cost: "free" },
  { cmd: ".gift @user <amount>", desc: "Gift tokens to a user", cost: "1 token" },
  { cmd: ".bl <id> <dur> <reason>", desc: "Blacklist a user (owner only)", cost: "owner" },
  { cmd: ".setrole @user <role>", desc: "Set user role (owner only)", cost: "owner" },
  { cmd: ".settoken @user <amt>", desc: "Set user tokens (owner only)", cost: "owner" },
  { cmd: ".config", desc: "View bot configuration (owner only)", cost: "owner" },
];

const ROLES = [
  { name: "Owner", icon: "👑", color: "#f1c40f", tokens: "Unlimited ♾️", max: "—" },
  { name: "Premium", icon: "💎", color: "#9b59b6", tokens: "500", max: "1000" },
  { name: "Free", icon: "🆓", color: "#3498db", tokens: "50", max: "100" },
];

function usePulse() {
  const [on, setOn] = useState(true);
  useEffect(() => {
    const t = setInterval(() => setOn((v) => !v), 1200);
    return () => clearInterval(t);
  }, []);
  return on;
}

export default function App() {
  const pulse = usePulse();
  const [uptime] = useState(() => new Date());
  const [now, setNow] = useState(new Date());

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(t);
  }, []);

  const elapsed = Math.floor((now.getTime() - uptime.getTime()) / 1000);
  const h = Math.floor(elapsed / 3600);
  const m = Math.floor((elapsed % 3600) / 60);
  const s = elapsed % 60;
  const uptimeStr = `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;

  return (
    <div style={{ minHeight: "100vh", background: "#1a1a2e", color: "#e0e0e0", fontFamily: "'Segoe UI', sans-serif", padding: "2rem 1rem" }}>
      <div style={{ maxWidth: 860, margin: "0 auto" }}>

        {/* Header */}
        <div style={{ textAlign: "center", marginBottom: "2.5rem" }}>
          <div style={{ fontSize: 64, marginBottom: 8 }}>🤖</div>
          <h1 style={{ fontSize: "2rem", fontWeight: 700, color: "#fff", margin: 0 }}>Lua Dumper Bot</h1>
          <p style={{ color: "#8888aa", marginTop: 6 }}>Discord bot • Lua tools & token system</p>

          <div style={{ display: "inline-flex", alignItems: "center", gap: 8, background: "#16213e", border: "1px solid #0f3460", borderRadius: 24, padding: "6px 18px", marginTop: 16 }}>
            <span style={{
              width: 10, height: 10, borderRadius: "50%",
              background: pulse ? "#2ecc71" : "#27ae60",
              boxShadow: pulse ? "0 0 8px #2ecc71" : "none",
              display: "inline-block", transition: "all 0.4s"
            }} />
            <span style={{ color: "#2ecc71", fontWeight: 600, fontSize: 14 }}>ONLINE</span>
            <span style={{ color: "#555", fontSize: 12, marginLeft: 4 }}>uptime {uptimeStr}</span>
          </div>
        </div>

        {/* Roles */}
        <h2 style={{ color: "#aaa", fontSize: 13, letterSpacing: 2, textTransform: "uppercase", marginBottom: 12 }}>User Roles</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12, marginBottom: 32 }}>
          {ROLES.map((r) => (
            <div key={r.name} style={{ background: "#16213e", border: `1px solid ${r.color}33`, borderRadius: 12, padding: "16px 20px" }}>
              <div style={{ fontSize: 28, marginBottom: 6 }}>{r.icon}</div>
              <div style={{ color: r.color, fontWeight: 700, fontSize: 16, marginBottom: 8 }}>{r.name}</div>
              <div style={{ fontSize: 13, color: "#8888aa" }}>Default tokens: <span style={{ color: "#ddd" }}>{r.tokens}</span></div>
              <div style={{ fontSize: 13, color: "#8888aa" }}>Max tokens: <span style={{ color: "#ddd" }}>{r.max}</span></div>
              <div style={{ fontSize: 13, color: "#8888aa" }}>Restore: <span style={{ color: "#ddd" }}>+1 / hour</span></div>
            </div>
          ))}
        </div>

        {/* Commands */}
        <h2 style={{ color: "#aaa", fontSize: 13, letterSpacing: 2, textTransform: "uppercase", marginBottom: 12 }}>Commands</h2>
        <div style={{ background: "#16213e", border: "1px solid #0f3460", borderRadius: 12, overflow: "hidden", marginBottom: 32 }}>
          {COMMANDS.map((c, i) => (
            <div key={c.cmd} style={{
              display: "flex", alignItems: "center", justifyContent: "space-between",
              padding: "12px 20px",
              borderBottom: i < COMMANDS.length - 1 ? "1px solid #0f346033" : "none",
              gap: 12
            }}>
              <div>
                <code style={{ color: "#5865f2", fontWeight: 700, fontSize: 14 }}>{c.cmd}</code>
                <div style={{ color: "#8888aa", fontSize: 13, marginTop: 2 }}>{c.desc}</div>
              </div>
              <span style={{
                fontSize: 11, fontWeight: 600, borderRadius: 12, padding: "3px 10px", whiteSpace: "nowrap",
                background: c.cost === "free" ? "#1a4a2e" : c.cost === "owner" ? "#3a2a10" : "#1a2a4a",
                color: c.cost === "free" ? "#2ecc71" : c.cost === "owner" ? "#f1c40f" : "#3498db",
              }}>
                {c.cost}
              </span>
            </div>
          ))}
        </div>

        {/* Footer */}
        <div style={{ textAlign: "center", color: "#555", fontSize: 13 }}>
          Tokens restore <strong style={{ color: "#888" }}>+1 per hour</strong> automatically • Running 24/7
        </div>
      </div>
    </div>
  );
}
