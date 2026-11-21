// 瓜相「問古書」的中繼站（Cloudflare Worker）。
// 只收文字：依據清單、簡介、問題。不收照片、不收臉部座標。金鑰放在 Cloudflare 的環境變數，不在網頁裡。
import { buildRequest, LIMITS } from "../prompt.js";

const json = (obj, status, origin) => new Response(JSON.stringify(obj), {
  status, headers: { "content-type": "application/json; charset=utf-8", ...cors(origin) } });
const cors = origin => ({
  "access-control-allow-origin": origin || "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "vary": "origin" });

export default {
  async fetch(req, env) {
    const origin = req.headers.get("origin") || "";
    const allowed = (env.ALLOWED_ORIGINS || "https://domyweb666.github.io").split(",").map(s => s.trim());
    const ok = allowed.includes(origin) || (env.ALLOW_LOCALHOST === "1" && /^http:\/\/localhost(:\d+)?$/.test(origin));
    if (req.method === "OPTIONS") return new Response(null, { status: ok ? 204 : 403, headers: ok ? cors(origin) : {} });
    if (req.method !== "POST") return json({ error: "只接受 POST" }, 405, origin);
    if (!ok) return json({ error: "來源不允許" }, 403, "");

    const raw = await req.text();
    if (raw.length > LIMITS.packChars + 8000) return json({ error: "內容太長" }, 413, origin);
    let body; try { body = JSON.parse(raw); } catch { return json({ error: "格式錯誤" }, 400, origin); }
    const { pack, profile, question, history } = body || {};
    if (!Array.isArray(pack) || !pack.length || typeof question !== "string" || !question.trim())
      return json({ error: "缺少依據或問題" }, 400, origin);
    if (profile?.age && Number(profile.age) < 18) return json({ error: "未滿 18 歲不提供" }, 400, origin);

    const { system, messages } = buildRequest({ pack, profile, question, history: Array.isArray(history) ? history : [] });
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model: env.MODEL || "claude-sonnet-5-5", max_tokens: 900, system, messages })
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) return json({ error: "AI 服務暫時無法回答", detail: data?.error?.message || r.status }, 502, origin);
    const text = (data.content || []).filter(c => c.type === "text").map(c => c.text).join("\n").trim();
    return json({ text }, 200, origin);
  }
};
