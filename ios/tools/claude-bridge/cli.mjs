// 叫電腦上的 Claude CLI 回一段文字。bridge.mjs 和 ../ask-eval/run.mjs 共用這一份。
// 使用者的內容一律走 stdin；system 走 --system-prompt，直接 spawn，不經 shell。
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const IS_WIN = process.platform === "win32";

export const MODEL = (process.env.CLAUDE_MODEL || "sonnet").trim();
export const TIMEOUT_MS = 170 * 1000;

// 在空資料夾裡跑，不給任何工具、不載 MCP、不存對話：它只能回文字，碰不到這台電腦的檔案
const CWD = path.join(os.tmpdir(), "guaxiang-claude-bridge");

export class CliError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ---------- 找 claude ----------
// Windows 上 npm 裝的 claude 是 claude.cmd，Node 不准不開 shell 直接跑 .cmd。
// 有 .exe 就直接跑；沒有就從 claude.cmd 找到它背後的 cli.js，用 node 跑。
// 兩個都找不到就不跑：系統提示詞有引號和換行，經過 cmd.exe 會壞掉。
function whereAll(name) {
  try {
    const out = execFileSync(IS_WIN ? "where" : "which", IS_WIN ? [name] : ["-a", name], {
      encoding: "utf8", windowsHide: true, stdio: ["ignore", "pipe", "ignore"]
    });
    return out.split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  } catch {
    return [];
  }
}

function resolveClaude() {
  if (!IS_WIN) return { file: "claude", pre: [], how: "claude" };
  const found = whereAll("claude");
  const exe = found.find(p => p.toLowerCase().endsWith(".exe"));
  if (exe) return { file: exe, pre: [], how: exe };
  const cmd = found.find(p => p.toLowerCase().endsWith(".cmd"));
  if (cmd) {
    const dir = path.dirname(cmd);
    const text = (() => { try { return fs.readFileSync(cmd, "utf8"); } catch { return ""; } })();
    // 新版的 claude.cmd 指到 .exe，舊版指到 .js
    const m = text.match(/%dp0%\\([^"]+?\.(?:exe|js))"/i);
    const fallback = path.join(dir, "node_modules", "@anthropic-ai", "claude-code", "cli.js");
    const target = m && fs.existsSync(path.join(dir, m[1])) ? path.join(dir, m[1]) : fallback;
    if (fs.existsSync(target)) {
      if (target.toLowerCase().endsWith(".exe")) return { file: target, pre: [], how: target };
      const localNode = path.join(dir, "node.exe");
      return { file: fs.existsSync(localNode) ? localNode : process.execPath, pre: [target], how: `node ${target}` };
    }
  }
  return null;
}

const CLAUDE = resolveClaude();
export const HOW = CLAUDE ? CLAUDE.how : "找不到 claude";

function childEnv() {
  const env = { ...process.env };
  // 從 Claude Code 裡面開這支時，別讓子程序以為自己是巢狀的 session
  delete env.CLAUDECODE;
  delete env.CLAUDE_CODE_ENTRYPOINT;
  return env;
}

function startCli(args) {
  if (!CLAUDE) throw new CliError(502, "這台電腦找不到 claude，先裝 Claude Code 並登入");
  fs.mkdirSync(CWD, { recursive: true });
  return spawn(CLAUDE.file, [...CLAUDE.pre, ...args], { cwd: CWD, env: childEnv(), windowsHide: true });
}

// 砍整棵程序樹
export function killTree(child) {
  if (!child || child.exitCode !== null || child.killed) return;
  if (IS_WIN && child.pid) {
    try {
      execFileSync("taskkill", ["/pid", String(child.pid), "/T", "/F"], { stdio: "ignore", windowsHide: true });
      return;
    } catch { /* 退回下面 */ }
  }
  child.kill("SIGKILL");
}

export function cliVersion() {
  return new Promise(resolve => {
    let out = "", child;
    try { child = startCli(["--version"]); } catch { return resolve(""); }
    const timer = setTimeout(() => { killTree(child); resolve(""); }, 20 * 1000);
    child.stdout.on("data", d => (out += d));
    child.on("error", () => { clearTimeout(timer); resolve(""); });
    child.on("close", code => { clearTimeout(timer); resolve(code === 0 ? out.trim() : ""); });
    child.stdin.end();
  });
}

// CLI 一次只吃一段文字。把多輪對話攤平，每一段標清楚是誰的
export function flatten(messages) {
  if (messages.length === 1) return messages[0].content;
  const parts = [];
  const last = messages.length - 1;
  messages.forEach((m, i) => {
    if (i === last) parts.push(`〔這一題，請回答〕\n${m.content}`);
    else if (m.role === "user") parts.push(`〔先前的對話：使用者〕\n${m.content}`);
    else parts.push(`〔先前的對話：你的回答〕\n${m.content}`);
  });
  return parts.join("\n\n");
}

// 跑一次。onStart 會拿到子程序（要中斷時用 killTree 砍）
export function runCli(system, messages, { model = MODEL, timeout = TIMEOUT_MS, onStart } = {}) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = startCli(["-p", "--output-format", "text", "--no-session-persistence", "--strict-mcp-config",
        "--model", model, "--system-prompt", system, "--tools", ""]);
    } catch (e) {
      return reject(e instanceof CliError ? e : new CliError(502, String(e.message || e).slice(0, 200)));
    }
    onStart?.(child);
    let out = "", err = "", timedOut = false;
    const timer = setTimeout(() => { timedOut = true; killTree(child); }, timeout);
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", d => (out += d));
    child.stderr.on("data", d => (err += d));
    child.stdin.on("error", () => { /* CLI 先結束時 stdin 會斷，交給 close 處理 */ });
    child.on("error", e => { clearTimeout(timer); reject(new CliError(502, String(e.message || e).slice(0, 200))); });
    child.on("close", code => {
      clearTimeout(timer);
      if (timedOut) return reject(new CliError(504, "timeout"));
      const text = out.trim();
      if (code !== 0) return reject(new CliError(502, (err.trim() || text || `claude 結束碼 ${code}`).slice(0, 200)));
      if (!text) return reject(new CliError(502, (err.trim() || "claude 沒有回任何文字").slice(0, 200)));
      resolve(text);
    });
    child.stdin.end(flatten(messages), "utf8");
  });
}
