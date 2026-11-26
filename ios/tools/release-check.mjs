// 送審前檢查：把「上架前一定要改、忘了就會被退或出包」的東西一次列出來。
// 用法（repo 根目錄）：node ios/tools/release-check.mjs
// 全部過才回 0；有任何一項沒過回 1。只讀檔，不改任何東西。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const read = p => fs.readFileSync(path.join(root, p), "utf8");
const results = [];
const check = (ok, what, fix) => results.push({ ok, what, fix });

// 1. 開發工具
const yml = read("ios/project.yml");
check(!/SWIFT_ACTIVE_COMPILATION_CONDITIONS:.*\bDEVTOOLS\b/.test(yml),
  "正式版沒有開發工具", "拿掉 ios/project.yml 裡 SWIFT_ACTIVE_COMPILATION_CONDITIONS 那一行的 DEVTOOLS");
check(!/NSCameraUsageDescription:.*開發工具/.test(yml),
  "相機用途說明沒提到開發工具", "NSCameraUsageDescription 刪掉「開發工具裡連電腦的時候…」那一句");
check(!/NSLocalNetworkUsageDescription|NSAllowsLocalNetworking/.test(yml),
  "沒有要區域網路權限", "刪掉 NSLocalNetworkUsageDescription 和 NSAppTransportSecurity 那一段（只有連電腦的 Claude CLI 用）");

// 2. 問古書接得到中繼站
const ask = read("ios/Guaxiang/Ask/AskClient.swift");
const endpoint = ask.match(/static let endpoint = "([^"]*)"/)?.[1] ?? "";
check(/^https:\/\//.test(endpoint), "問古書有中繼站網址", "中繼站部署好後，把網址填進 AskClient.swift 的 AskConfig.endpoint");

// 3. 設定頁的回饋信箱、隱私權政策、App Store ID
const settings = read("ios/Guaxiang/Settings/SettingsView.swift");
for (const [key, label] of [["appStoreID", "App Store ID"], ["supportEmail", "回饋信箱"], ["privacyURL", "隱私權政策網址"]]) {
  check(!new RegExp(`${key}:\\s*nil`).test(settings), `設定頁有${label}`, `SettingsView.swift 的 ${key} 填上`);
}

// 4. App 圖示：1024×1024、沒有透明
const icon = fs.readFileSync(path.join(root, "ios/Guaxiang/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"));
const w = icon.readUInt32BE(16), h = icon.readUInt32BE(20), colorType = icon[25];
check(w === 1024 && h === 1024, "App 圖示是 1024×1024", `現在是 ${w}×${h}，跑 bash ios/tools/render-icon.sh 再跑 make-icons.py`);
check(colorType === 2 || colorType === 0, "App 圖示沒有透明", "圖示要存成不帶透明的 RGB");

// 5. 隱私清單
check(fs.existsSync(path.join(root, "ios/Guaxiang/Resources/PrivacyInfo.xcprivacy")), "有隱私清單 PrivacyInfo", "補回 PrivacyInfo.xcprivacy");

// 6. 版本號要手動對：上線版收過的號碼不能再用
const version = yml.match(/MARKETING_VERSION:\s*"([^"]+)"/)?.[1];

const bad = results.filter(r => !r.ok);
for (const r of results) console.log(`${r.ok ? "✅" : "❌"} ${r.what}${r.ok ? "" : `\n   → ${r.fix}`}`);
console.log(`\n版本 ${version}：送審前到 App Store Connect 確認這個版本號還沒上線過`);
console.log(bad.length ? `\n${bad.length} 項沒過，不能送審` : "\n全部過了");
process.exit(bad.length ? 1 : 0);
