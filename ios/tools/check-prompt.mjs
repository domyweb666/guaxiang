// 檢查 Swift 版的提示詞（Prompt.swift）跟 prompt.js 是不是一字不差。改提示詞後跑：
//   node ios/tools/check-prompt.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const swift = fs.readFileSync(path.join(root, "ios", "Guaxiang", "Engine", "Prompt.swift"), "utf8");
const m = swift.match(/static let system = """\n([\s\S]*?)\n\s*"""/);
if (!m) throw new Error("Prompt.swift 裡找不到 system");
const fromSwift = m[1].split("\n").map(l => l.replace(/^ {8}/, "")).join("\n").replaceAll("\\\\", "\\");
const prompt = await import(pathToFileURL(path.join(root, "prompt.js")).href);
const fromJS = prompt.buildRequest({ pack: [], profile: {}, question: "x" }).system;
if (fromSwift !== fromJS) {
  console.error("不一樣：Swift", fromSwift.length, "字，prompt.js", fromJS.length, "字");
  process.exit(1);
}
console.log("提示詞一字不差，共", fromJS.length, "字");

// 寫死的句子也要一樣
const reply = fs.readFileSync(path.join(root, "ios", "Guaxiang", "Engine", "AskReply.swift"), "utf8");
for (const [kind, text] of Object.entries({ ...prompt.FIXED, badFormat: prompt.BAD_FORMAT })) {
  if (!reply.includes(`"${text}"`)) {
    console.error("AskReply.swift 的", kind, "跟 prompt.js 不一樣");
    process.exit(1);
  }
}
console.log("寫死的句子一樣");
