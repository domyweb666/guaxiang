// 瓜相「問古書」的中繼站（Cloudflare Worker）。
// 只收文字：依據清單、簡介、問題。不收照片、不收臉部座標。金鑰放在 Cloudflare 的環境變數，不在網頁裡。
import { askOnce, checkBody, LIMITS } from "../prompt.js";

const json = (obj, status, origin) => new Response(JSON.stringify(obj), {
  status, headers: { "content-type": "application/json; charset=utf-8", ...cors(origin) } });
const cors = origin => ({
  "access-control-allow-origin": origin || "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "vary": "origin" });

async function callClaude(env, system, messages) {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model: env.MODEL || "claude-sonnet-5-5", max_tokens: 900, system, messages })
  }).catch(() => null);
  if (!r || !r.ok) throw new Error("AI 服務暫時無法回答");
  const data = await r.json().catch(() => ({}));
  return (data.content || []).filter(c => c.type === "text").map(c => c.text).join("\n");
}

export default {
  async fetch(req, env) {
    const origin = req.headers.get("origin") || "";
    const allowed = (env.ALLOWED_ORIGINS || "https://domyweb666.github.io").split(",").map(s => s.trim());
    // iOS app 不是瀏覽器，不會帶 origin；改認 app 自己帶的標頭。
    // 這個標頭誰都能假造，擋不了有心人，所以上架前一定要加每人每天的次數限制（HANDOFF 第八節）。
    const fromApp = !origin && env.ALLOW_APP === "1" && /^ios\/[\d.]+$/.test(req.headers.get("x-guaxiang-client") || "");
    const ok = fromApp || allowed.includes(origin) || (env.ALLOW_LOCALHOST === "1" && /^http:\/\/localhost(:\d+)?$/.test(origin));
    if (req.method === "OPTIONS") return new Response(null, { status: ok ? 204 : 403, headers: ok ? cors(origin) : {} });
    if (req.method !== "POST") return json({ error: "只接受 POST" }, 405, origin);
    if (!ok) return json({ error: "來源不允許" }, 403, "");

    const raw = await req.text();
    if (raw.length > LIMITS.packChars + 8000) return json({ error: "內容太長" }, 413, origin);
    let body; try { body = JSON.parse(raw); } catch { return json({ error: "格式錯誤" }, 400, origin); }
    const wrong = checkBody(body);
    if (wrong) return json({ error: wrong }, 400, origin);

    // 回 {kind, answer}：已經檢查過的結構，跑題和健康那幾種不帶模型寫的字（prompt.js 的 askOnce）
    try {
      return json(await askOnce(body, (system, messages) => callClaude(env, system, messages)), 200, origin);
    } catch (e) {
      return json({ error: e.message }, 502, origin);
    }
  }
};
