# 瓜相 iOS 版

SwiftUI 原生。這台 Windows 不能編 Swift，推上 GitHub 後由 Actions 的 macOS 機器編譯和跑測試（`.github/workflows/ios-ci.yml`）。

規矩在 `.vibe/規矩檔.md`，Claude 代為決定的事在 `.vibe/代決清單.md`。

## 資料夾

| 位置 | 內容 |
|---|---|
| `project.yml` | 專案描述檔，CI 用 XcodeGen 照它產生 Xcode 專案 |
| `Guaxiang/Engine/` | 判讀引擎：特徵公式、中位數、規則比對、依據清單、提示詞。只用 Foundation，逐行照網頁版 |
| `Guaxiang/Scan/` | ARKit 掃描、把關、Vision 找眉毛嘴唇、頂點對照表、髮際線 |
| `Guaxiang/Report/` | 報告畫面 |
| `Guaxiang/Ask/` | 問古書 |
| `Guaxiang/Settings/` | 設定頁（VeggieKit）和開發工具 |
| `Guaxiang/Resources/arkit-vertex-map.json` | ARKit 頂點對照表，現在是空的 |
| `GuaxiangTests/` | 單元測試；`Fixtures/parity.json` 是網頁版 JS 算出來的標準答案 |
| `tools/` | 產生標準答案、檢查提示詞、產生圖示的小程式 |

規則庫用 repo 根目錄的 `rules.json`，打包時直接帶進 app，這裡沒有另外一份。

## 改了東西之後

| 改了什麼 | 要做什麼 |
|---|---|
| `rules.json`、`index.html` 的算法 | `node ios/tools/make-fixtures.mjs`，重產標準答案 |
| `prompt.js` | 把 `Guaxiang/Engine/Prompt.swift` 改成一樣，跑 `node ios/tools/check-prompt.mjs` 和上面那一行 |
| 圖示 | `python ios/tools/make-icons.py` |
| 任何 Swift | commit、推功能分支，看 Actions 的 iOS CI |

## 現在做到哪

照 HANDOFF 第五節的路線圖：

| # | 項目 | 狀態 |
|---|---|---|
| 1 | 專案骨架、CI 編譯 | 模擬器版編得過、測試會過。TestFlight 打包流程跑通了（`.github/workflows/testflight.yml`，推 `tf-*` tag 觸發）：2026-11-22 `tf-1` 全綠，0.1.0 (1) 上傳成功。下一個 tag 是 `tf-2`，多米開口才打 |
| 2 | 頂點編號除錯畫面、對照表 | 工具寫好了（設定 → 開發工具 → 頂點對照）。**對照表是空的，要在真機上對** |
| 3 | 掃描流程 | 寫好了，沒在真機跑過 |
| 4 | 量測＋規則判讀 | 判讀引擎跟網頁版逐項一致（有測試）。量測要等對照表 |
| 5 | 報告畫面 | 2026-11-22 照準則改版：總覽＋一區一頁、朱印古書配色（畫板 https://claude.ai/artifact/9vk3MZVLe7Bdo2kbpuftfU）。首頁就能開範例報告。沒在真機看過 |
| 6 | 深度特徵 | 公式照搬、標實驗，還沒校準 |
| 7 | 問古書 | 畫面和檢查都寫好了。中繼站還沒部署；評測題還沒建 |
| 8 | 付費 | 只有骨架（`Store/Storage.swift` 的 `Paywall`） |
| 9 | 上架準備 | 還沒開始 |

## 第一次裝到手機後要做的事

1. **看範例報告**：首頁「先看一份範例報告」（開發工具裡也有）。看報告每一區的樣子，深色模式也切一次。
2. **對頂點**：設定 → 開發工具 → 頂點對照。
   - 按定格。照片上會蓋一層白點，每一點是一個網格頂點。**先看白點有沒有貼在臉上**；整片歪掉或左右相反的話，截圖給 Claude，那是畫面方向沒對上。
   - 下面選「要對的點」，兩指放大，點最接近那個位置的白點，按「指定」。一共 26 個點。
   - 對照網頁版的標註圖比較好找位置。
   - 對完按「分享 JSON」，把內容貼給 Claude 或直接存成 `ios/Guaxiang/Resources/arkit-vertex-map.json`。對到一半的會留在手機上，可以分次做。
3. **掃一次**：對完之後不用等新版，直接回主畫面掃。報告最上面如果出現「這一版還量不到的」，把那幾行字告訴 Claude。
4. **連掃三次**：同一個地點，看每一項的數字差多少（數字明細裡有）。路線圖第 3 步的驗收是每項差距小於 3%。
