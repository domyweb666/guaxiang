// 開發測試用：讓 iPhone 上的瓜相，透過這台電腦登入的 Claude CLI 回答「問古書」。
// 協定跟 worker 一樣：POST /ask?t=密碼，body {pack, profile, question, history}，回 {kind, answer}。
// 提示詞和回答檢查用 repo 根目錄的 prompt.js。做法改寫自蘿蔔旅行的 claude-bridge。正式版不走這條。
import crypto from "node:crypto";
import http from "node:http";
import os from "node:os";
import qrcode from "qrcode-terminal";
import { askOnce, checkBody } from "../../../prompt.js";
import { CliError, HOW, MODEL, cliVersion, killTree, runCli } from "./cli.mjs";

const PORT = Number(process.env.PORT) || 8790;
const BODY_MAX = 1024 * 1024;
const TOKEN = crypto.randomBytes(16).toString("hex");

// ---------- 排隊：同一時間只跑一題 ----------
let running = null;
let queue = Promise.resolve();
let waiting = 0;

function enqueue(task) {
  waiting += 1;
  const run = () => { waiting -= 1; return task(); };
  const p = queue.then(run, run);
  queue = p.catch(() => {});
  return p;
}

// ---------- HTTP ----------
const stamp = () => new Date().toLocaleTimeString("zh-TW", { hour12: false });

function send(res, code, obj) {
  if (res.writableEnded || res.destroyed) return;
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store"
  });
  res.end(body);
}

function tokenOk(t) {
  if (typeof t !== "string" || t.length !== TOKEN.length) return false;
  return crypto.timingSafeEqual(Buffer.from(t), Buffer.from(TOKEN));
}

let CLI_VERSION = "";

function handleAsk(req, res) {
  const chunks = [];
  let size = 0, tooBig = false;
  req.on("data", d => {
    if (tooBig) return;
    size += d.length;
    if (size > BODY_MAX) {
      tooBig = true;
      send(res, 413, { error: "內容超過 1MB" });
      req.resume();
      return;
    }
    chunks.push(d);
  });
  req.on("error", () => { /* 連線斷掉就算了 */ });
  req.on("end", async () => {
    if (tooBig) return;
    let body;
    try { body = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { return send(res, 400, { error: "格式錯誤" }); }
    const wrong = checkBody(body);
    if (wrong) return send(res, 400, { error: wrong });

    const ahead = waiting + (running ? 1 : 0);
    console.log(`[${stamp()}] 收到一題${ahead ? `，前面還有 ${ahead} 題在排` : ""}`);
    const t0 = Date.now();
    const gone = () => res.destroyed && !res.writableEnded;
    // app 那頭按了停止，正在跑的這一題就不用跑完
    let mine = null;
    res.on("close", () => { if (gone()) killTree(mine); });
    try {
      const reply = await enqueue(() => askOnce(body, async (system, messages) => {
        if (gone()) throw new CliError(499, "app 已經斷線");
        try {
          return await runCli(system, messages, { onStart: child => { mine = running = child; } });
        } finally {
          mine = running = null;
        }
      }));
      console.log(`[${stamp()}] 回了，花了 ${((Date.now() - t0) / 1000).toFixed(1)} 秒，種類 ${reply.kind}`);
      send(res, 200, reply);
    } catch (e) {
      const status = gone() ? 499 : e instanceof CliError ? e.status : 502;
      const why = status === 504 ? "超過 170 秒" : status === 499 ? "app 按了停止或斷線" : `失敗（${status}）`;
      console.log(`[${stamp()}] 花了 ${((Date.now() - t0) / 1000).toFixed(1)} 秒，${why}`);
      const message = status === 504 ? "等太久了，電腦上的 Claude 沒有在 170 秒內回答。" : String(e.message || e).slice(0, 200);
      send(res, status === 499 ? 502 : status, { error: message });
    }
  });
}

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url || "/", "http://localhost");
  } catch {
    return send(res, 400, { error: "網址看不懂" });
  }
  if (!tokenOk(url.searchParams.get("t"))) {
    req.resume();
    return send(res, 401, { error: "密碼不對" });
  }
  if (url.pathname === "/ping") {
    if (req.method !== "GET") return send(res, 405, { error: "只收 GET" });
    return send(res, 200, { ok: true, name: os.hostname(), cli: CLI_VERSION });
  }
  if (url.pathname === "/ask") {
    if (req.method !== "POST") {
      req.resume();
      return send(res, 405, { error: "只收 POST" });
    }
    return handleAsk(req, res);
  }
  req.resume();
  send(res, 404, { error: "只有 /ping 和 /ask" });
});
// CLI 最多跑 170 秒，排隊還要再等，別讓 Node 自己先把連線斷掉
server.requestTimeout = 0;
server.headersTimeout = 30 * 1000;

// ---------- 找區網 IP ----------
const VIRTUAL = /vethernet|virtualbox|vmware|vbox|hyper-v|wsl|docker|loopback|tailscale|zerotier|hamachi|vpn|tap|tun|utun|veth|br-|bridge|npcap/i;

function privateRank(ip) {
  if (ip.startsWith("192.168.")) return 0;
  if (ip.startsWith("10.")) return 1;
  const m = ip.match(/^172\.(\d+)\./);
  if (m && Number(m[1]) >= 16 && Number(m[1]) <= 31) return 2;
  return 9;
}

function lanIps() {
  const all = [];
  for (const [name, list] of Object.entries(os.networkInterfaces())) {
    for (const a of list || []) {
      const v4 = a.family === "IPv4" || a.family === 4;
      if (!v4 || a.internal || a.address.startsWith("169.254.")) continue;
      all.push({ name, ip: a.address, rank: privateRank(a.address), virtual: VIRTUAL.test(name) });
    }
  }
  // app 只收私人網段的網址，其他的印了也連不上
  const lan = all.filter(x => x.rank < 9);
  const real = lan.filter(x => !x.virtual);
  return (real.length ? real : lan).sort((a, b) => a.rank - b.rank);
}

// ---------- 開機與關機 ----------
function printBanner() {
  const ips = lanIps();
  console.log("");
  console.log("瓜相 × Claude CLI 轉接（開發測試用）");
  console.log(`叫 CLI 的方式：${HOW}`);
  console.log(`Claude CLI：${CLI_VERSION || "（取不到版本，確認 claude 有裝好、有登入）"}`);
  console.log(`模型：${MODEL}`);
  console.log("");
  if (!ips.length) {
    console.log(`找不到區網 IP。這台電腦有連上 Wi-Fi 嗎？這台電腦自己連：http://127.0.0.1:${PORT}/ask?t=${TOKEN}`);
    return;
  }
  const urls = ips.map(x => `http://${x.ip}:${PORT}/ask?t=${TOKEN}`);
  console.log("在 app 的「設定 → 開發工具 → 連電腦的 Claude CLI」掃這個：");
  qrcode.generate(urls[0], { small: true }, q => console.log(q));
  ips.forEach((x, i) => console.log(`${urls[i]}   （${x.name}）`));
  console.log("");
  console.log("iPhone 跟這台電腦要連同一個 Wi-Fi；第一次會問要不要讓瓜相找區網裝置，要按允許");
  console.log("按 Ctrl+C 結束");
  console.log("");
}

let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  console.log(`\n[${stamp()}] 收到結束，關掉中…`);
  if (running) killTree(running);
  server.close(() => process.exit(0));
  if (server.closeAllConnections) server.closeAllConnections();
  setTimeout(() => process.exit(0), 3000).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.on("SIGHUP", shutdown);

server.on("error", e => {
  if (e.code === "EADDRINUSE") console.error(`埠號 ${PORT} 已經有人在用。關掉另一個，或用 PORT=8791 npm start 換一個`);
  else console.error(`伺服器開不起來：${e.message}`);
  process.exit(1);
});

CLI_VERSION = await cliVersion();
server.listen(PORT, "0.0.0.0", printBanner);
