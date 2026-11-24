# Handoff: 芹查 QC-0006 做完三筆，第 3 筆多米選了 A（下方懸浮視窗），還沒寫 Swift

> 產出時間：2026-11-24（前一會話過 400K 自動交接，檔案都沒有改到一半）
> repo：`E:\瓜相\guaxiang`，分支 `ios`，最新 `a293bf6`，跟遠端同步

## ✅ 這次完成了什麼

- #42 幾乎判讀不到：量測點改由 `Engine/MeshLocator.swift` 從網格形狀自動找，眼角眼瞼改由 Vision 找（`Outline.eye`）
- #43 報告最上面放照片標註：`Store/FacePhoto.swift`、`Report/AnnotatedPhoto.swift`，照片只存手機、不進備份
- #45 手動頂點對照：整個拿掉
- 測試 `GuaxiangTests/MeshLocatorTests.swift`；`fdbcc18` 的 iOS CI 綠，24 個測試全過
- 文件：README 狀態表、規矩檔那一條、代決 48–52
- #44 比較：Claude Design 畫板 https://claude.ai/artifact/YBPknTMx9WjnB33q8yp2RF（11 張，沒有打開檢查過）。`.uiux/報告介面-比較-2026-11-24.html` 是舊版，以畫板為準

## 📌 關鍵決策（別再爭論）

- 多米 2026-11-24 選 **A 下方懸浮視窗**
- 切換列（總覽、五官、三停、十二宮、問古書）釘在視窗自己的底部，換區不用先關視窗。視窗沒有「關閉」，回總覽就是按「總覽」
- 照片滿版鋪在上半部，不捲動；換區時只亮那一區的標註。半高約佔下半，可以往上拖成整頁
- 用系統 `.sheet`，不自己刻（準則附錄 E 第 3 項、3-43）
- 芹查說「E:\瓜相 不是芹查認得的 app」只是因為 git 在底下的 guaxiang，專案沒開錯
- 掃描頁進度圈畫到橢圓外面，是單子外的問題，不要動

## 🧩 剩下的工作（工作包）

- [ ] A：報告改成懸浮視窗｜見下面規格｜`Report/ReportView.swift`、`Report/ReportSections.swift`、`Ask/AskView.swift`、`App/GuaxiangApp.swift`、`Design/Theme.swift`｜無
- [ ] B：照片分區標註｜見下面規格｜`Report/AnnotatedPhoto.swift`｜跟 A 共用介面，依序做
- [ ] C：推 `ios` 分支、CI 綠；limrun 模擬器用「範例報告」看版面（範例沒有照片，另塞一張測試圖看照片模式），測完關機器｜依賴 A、B
- [ ] D：文件：代決清單補這輪（53 起）、README 第 5 列、規矩檔不用動；逐筆回報多米

### A 的規格

- `ReportView`：上半部照片滿版（`ignoresSafeArea(edges: .top)`），沒有照片放說明或 `FaceSketch`（範例）。返回用系統的返回鈕和左緣滑回，別蓋掉
- 常駐 sheet：`.presentationDetents([.fraction(約0.5), .large], selection:)`、`.presentationBackgroundInteraction(.enabled(upThrough: 半高))`、`.interactiveDismissDisabled()`、`.presentationDragIndicator(.visible)`、`.presentationCornerRadius(約 36)`、`.presentationBackground(Theme.canvas)`
- 要顧的：進頁才升起、返回時先收（在 `onAppear`／`onDisappear` 控制 isPresented），左緣滑到一半取消時視窗要還在；iOS 26 半高 sheet 會自己懸浮縮進，17–18 是貼邊
- 視窗內容：`NavigationStack` 包內容，切換列用 `safeAreaInset(edge: .bottom)`；每一區標題＋原本的內容
- `ReportSectionView` 拆成「只有內容」和「推入頁」兩種用法。總覽列：臉形（推入臉形頁）、五官／三停／十二宮摘要格、其他古書條文、這次沒看的、標註圖線條、數字明細；這幾列在視窗裡往右推入。「這次量不到的」（gaps）和「結果只當參考」也放總覽
- 免責那一句留在總覽最下面
- 問古書：`AskView` 現在自帶 NavigationStack 和「回到報告」鈕，加一個內嵌用法，首頁的 sheet 用法不變。`askBar` 是 `safeAreaInset`，要跟切換列一起排，鍵盤出來時切換列收起
- 上鎖（`ReportSection.locked`，現在 Paywall 全開）：切到鎖住的區顯示完整版說明，不要 sheet 上再疊 sheet（準則 4-5）
- `AppModel.open(_:)`、`Route.section` 用不到就刪
- 範例報告照用，問古書那一區寫不能問

### B 的規格

- `AnnotatedPhoto` 加 mode：總覽（五官＋三停）、五官、三停、十二宮；加 `fill` 用法：照指定長寬比裁、撐滿上半部，頂端多留（返回鈕和瀏海），底部留視窗圓角的重疊。裁切改成：包住所有點 → 補成目標比例 → 超出照片就縮到照片範圍內
- 十二宮：判得到的（依 `report.palaces` 的 status）畫朱紅實心小標籤寫宮名，其他宮畫白色小圓點。位置從 `PhotoMarks`：命宮＝眉心、財帛＝鼻尖、兄弟＝兩道眉中心、田宅＝兩眼中心、男女＝眼下、妻妾＝外眼角外側、官祿＝眉心和額頂中間、遷移＝兩側 temple、奴僕＝下巴上方、疾厄＝山根；福德、相貌不畫點
- 滿版時圖例改成照片上一小塊或拿掉，五官靠顏色在視窗列上對應
- 切換時標註淡入淡出，減少動態時不動

## ⏭️ 下一步從哪繼續

1. `git -C E:\瓜相\guaxiang log --oneline -3` 確認沒有別的 session 改過
2. 讀 `.vibe/規矩檔.md`、`Report/ReportView.swift`、`Report/ReportSections.swift`、`Report/AnnotatedPhoto.swift`、`Ask/AskView.swift`、`App/GuaxiangApp.swift`
3. 從包 A 開始；commit 訊息寫 QC-0006，只推 `ios` 分支，不打包 TestFlight（下一個 tag 是 tf-3，多米開口才打）

## 🚧 還沒驗

- 真臉：量測點準不準、照片標註有沒有貼到位，要多米在手機上看。模擬器拿不到 ARKit 網格（試過，0 個頂點），別再試
- 舊報告沒有照片，要重新掃一次才看得到

## 🗑️ 雜訊

- Git Bash 長 heredoc 會壞，Swift 用 Write、批次改檔寫成 .py 再跑
