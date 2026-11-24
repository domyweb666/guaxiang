# claude-bridge：讓 iPhone 用這台電腦的 Claude CLI 回答問古書

開發測試用。中繼站（`worker/`）還沒部署的時候，iPhone 上的瓜相把問題送到這台電腦，這支程式交給你登入的 Claude CLI（`claude -p`），再把回答傳回手機。

## 怎麼開

先確認這台電腦裝好 Claude Code，而且 `claude` 已經登入（終端機打 `claude --version` 有版本號就行）。

```
cd ios/tools/claude-bridge
npm install
npm start
```

開起來會印一個 QR code，下面是同一串網址的文字版：

```
http://192.168.0.173:8790/ask?t=0123456789abcdef0123456789abcdef
```

`t=` 後面是這次隨機產生的密碼，每次 `npm start` 都會換，重開之後手機要重掃一次。電腦有好幾張網卡時會每個 IP 都印一行，QR code 只畫第一個，連不上就改貼別行。

要換埠號或模型（預設 8790、sonnet）：

```
PORT=8791 npm start
CLAUDE_MODEL=haiku npm start
```

PowerShell 寫成 `$env:PORT=8791; npm start`。按 Ctrl+C 結束。

## 在 app 裡怎麼接

設定 → 開發工具 → 連電腦的 Claude CLI → 掃 QR code。模擬器沒有相機，把終端機印的那串網址整串貼上。

接上之後，問古書優先走這台電腦；中斷連線才會用中繼站或自己貼的金鑰。

## 限制

- 電腦要開著，這支程式要一直跑著。
- iPhone 跟電腦要連同一個 Wi-Fi。第一次連，iPhone 會問要不要讓瓜相找區網裝置，要按允許。按成不允許，到 iPhone 的設定 → 隱私權與安全性 → 區域網路，把瓜相打開。
- Windows 防火牆第一次會問要不要讓 Node.js 接受區網連線，要按允許（至少勾私人網路）。按錯了到「Windows 安全性 → 防火牆與網路保護 → 允許應用程式通過防火牆」把 Node.js 打勾。
- 用的是你自己的 Claude 訂閱額度，網址和密碼不要給別人。
- 走的是區網裡沒加密的 http，不要在咖啡廳那種公用 Wi-Fi 上開。
- 同一時間只跑一題，後面的排隊。一題最多等 170 秒。手機按停止，這邊跑到一半的也會停。
- Claude CLI 在一個空的暫存資料夾裡跑，關掉所有工具、不載 MCP、不存對話，它只能回文字。
- 終端機只印幾點收到、花幾秒、回的是哪一種，不印問題和回答。

## 協定

跟 `worker/` 一樣。網址都要帶 `?t=<密碼>`，不對回 401 `{"error":"密碼不對"}`。

### `GET /ping?t=<密碼>`

```json
{"ok": true, "name": "<電腦名稱>", "cli": "2.1.81 (Claude Code)"}
```

### `POST /ask?t=<密碼>`

body 最大 1MB：

```json
{"pack": [{"id": "E1", "title": "…", "text": "…"}], "profile": {}, "question": "…", "history": [{"q": "…", "a": "…", "kind": "answer"}]}
```

回：

```json
{"kind": "answer", "answer": "古書說……［E1］。"}
```

`kind` 是 `answer`、`nodata`、`offtopic`、`health`、`chat` 其中一個，後四種不帶模型寫的字。

| 狀態碼 | 什麼時候 |
|---|---|
| 400 | body 不是 JSON、缺依據或問題、未滿 18 歲 |
| 401 | 密碼不對 |
| 413 | 超過 1MB |
| 502 | CLI 失敗，或問了兩次格式都不對 |
| 504 | 超過 170 秒 |
