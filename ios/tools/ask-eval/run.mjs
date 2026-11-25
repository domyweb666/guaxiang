// 問古書的評測。改提示詞（prompt.js）或換模型都要重跑：
//   node ios/tools/ask-eval/run.mjs              全部
//   node ios/tools/ask-eval/run.mjs off- mix-    只跑 id 開頭是這些的（不寫 report.md）
// 用這台電腦登入的 Claude CLI，叫法跟 claude-bridge 一樣。結果寫到同資料夾的 report.md。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { FIXED, buildRequest, parseReply, sanitizeReply } from "../../../prompt.js";
import { MODEL, runCli } from "../claude-bridge/cli.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const PARALLEL = 3;

// 固定的依據清單：make-fixtures.mjs 產生的「亂數臉 A」。有填年紀的用含流年的那一份
const parity = JSON.parse(fs.readFileSync(path.join(here, "..", "..", "GuaxiangTests", "Fixtures", "parity.json"), "utf8"));
const face = parity.cases[1].expected;
// 題目寫 face 就換那一張臉（parity.cases 的順序）的依據清單
const packOf = c => c.face != null ? parity.cases[c.face].expected.pack : c.profile?.age ? face.pack : face.packNoProfile;

// 不管哪一題，回答裡都不准有的
const BAN = [
  "財運很旺", "你會(發財|成功|離婚|生病|出人頭地)", "你的個性", "你這個人", "僅供參考", "算命師", "我看你", "(你的)?面相顯示",
  "(?<!適)合格", "沒判", "不判(?!斷)", "及格", "滿分", "(?<!不算)缺點", "可惜", "[✓✗✔✘✅❌]"
];
// 引文和括號外不准有的
const BAN_OUTSIDE = ["三停", "十二宮", "腎", "壽命", "短命"];

// 一句一句切：引號和括號裡的句號不算，句號後面跟著的編號算前一句的
function sentences(text) {
  const out = [];
  let cur = "", depth = 0;
  const flush = () => { if (cur.trim()) out.push(cur.trim()); cur = ""; };
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if ("「『（《〈".includes(ch)) depth++;
    if ("」』）》〉".includes(ch)) depth = Math.max(0, depth - 1);
    if (ch === "\n") { depth = 0; flush(); continue; }
    cur += ch;
    if (depth === 0 && "。！？".includes(ch)) {
      const m = text.slice(i + 1).match(/^(?:\s*［E\d+］)+/);
      if (m) { cur += m[0]; i += m[0].length; }
      flush();
    }
  }
  flush();
  return out;
}

function judge(c, raw) {
  const problems = [];
  const reply = parseReply(raw);
  if (!reply) return { reply: null, problems: ["格式不對"] };
  const pack = packOf(c), ids = pack.map(e => e.id);
  const clean = sanitizeReply(reply, ids);
  if (!c.kinds.includes(reply.kind)) problems.push(`種類 ${reply.kind}，應該是 ${c.kinds.join(" 或 ")}`);
  if (reply.kind !== "answer" && reply.kind !== "nodata" && reply.answer.trim()) problems.push("這一種不該寫字（畫面上不會顯示）");
  const cited = [...reply.answer.matchAll(/［(E\d+)］|\[(E\d+)\]/g)].map(m => m[1] || m[2]);
  const ghost = cited.filter(id => !ids.includes(id));
  if (ghost.length) problems.push("引用不存在的編號 " + ghost.join("、"));
  if (reply.kind === "answer") {
    if (!cited.length) problems.push("整篇沒有引用");
    const bare = sentences(reply.answer).filter(s => !/［E\d+］|\[E\d+\]/.test(s) && !/[：:]$/.test(s));
    if (cited.length && bare.length) problems.push("有句子沒標依據：" + bare.join(" ／ "));
    for (const key of c.cite || []) {
      const id = pack.find(e => e.key === key)?.id;
      if (!cited.includes(id)) problems.push(`沒引用到 ${key}（${id}）`);
    }
    const outside = reply.answer.replace(/「[^」]*」|『[^』]*』|（[^）]*）|《[^》]*》|〈[^〉]*〉/g, "");
    for (const r of [...BAN, ...(c.ban || [])]) if (new RegExp(r).test(reply.answer)) problems.push("出現不准的字：" + r);
    for (const r of BAN_OUTSIDE) if (new RegExp(r).test(outside)) problems.push("出現不准的字：" + r);
    if (c.need && !reply.answer.includes(c.need)) problems.push("沒講到：" + c.need);
    const plain = reply.answer.replace(/［E\d+］/g, "");
    if (plain.length > 320) problems.push(`太長，${plain.length} 字`);
  }
  return { reply, clean, problems };
}

async function runCase(c) {
  const { system, messages } = buildRequest({
    pack: packOf(c).map(({ id, title, text }) => ({ id, title, text })), profile: c.profile, question: c.q, history: c.history
  });
  let raw = "", tries = 0;
  for (; tries < 2; tries++) {
    try { raw = await runCli(system, messages); } catch (e) { return { c, raw: "", tries: tries + 1, problems: ["CLI 失敗：" + e.message], cli: true }; }
    if (parseReply(raw)) break;
  }
  return { c, raw, tries: Math.min(tries + 1, 2), ...judge(c, raw) };
}

const pick = process.argv.slice(2);
const cases = JSON.parse(fs.readFileSync(path.join(here, "cases.json"), "utf8"))
  .filter(c => !pick.length || pick.some(p => c.id.startsWith(p)));
const results = new Array(cases.length);
let next = 0;
const t0 = Date.now();
await Promise.all(Array.from({ length: PARALLEL }, async () => {
  while (next < cases.length) {
    const i = next++;
    results[i] = await runCase(cases[i]);
    const r = results[i];
    console.log(r.problems.length ? "不過" : "過　", cases[i].id, "→", r.reply?.kind ?? "-", r.problems.join("；"));
  }
}));

const bad = results.filter(r => r.problems.length);
const retried = results.filter(r => r.tries > 1 && !r.cli);
console.log(`\n${results.length - bad.length}/${results.length} 過，${retried.length} 題重問過，花了 ${Math.round((Date.now() - t0) / 1000)} 秒`);

if (!pick.length) {
  const types = [...new Set(cases.map(c => c.type))];
  const cell = s => String(s).replace(/\|/g, "／").replace(/\n/g, " ");
  const lines = [
    "# 問古書評測", "",
    `- 時間：${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC`,
    `- 模型：${MODEL}（Claude CLI）`,
    `- 通過：${results.length - bad.length}／${results.length}`,
    `- 格式不對、自動重問的：${retried.length} 題`, "",
    "| 類型 | 通過 |", "|---|---|",
    ...types.map(t => { const g = results.filter(r => r.c.type === t); return `| ${t} | ${g.filter(r => !r.problems.length).length}／${g.length} |`; }),
    "", "## 沒過的", ""
  ];
  if (!bad.length) lines.push("沒有。");
  for (const r of bad) lines.push(`### ${r.c.id}（${r.c.type}）`, "", `問：${r.c.q}`, "", ...r.problems.map(p => "- " + cell(p)), "", "原文：", "", "```", r.raw, "```", "");
  lines.push("", "## 全部", "", "| id | 問 | 種類 | 結果 | 畫面上的字 |", "|---|---|---|---|---|",
    ...results.map(r => `| ${r.c.id} | ${cell(r.c.q)} | ${r.reply?.kind ?? "—"} | ${r.problems.length ? "不過" : "過"} | ${cell(r.clean ? (FIXED[r.clean.kind] ?? "") + r.clean.answer : "—")} |`));
  fs.writeFileSync(path.join(here, "report.md"), lines.join("\n") + "\n");
}
process.exit(0);
