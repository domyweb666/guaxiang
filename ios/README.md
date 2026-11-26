# 瓜相 iOS 版

SwiftUI 原生。這台 Windows 不能編 Swift，推上 GitHub 後由 Actions 的 macOS 機器編譯和跑測試（`.github/workflows/ios-ci.yml`）。

規矩在 `.vibe/規矩檔.md`，Claude 代為決定的事在 `.vibe/代決清單.md`。

## 資料夾

| 位置 | 內容 |
|---|---|
| `project.yml` | 專案描述檔，CI 用 XcodeGen 照它產生 Xcode 專案 |
| `Guaxiang/Engine/` | 判讀引擎：特徵公式、中位數、規則比對、依據清單、提示詞。只用 Foundation，逐行照網頁版 |
| `Guaxiang/Scan/` | ARKit 掃描、把關、Vision 找眉毛眼睛嘴唇、髮際線 |
| `Guaxiang/Report/` | 報告畫面 |
| `Guaxiang/Ask/` | 問古書 |
| `Guaxiang/Settings/` | 設定頁（VeggieKit）和開發工具 |
| `Guaxiang/Engine/MeshLocator.swift` | 從臉部網格的形狀自動找出量測點 |
| `Guaxiang/Store/FacePhoto.swift`、`Guaxiang/Report/AnnotatedPhoto.swift` | 報告最上面的照片和標註 |
| `GuaxiangTests/` | 單元測試；`Fixtures/parity.json` 是網頁版 JS 算出來的標準答案 |
| `tools/` | 產生標準答案、檢查提示詞、產生圖示的小程式 |

規則庫用 repo 根目錄的 `rules.json`，打包時直接帶進 app，這裡沒有另外一份。

## 改了東西之後

| 改了什麼 | 要做什麼 |
|---|---|
| `rules.json`、`index.html` 的算法 | `node ios/tools/make-fixtures.mjs`，重產標準答案 |
| `prompt.js` | 把 `Guaxiang/Engine/Prompt.swift` 改成一樣（寫死的句子在 `AskReply.swift`），跑 `node ios/tools/check-prompt.mjs` 和上面那一行，再跑 `node ios/tools/ask-eval/run.mjs` |
| 圖示 | `python ios/tools/make-icons.py` |
| 任何 Swift | commit、推功能分支，看 Actions 的 iOS CI |

## 現在做到哪

照 HANDOFF 第五節的路線圖：

| # | 項目 | 狀態 |
|---|---|---|
| 1 | 專案骨架、CI 編譯 | 模擬器版編得過、測試會過。TestFlight 打包流程跑通了（`.github/workflows/testflight.yml`，推 `tf-*` tag 觸發）：2026-11-22 `tf-1` 全綠，0.1.0 (1) 上傳成功；同一天 `tf-2`（介面大改版）全綠，0.1.0 (2) 上傳成功，手機還沒驗；2026-11-24 `tf-3`（QC-0006 四筆）全綠，0.1.0 (3) 上傳成功，手機還沒驗。2026-11-25 `tf-4`（九項＋刻度尺＋在交界上＋120Hz）全綠，0.1.0 (4) 上傳成功，手機還沒驗。2026-11-26 `tf-5`（QC-0009＋性能修正）全綠，0.1.0 (5) 上傳成功，手機還沒驗。下一個 tag 是 `tf-6`，多米開口才打 |
| 2 | 量測點 | 2026-11-25 照片方向改用嘴和眼睛的位置判斷，舊照片讀入時轉正。2026-11-24 改成 app 自己從網格形狀找（QC-0006），手動對照工具拿掉。用假臉測過，**真臉還沒在手機上看過** |
| 3 | 掃描流程 | 2026-11-24 多米在真機掃過一次，30 張收得滿 |
| 4 | 量測＋規則判讀 | 判讀引擎跟網頁版逐項一致（有測試）。2026-11-25 多「在交界上」這一種（代決 93–102）。2026-11-24 起量得到，門檻還沒校準 |
| 5 | 報告畫面 | 2026-11-22 照準則改版：總覽＋一區一頁、朱印古書配色（畫板 https://claude.ai/artifact/9vk3MZVLe7Bdo2kbpuftfU）。首頁就能開範例報告。2026-11-24 改成照片滿版＋下方懸浮視窗（QC-0006 第 3 筆，多米選 A），iOS 26.4 模擬器驗過手勢、深色、最大字級、375 寬，**沒在真機看過**，iOS 17／18 也沒跑過。2026-11-25 全部改白話、小圓鈕看原文、拉條一拉就換高度，判讀樣式多米選 B 刻度尺（https://claude.ai/artifact/7bAdzHdrLf8D8AnwdsxB2X），模擬器看過 |
| 6 | 深度特徵 | 公式照搬、標實驗，還沒校準 |
| 7 | 問古書 | 2026-11-24 改成單純對話；防跑題四層、評測 72／74（`tools/ask-eval/report.md`）。內部測試走電腦的 Claude CLI（`tools/claude-bridge`）。中繼站還沒部署。畫面在 iOS 26.4 模擬器用假的轉接端驗過，**手機實連還沒試** |
| 8 | 付費 | 只有骨架（`Store/Storage.swift` 的 `Paywall`） |
| 9 | 上架準備 | 還沒開始 |

## 第一次裝到手機後要做的事

1. **看範例報告**：首頁「先看一份範例報告」（開發工具裡也有）。下方視窗底部的四格都按一次，往上拖成整頁再拉回來，從左緣滑回首頁滑一半放手試一次，深色模式也切一次。
2. **看量測點準不準**：掃完打開報告，最上面的照片會標出眉、眼、鼻、嘴和三停的分界線。線沒有貼在對的位置，截圖給 Claude。
3. **掃一次**：報告如果出現「這次量不到的」，把那幾行字（含代號）告訴 Claude。
4. **連掃三次**：同一個地點，看每一項的數字差多少（設定 → 開發工具 → 量測數字）。路線圖第 3 步的驗收是每項差距小於 3%。
