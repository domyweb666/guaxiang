// 中繼站次數限制的本機測試。用法：node worker/worker.test.mjs
// 不連網、不呼叫 AI：只測到「格式對了、次數還夠」為止，之後的 AI 呼叫用假的 fetch 接住
import assert from "node:assert/strict";
import worker, { checkLimits, clientKey, taipeiDay } from "./worker.js";

const fakeKV = () => {
  const m = new Map();
  return { m, get: async k => m.get(k) ?? null, put: async (k, v) => { m.set(k, v); } };
};
const fakeBurst = max => {
  const n = new Map();
  return { limit: async ({ key }) => { n.set(key, (n.get(key) || 0) + 1); return { success: n.get(key) <= max }; } };
};

let pass = 0;
const test = async (name, fn) => { await fn(); pass++; console.log("ok", name); };

await test("沒綁任何限制就放行", async () => {
  assert.equal(await checkLimits({}, "1.2.3.4"), null);
});

await test("每分鐘超過就擋", async () => {
  const env = { ASK_BURST: fakeBurst(2) };
  assert.equal(await checkLimits(env, "a"), null);
  assert.equal(await checkLimits(env, "a"), null);
  assert.equal((await checkLimits(env, "a")).status, 429);
  assert.equal(await checkLimits(env, "b"), null, "別人不受影響");
});

await test("每天題數到了就擋，隔天重算", async () => {
  const env = { ASK_KV: fakeKV(), DAILY_LIMIT: "3" };
  const day1 = Date.UTC(2026, 10, 26, 3);
  for (let i = 0; i < 3; i++) assert.equal(await checkLimits(env, "a", day1), null);
  const no = await checkLimits(env, "a", day1);
  assert.equal(no.status, 429);
  assert.match(no.error, /3 題/);
  assert.equal(await checkLimits(env, "a", day1 + 24 * 3600 * 1000), null);
});

await test("有 KV 但沒設 DAILY_LIMIT 就不限", async () => {
  const env = { ASK_KV: fakeKV() };
  for (let i = 0; i < 50; i++) assert.equal(await checkLimits(env, "a"), null);
  assert.equal(env.ASK_KV.m.size, 0);
});

await test("換日照台灣時間", async () => {
  assert.equal(taipeiDay(Date.UTC(2026, 10, 25, 15, 59)), "2026-11-25");
  assert.equal(taipeiDay(Date.UTC(2026, 10, 25, 16, 0)), "2026-11-26");
});

await test("認 IP 的順序", async () => {
  const h = o => ({ headers: new Headers(o) });
  assert.equal(clientKey(h({ "cf-connecting-ip": "9.9.9.9", "x-forwarded-for": "1.1.1.1" })), "9.9.9.9");
  assert.equal(clientKey(h({ "x-forwarded-for": "1.1.1.1, 2.2.2.2" })), "1.1.1.1");
  assert.equal(clientKey(h({})), "unknown");
});

await test("整條路：格式錯不扣次數；次數用完回 429，不叫 AI", async () => {
  const env = { ALLOW_APP: "1", ASK_KV: fakeKV(), DAILY_LIMIT: "1", ANTHROPIC_API_KEY: "test" };
  const post = body => new Request("https://x/", {
    method: "POST", body, headers: { "x-guaxiang-client": "ios/0.1.0", "cf-connecting-ip": "5.5.5.5" } });
  let aiCalls = 0;
  globalThis.fetch = async () => { aiCalls++; return new Response("{}", { status: 500 }); };
  assert.equal((await worker.fetch(post("not json"), env)).status, 400);
  assert.equal(env.ASK_KV.m.size, 0, "格式錯不算一題");
  const good = JSON.stringify({ pack: [{ id: "E1", text: "鼻樑直" }], profile: {}, question: "我的財運怎樣？" });
  const first = await worker.fetch(post(good), env);
  assert.notEqual(first.status, 429);
  const second = await worker.fetch(post(good), env);
  assert.equal(second.status, 429);
  const callsBefore = aiCalls;
  await worker.fetch(post(good), env);
  assert.equal(aiCalls, callsBefore, "被擋的不叫 AI");
});

console.log(`全部 ${pass} 條過了`);
