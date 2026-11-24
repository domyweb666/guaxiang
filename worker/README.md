# 瓜相「問古書」中繼站

網頁不能放 AI 金鑰（任何人都看得到），所以要有一個小中繼站：網頁把文字送過來，中繼站加上金鑰轉給 Anthropic，再把回答送回去。

## 第一次部署（Windows 也可以）

1. 申請 Anthropic API 金鑰：https://console.anthropic.com → API Keys
2. 申請 Cloudflare 帳號（免費方案就夠）：https://dash.cloudflare.com
3. 在這個資料夾打開終端機：
   ```
   npx wrangler login
   npx wrangler secret put ANTHROPIC_API_KEY
   npx wrangler deploy
   ```
4. 部署完會顯示網址，像 `https://guaxiang-ask.你的帳號.workers.dev`
5. 把這個網址貼到 `index.html` 最上面的 `ASK_ENDPOINT`，推上 GitHub

## 會傳什麼

只傳文字：這次量測的結果整理（相符、不同、沒看、古書條文）、使用者填的簡介（只有年紀，沒有生日）、問題、前幾輪的問答。
不傳照片，不傳臉部座標。

## 回傳什麼

`{"kind":"answer","answer":"……［E3］"}`。`kind` 有五種：`answer`、`nodata`（沒講到）、`offtopic`（跑題）、`health`（健康）、`chat`（閒聊）。後四種不帶模型寫的字，畫面顯示 `prompt.js` 的 `FIXED`。模型回的格式不對會自動再問一次。

## 費用

每問一題大約幾千個 token。實際價格看 Anthropic 官網。
想省錢可以把 `wrangler.toml` 的 `MODEL` 改成 `claude-haiku-5-5`。

## 還沒做的

- 每人每天的提問次數限制（上架前要加，可以用 Cloudflare 的 Rate Limiting）
