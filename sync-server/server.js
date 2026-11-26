#!/usr/bin/env node
/**
 * Dòng 同步服务 · 零依赖
 *
 * 提供：邮箱密码登录 + 壁纸清单同步 + 壁纸文件存储。
 * 数据全部落在 ./data 下，直接拷走就等于备份。
 *
 * 运行：
 *   node server.js                  # 默认 8787
 *   PORT=9000 DATA_DIR=/var/dong node server.js
 *   DONG_QUOTA_GB=5 node server.js  # 每个账号的存储上限
 *
 * 反向代理到 https 之后，把 App 的 ApiBaseURL 指到域名即可。
 */
"use strict";

const http = require("node:http");
const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const storage = require("./storage");
const emailcheck = require("./emailcheck");
const mail = require("./mail");
const notify = require("./notify");
const snapshot = require("./snapshot");

const PORT = Number(process.env.SYNC_PORT || process.env.PORT || 8787);
const DATA_DIR = path.resolve(process.env.DATA_DIR || path.join(__dirname, "data"));
const QUOTA_BYTES = Number(process.env.DONG_QUOTA_GB || 2) * 1024 ** 3;
const MAX_ASSET = Number(process.env.DONG_MAX_ASSET_MB || 512) * 1024 ** 2;
/// 头像借用同一套存储，固定用这个 assetId，避免和壁纸混在一起
const AVATAR_ID = "__avatar__";
const TOKEN_DAYS = Number(process.env.DONG_TOKEN_DAYS || 60);
// 是否「注册必须过邮箱验证码」。默认跟随发信是否可用；
// 想先只做域名校验、等新版客户端铺开再强制，就设 MAIL_REQUIRE_CODE=0。
const MAIL_REQUIRE_CODE = String(process.env.MAIL_REQUIRE_CODE || "").trim();

/// 注册是否必须过邮箱验证码：发信可用 + 没被显式关掉
function codeRequired() {
  return mail.isConfigured() && MAIL_REQUIRE_CODE !== "0";
}

// 简易限流：key = 客户端 IP，滑动窗口计数。托管平台没有 Nginx，只能自己兜一层。
// 注意反代场景必须用 X-Forwarded-For，否则所有请求都来自 127.0.0.1，会把所有人一起锁死。
const LIMITS = {
  register: { max: 5, windowMs: 60_000 },
  login: { max: 12, windowMs: 60_000 },
  reset: { max: 6, windowMs: 60_000 },
  emailcode: { max: 6, windowMs: 60_000 },
};
const hits = new Map(); // "ip|bucket" -> { count, resetAt }

function clientIp(req) {
  const xff = req.headers["x-forwarded-for"];
  if (typeof xff === "string" && xff.trim()) return xff.split(",")[0].trim();
  return req.socket.remoteAddress || "unknown";
}

function allow(req, bucket) {
  const rule = LIMITS[bucket];
  if (!rule) return true;
  const key = clientIp(req) + "|" + bucket;
  const now = Date.now();
  const rec = hits.get(key);
  if (!rec || rec.resetAt < now) {
    hits.set(key, { count: 1, resetAt: now + rule.windowMs });
    return true;
  }
  if (rec.count >= rule.max) return false;
  rec.count += 1;
  return true;
}

// 内存别无限涨：每分钟清一次过期记录
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of hits) if (v.resetAt < now) hits.delete(k);
}, 60_000).unref();

storage.init(DATA_DIR, { maxAsset: MAX_ASSET });
snapshot.init(DATA_DIR);
let gatewayHealth = { ok: true, mode: storage.mode() };

const F = {
  accounts: path.join(DATA_DIR, "accounts.json"),
  tokens: path.join(DATA_DIR, "tokens.json"),
  users: path.join(DATA_DIR, "users"),
  // 记录哪些版本已经群发过通知，避免手滑发两遍
  notify: path.join(DATA_DIR, "notify-log.json"),
};

// ── 管理后台（发布时群发更新通知）────────────────────────────
// 令牌走环境变量 ADMIN_TOKEN，没配就整块关闭（返回 503，不暴露任何东西）。
const ADMIN_TOKEN = String(process.env.ADMIN_TOKEN || "").trim();
const notifyJobs = new Map(); // jobId -> { state, version, build, startedAt }

function adminOk(req, url) {
  if (!ADMIN_TOKEN) return false;
  const auth = String(req.headers["authorization"] || "");
  let got = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!got) got = String(url.searchParams.get("t") || "").trim();
  if (!got || got.length !== ADMIN_TOKEN.length) return false;
  try {
    return crypto.timingSafeEqual(Buffer.from(got), Buffer.from(ADMIN_TOKEN));
  } catch {
    return false;
  }
}

function htmlPage(res, code, html) {
  const data = Buffer.from(html);
  res.writeHead(code, {
    "content-type": "text/html; charset=utf-8",
    "content-length": data.length,
    "cache-control": "no-store",
  });
  res.end(data);
}

function baseUrlOf(req) {
  const env = String(process.env.PUBLIC_BASE_URL || "").trim();
  if (env) return env.replace(/\/+$/, "");
  const proto = String(req.headers["x-forwarded-proto"] || "https").split(",")[0].trim();
  const host = String(req.headers["x-forwarded-host"] || req.headers.host || "").trim();
  return host ? `${proto}://${host}` : "";
}

// ── 极简持久化：内存一份 + 原子落盘 ─────────────────────────
let accounts = {}; // email -> { id, salt, hash, createdAt, quotaBytes, emailVerified, emailOptOut }
let tokens = {};   // tokenHash -> { userId, expiresAt }
let notifyLog = {}; // "3.46|68" -> { sentAt, sent, failed }

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return fallback;
  }
}

async function writeJson(file, value) {
  const tmp = file + ".tmp";
  await fsp.mkdir(path.dirname(file), { recursive: true });
  await fsp.writeFile(tmp, JSON.stringify(value));
  await fsp.rename(tmp, file);
}

// ── 邮箱验证码（只在内存里：10 分钟就过期的东西，不值得落盘） ─────
const mailCodes = new Map();   // "email|purpose" -> { code, exp, tries, sentAt }
const codeHistory = new Map(); // email -> [发送时间戳]
const CODE_TTL = 10 * 60_000;  // 有效期 10 分钟
const CODE_GAP = 60_000;       // 同一地址 60 秒才能再发
const CODE_HOURLY = 5;         // 同一地址每小时最多 5 封

function keyOf(email, purpose) { return `${email}|${purpose}`; }

/// 核销验证码：用掉即作废；错 5 次也作废
function takeCode(email, purpose, code) {
  const key = keyOf(email, purpose);
  const rec = mailCodes.get(key);
  if (!rec) return { ok: false, message: "验证码不对或已过期，重新发一个" };
  if (Date.now() > rec.exp) {
    mailCodes.delete(key);
    return { ok: false, message: "验证码过期了，重新发一个" };
  }
  rec.tries += 1;
  if (rec.tries > 5) {
    mailCodes.delete(key);
    return { ok: false, message: "试错太多次，重新发一个验证码" };
  }
  const got = String(code || "").replace(/\s/g, "");
  if (got !== rec.code) return { ok: false, message: "验证码不对" };
  mailCodes.delete(key);
  return { ok: true };
}

async function initStore() {
  await fsp.mkdir(F.users, { recursive: true });
  accounts = readJson(F.accounts, {});
  notifyLog = readJson(F.notify, {});
  tokens = readJson(F.tokens, {});
  // 清掉过期 token
  const now = Date.now();
  for (const [k, v] of Object.entries(tokens)) {
    if (v.expiresAt < now) delete tokens[k];
  }
  await writeJson(F.tokens, tokens);
  console.log(`[dong-sync] data=${DATA_DIR} quota=${(QUOTA_BYTES / 1024 ** 3).toFixed(1)}GB`);
}

// ── 工具 ────────────────────────────────────────────────────
const sha256 = (buf) => crypto.createHash("sha256").update(buf).digest("hex");

function scrypt(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString("hex");
}

function safeId(id) {
  // 只留文件名安全字符，防止 ../ 穿越
  return String(id).replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 120);
}

function manifestPath(userId) {
  return path.join(F.users, userId, "manifest.json");
}

function assetDir(userId) {
  return path.join(F.users, userId, "assets");
}

async function readManifest(userId) {
  const m = readJson(manifestPath(userId), null);
  return m || { rev: 0, items: [], order: [], updatedAt: 0 };
}

async function usedBytes(userId) {
  return storage.usedBytes(userId);
}

// ── HTTP ────────────────────────────────────────────────────
function send(res, code, body, headers = {}) {
  const data = Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
  res.writeHead(code, {
    "content-type": Buffer.isBuffer(body) ? "application/octet-stream" : "application/json; charset=utf-8",
    "content-length": data.length,
    "cache-control": "no-store",
    ...headers,
  });
  res.end(data);
}

function fail(res, code, message) {
  send(res, code, { error: message });
}

async function readBody(req, limit = 2 * 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > limit) throw new Error("payload too large");
    chunks.push(c);
  }
  if (!chunks.length) return "";
  return Buffer.concat(chunks).toString("utf8");
}

function authUser(req) {
  const h = req.headers["authorization"] || "";
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) return null;
  const rec = tokens[sha256(Buffer.from(m[1]))];
  if (!rec) return null;
  if (rec.expiresAt < Date.now()) return null;
  // 每台设备「最近活跃」——设备列表要显示这个
  rec.lastSeen = Date.now();
  tokensDirty = true;
  const entry = Object.values(accounts).find((a) => a.id === rec.userId);
  if (!entry) return null;
  return entry;
}

function rawToken(req) {
  const m = /^Bearer\s+(.+)$/i.exec(req.headers["authorization"] || "");
  return m ? m[1] : null;
}

function issueToken(userId, device) {
  const raw = crypto.randomBytes(32).toString("hex");
  const now = Date.now();
  tokens[sha256(Buffer.from(raw))] = {
    userId,
    device: String(device || "").slice(0, 60) || "未知设备",
    createdAt: now,
    lastSeen: now,
    expiresAt: now + TOKEN_DAYS * 86400_000,
  };
  return raw;
}

/// 设备名由客户端在请求头里报上来；没报就写「未知设备」，不要瞎猜 UA
function deviceName(req) {
  const raw = String(req.headers["x-device-name"] || "").trim();
  if (!raw) return "未知设备";
  // 客户端做了百分号编码（中文电脑名在 HTTP 头里会花）
  let d = raw;
  try { d = decodeURIComponent(raw); } catch {}
  return d.slice(0, 60) || "未知设备";
}

/// 最近活跃时间只在内存里更新，60 秒落一次盘。
/// 每条请求都写文件的话，磁盘和历史快照会被刷爆。
let tokensDirty = false;
setInterval(() => {
  if (!tokensDirty) return;
  tokensDirty = false;
  writeJson(F.tokens, tokens).catch(() => {});
}, 60_000).unref();

function validEmail(s) {
  return typeof s === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) && s.length <= 160;
}

const NOTIFY_PAGE = `<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dòng · 发更新通知</title>
<style>
  :root { --ink:#26262a; --mute:#8b857d; --line:#e6e2dc; --accent:#e8944a; --bg:#f7f6f4; }
  * { box-sizing:border-box }
  body { margin:0; background:var(--bg); color:var(--ink);
         font:15px/1.7 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif; }
  .wrap { max-width:560px; margin:38px auto 60px; background:#fff; border-radius:16px;
          padding:30px 32px 26px; box-shadow:0 10px 30px rgba(0,0,0,.06); }
  h1 { font-size:20px; margin:0 0 4px; letter-spacing:-.01em }
  .sub { color:var(--mute); font-size:13px; margin-bottom:22px }
  label { display:block; font-size:12.5px; color:var(--mute); margin:14px 0 6px }
  input[type=text], input[type=password], textarea {
    width:100%; padding:10px 12px; border:1px solid var(--line); border-radius:9px;
    font:inherit; font-size:14px; background:#fbfaf9; outline:none }
  input:focus, textarea:focus { border-color:var(--accent); background:#fff }
  textarea { min-height:150px; resize:vertical; line-height:1.65 }
  .row { display:flex; gap:12px } .row > div { flex:1 }
  .check { display:flex; gap:10px; align-items:flex-start; margin:20px 0 6px;
           padding:14px; border:1px solid var(--line); border-radius:11px; background:#fbfaf9 }
  .check input { margin-top:3px } .check b { font-size:14px }
  .check span { display:block; color:var(--mute); font-size:12.5px }
  button { border:0; border-radius:9px; font:inherit; font-weight:600; font-size:14px;
           padding:11px 18px; cursor:pointer }
  .primary { background:var(--accent); color:#fff }
  .primary:disabled { opacity:.45; cursor:not-allowed }
  .ghost { background:#f1efec; color:var(--ink) }
  .acts { display:flex; gap:10px; margin-top:20px; flex-wrap:wrap }
  .msg { margin-top:16px; font-size:13.5px; white-space:pre-wrap }
  .bar { height:6px; background:#eee; border-radius:4px; overflow:hidden; margin-top:12px; display:none }
  .bar > i { display:block; height:100%; width:0; background:var(--accent); transition:width .25s }
  .hint { color:var(--mute); font-size:12px; margin-top:6px }
  .ok { color:#2f8f4e } .bad { color:#c0392b }
</style>
<div class="wrap">
  <h1>发「新版本」通知</h1>
  <div class="sub">发布后在这里勾一下，就给所有注册用户发一封更新邮件。不勾就什么都不用做。</div>

  <label>管理令牌</label>
  <input id="tok" type="password" placeholder="ADMIN_TOKEN（只存在本机浏览器里）">

  <div class="row">
    <div><label>版本号</label><input id="ver" type="text" placeholder="3.46"></div>
    <div><label>build</label><input id="build" type="text" placeholder="68"></div>
  </div>

  <label>更新内容（一行一条，用「·」开头；这几行会变成邮件里的列表）</label>
  <textarea id="notes" placeholder="· 修复退出登录后再登录，壁纸空白两三分钟的问题&#10;· 点底栏空白处不再误切壁纸"></textarea>

  <div class="check">
    <input id="send" type="checkbox">
    <div><b>给所有用户发这封通知</b>
      <span>不勾也行：可以先不勾，点「预览收件人数」看人数和邮件标题。</span></div>
  </div>

  <div class="acts">
    <button class="ghost" id="preview">预览收件人数</button>
    <button class="ghost" id="test">先发给我自己（1 封）</button>
    <button class="primary" id="go" disabled>发送给所有用户</button>
  </div>

  <div class="bar" id="bar"><i></i></div>
  <div class="msg" id="msg"></div>
  <div class="hint">同一个版本只发一次；重发需要在接口里带 force。每封邮件底部都有退订链接。</div>
</div>
<script>
var $ = function (id) { return document.getElementById(id); };
var tok = function () { return $("tok").value.trim(); };
$("tok").value = localStorage.getItem("dongAdminTok") || "";
$("tok").addEventListener("input", function () { localStorage.setItem("dongAdminTok", tok()); });
$("send").addEventListener("change", function () { $("go").disabled = !$("send").checked; });

function say(text, cls) {
  var m = $("msg");
  m.className = "msg " + (cls || "");
  m.textContent = text;
}
function payload(extra) {
  var base = {
    version: $("ver").value.trim(),
    build: Number($("build").value.trim() || 0),
    notes: $("notes").value
  };
  for (var k in (extra || {})) base[k] = extra[k];
  return base;
}
function call(path, opts) {
  return fetch(path, Object.assign({
    headers: { "content-type": "application/json", authorization: "Bearer " + tok() }
  }, opts || {})).then(function (r) {
    return r.json().catch(function () { return {}; }).then(function (j) {
      if (!r.ok) throw new Error(j.error || ("请求失败 " + r.status));
      return j;
    });
  });
}

$("preview").onclick = function () {
  say("查询中…");
  call("/api/admin/notify", { method: "POST", body: JSON.stringify(payload({ dryRun: true })) })
    .then(function (j) {
      var text = "收件人 " + j.recipients + " 人";
      if (j.skippedOptOut) text += "，已退订 " + j.skippedOptOut + " 人跳过";
      if (j.alreadyNotified) text += "\n⚠ 这个版本已经发过 " + j.alreadyNotified.sent + " 人";
      text += "\n邮件标题：" + j.subject;
      say(text, j.alreadyNotified ? "bad" : "ok");
    })
    .catch(function (e) { say(e.message, "bad"); });
};

$("test").onclick = function () {
  say("正在给第一个用户发一封测试信…");
  call("/api/admin/notify", { method: "POST", body: JSON.stringify(payload({ limit: 1, force: true })) })
    .then(function (j) { poll(j.jobId); })
    .catch(function (e) { say(e.message, "bad"); });
};

$("go").onclick = function () {
  if (!$("send").checked) return;
  if (!confirm("确定给所有用户发这封更新通知？发出后撤不回来。")) return;
  say("开始发送…");
  $("go").disabled = true;
  $("bar").style.display = "block";
  call("/api/admin/notify", { method: "POST", body: JSON.stringify(payload()) })
    .then(function (j) { poll(j.jobId); })
    .catch(function (e) { say(e.message, "bad"); $("go").disabled = false; });
};

function poll(id) {
  $("bar").style.display = "block";
  var tick = function () {
    setTimeout(function () {
      call("/api/admin/notify-status?id=" + id).then(function (j) {
        var doneCount = j.sent + j.failed;
        var pct = j.total ? Math.round(doneCount / j.total * 100) : 0;
        $("bar").firstElementChild.style.width = pct + "%";
        var text = "已发 " + j.sent + " · 失败 " + j.failed + " · 共 " + j.total;
        if (j.current) text += "（正在发 " + j.current + "）";
        say(text);
        if (j.done) {
          var fin = "完成：成功 " + j.sent + "，失败 " + j.failed + "。";
          if (j.errors && j.errors.length) fin += "\n" + j.errors.slice(0, 5).join("\n");
          say(fin, j.failed ? "bad" : "ok");
          return;
        }
        tick();
      }).catch(function (e) { say(e.message, "bad"); });
    }, 900);
  };
  tick();
}
</script></html>`;

// ── 路由 ────────────────────────────────────────────────────
async function handle(req, res) {
  const url = new URL(req.url, "http://localhost");
  const p = url.pathname;
  const method = req.method || "GET";

  if (p === "/healthz") {
    const healthy = gatewayHealth.ok;
    return send(res, healthy ? 200 : 503, {
      ok: healthy,
      time: Date.now(),
      storage: gatewayHealth.mode,
      // 排障用：看邮箱验证是不是真开着（off = 只做域名真实性校验）
      mail: mail.providerName(),
      mailCodeRequired: codeRequired(),
      snapshot: snapshot.status().enabled ? "on" : "off",
      // 排障用：远程就能看出快照到底推没推、恢复有没有跑
      snapDetail: snapshot.status(),
      ...(healthy ? {} : { error: gatewayHealth.error }),
    });
  }

  // 发布后用来「勾一下发通知」的小页面（纯前端，所有动作都要令牌）
  if (p === "/admin/notify" && method === "GET") {
    return htmlPage(res, 200, NOTIFY_PAGE);
  }

  // ---- 管理：发布时群发更新通知 ----
  // 官网发布后台勾了「给用户发更新通知」就调这里；不勾就什么都不用调。
  if (p === "/api/admin/notify" && method === "POST") {
    if (!ADMIN_TOKEN) return fail(res, 503, "未配置管理令牌");
    if (!adminOk(req, url)) return fail(res, 401, "没有权限");
    let body;
    try {
      body = JSON.parse(await readBody(req, 256 * 1024) || "{}");
    } catch {
      return fail(res, 400, "请求格式不对");
    }
    const version = String(body.version || "").trim();
    const build = Number(body.build || 0);
    const notes = String(body.notes || "");
    if (!/^\d+\.\d+(\.\d+)?$/.test(version)) return fail(res, 400, "版本号格式不对");
    if (!(build > 0)) return fail(res, 400, "build 不对");
    if (!mail.isConfigured()) return fail(res, 503, "还没配置发信通道");

    const key = `${version}|${build}`;
    const done = notifyLog[key];
    if (done && !body.force) {
      return fail(res, 409, `这个版本在 ${new Date(done.sentAt).toLocaleString("zh-CN")} 已经通知过 ${done.sent} 人；要再发请显式重发`);
    }
    const recipients = Object.values(accounts).filter((u) => u && u.id && !u.emailOptOut).length;
    if (body.dryRun) {
      return send(res, 200, {
        ok: true, dryRun: true, recipients,
        skippedOptOut: Object.values(accounts).filter((u) => u && u.emailOptOut).length,
        alreadyNotified: done || null,
        provider: mail.providerName(),
        subject: `Dòng ${version} 已发布`,
      });
    }
    if (!recipients) return fail(res, 400, "还没有可发的用户");

    const jobId = crypto.randomUUID().slice(0, 8);
    const state = { total: recipients, sent: 0, failed: 0, done: false, errors: [], current: "" };
    notifyJobs.set(jobId, { state, version, build, startedAt: Date.now() });

    const base = baseUrlOf(req);
    notify.broadcast({
      accounts,
      version, build, notes, baseUrl: base,
      // 试跑模式只发前 N 个（想先给自己发一封就用 limit=1）
      limit: Number(body.limit || 0),
      onProgress: (st) => { Object.assign(state, st); },
    }).then(async (final) => {
      notifyLog[key] = { sentAt: Date.now(), sent: final.sent, failed: final.failed };
      try { await writeJson(F.notify, notifyLog); } catch { /* 记账失败不影响已发出的信 */ }
      console.log(`[notify] ${key} 发送完成：成功 ${final.sent} / 失败 ${final.failed}`);
    }).catch((e) => {
      state.done = true;
      state.errors.push(String(e && e.message || e));
      console.error("[notify] 任务出错", String(e && e.message || e));
    });

    return send(res, 200, { ok: true, jobId, recipients });
  }

  if (p === "/api/admin/notify-status" && method === "GET") {
    if (!ADMIN_TOKEN) return fail(res, 503, "未配置管理令牌");
    if (!adminOk(req, url)) return fail(res, 401, "没有权限");
    const job = notifyJobs.get(String(url.searchParams.get("id") || ""));
    if (!job) return fail(res, 404, "没有这个任务");
    return send(res, 200, { ok: true, version: job.version, build: job.build, ...job.state });
  }

  // 退订：邮件里点一下就生效，不需要登录
  if (p === "/api/mail/unsubscribe" && method === "GET") {
    const uid = String(url.searchParams.get("u") || "");
    const t = String(url.searchParams.get("t") || "");
    const hit = Object.entries(accounts).find(([, u]) => u && u.id === uid);
    const ok = hit && t && t === notify.unsubToken(uid);
    if (ok) {
      hit[1].emailOptOut = true;
      accounts[hit[0]] = hit[1];
      await writeJson(F.accounts, accounts);
      snapshot.markDirtySoon();
    }
    return htmlPage(res, ok ? 200 : 400, `<!doctype html><meta charset="utf-8">
      <title>${ok ? "已退订" : "链接无效"}</title>
      <div style="max-width:460px;margin:80px auto;font-family:-apple-system,'PingFang SC',sans-serif;color:#26262a;text-align:center">
        <h2 style="font-weight:600">${ok ? "已退订更新通知" : "这个链接无效"}</h2>
        <p style="color:#8b857d;font-size:14px">${ok ? "以后有新版不会再打扰你。想重新订阅，登录后在账号里联系我们即可。" : "可能是链接不完整，或者这个账号已经不存在了。"}</p>
      </div>`);
  }

  // 公开配置（客户端据此决定要不要显示「验证码」那一行）
  if (p === "/api/auth/config" && method === "GET") {
    return send(res, 200, { mail: mail.isConfigured(), mailCodeRequired: codeRequired() });
  }

  // ---- 发送邮箱验证码（不需要登录）----
  // purpose=register 注册验证；purpose=reset 将来做「邮件找回密码」用。
  // 没配发信通道时直接 501，客户端据此把验证码那一行隐藏掉、继续用域名校验。
  if (p === "/api/auth/email/code" && method === "POST") {
    if (!allow(req, "emailcode")) return fail(res, 429, "试得太快了，等一分钟再试");
    let body;
    try {
      body = JSON.parse(await readBody(req) || "{}");
    } catch {
      return fail(res, 400, "请求格式不对");
    }
    const email = emailcheck.normalize(body.email);
    const purpose = body.purpose === "reset" ? "reset" : "register";
    if (!validEmail(email)) return fail(res, 400, "邮箱格式不对");

    const chk = await emailcheck.check(email);
    if (!chk.ok) return fail(res, 400, chk.message);

    if (purpose === "register" && accounts[email]) {
      return fail(res, 409, "这个邮箱已经注册过了");
    }
    // 找回密码不透露邮箱是否注册过：假装发了
    if (purpose === "reset" && !accounts[email]) {
      return send(res, 200, { ok: true, cooldown: CODE_GAP / 1000 });
    }
    if (!mail.isConfigured()) return fail(res, 501, "邮箱验证暂未开通");

    const now = Date.now();
    const prev = mailCodes.get(keyOf(email, purpose));
    if (prev && now - prev.sentAt < CODE_GAP) {
      const wait = Math.ceil((CODE_GAP - (now - prev.sentAt)) / 1000);
      return fail(res, 429, `别急，${wait} 秒后再试`);
    }
    const hist = (codeHistory.get(email) || []).filter((t) => now - t < 3600_000);
    if (hist.length >= CODE_HOURLY) {
      return fail(res, 429, "这个邮箱收得有点多了，过一会儿再试");
    }

    const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, "0");
    const r = await mail.sendCode(email, code, purpose);
    if (!r.ok) return fail(res, 502, r.error || "验证码发送失败");

    mailCodes.set(keyOf(email, purpose), { code, exp: now + CODE_TTL, tries: 0, sentAt: now });
    hist.push(now);
    codeHistory.set(email, hist);

    const payload = { ok: true, cooldown: CODE_GAP / 1000 };
    // 只有本地联调（console 模式 + 显式开关）才回显验证码，线上绝不能回
    if (r.dev && process.env.MAIL_DEV_ECHO === "1") payload.devCode = code;
    return send(res, 200, payload);
  }

  // ---- 注册 ----
  if (p === "/api/auth/register" && method === "POST") {
    if (!allow(req, "register")) return fail(res, 429, "试得太快了，等一分钟再试");
    let body;
    try {
      body = JSON.parse(await readBody(req) || "{}");
    } catch {
      return fail(res, 400, "请求格式不对");
    }
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    if (!validEmail(email)) return fail(res, 400, "邮箱格式不对");
    if (password.length < 8) return fail(res, 400, "密码至少 8 位");
    if (accounts[email]) return fail(res, 409, "这个邮箱已经注册过了");

    // 域名必须真的存在、真的能收信——只校验格式的话，asdf@asdf.com 也能注册成功
    const chk = await emailcheck.check(email);
    if (!chk.ok) return fail(res, 400, chk.message);

    // 开了发信就必须过验证码（证明这个邮箱确实能收到信）；没开就只做上面的域名校验
    const mailOn = codeRequired();
    if (mailOn) {
      if (!String(body.code || "").trim()) {
        return fail(res, 400, "请先获取邮箱验证码，再注册");
      }
      const v = takeCode(email, "register", body.code);
      if (!v.ok) return fail(res, 400, v.message);
    }

    const salt = crypto.randomBytes(16).toString("hex");
    const user = {
      id: crypto.randomUUID(),
      salt,
      hash: scrypt(password, salt),
      createdAt: Date.now(),
      quotaBytes: QUOTA_BYTES,
      // 只有真的收过验证码才算已验证；没开发信时先记 false，将来可以登录后补验
      emailVerified: mailOn,
    };
    accounts[email] = user;
    await writeJson(F.accounts, accounts);
    snapshot.markDirtySoon();   // 新账号别等 10 分钟
    await fsp.mkdir(assetDir(user.id), { recursive: true });

    const token = issueToken(user.id, deviceName(req));
    await writeJson(F.tokens, tokens);
    snapshot.markDirty();
    return send(res, 200, { token, email, userId: user.id, quotaBytes: user.quotaBytes });
  }

  // ---- 登录 ----
  if (p === "/api/auth/login" && method === "POST") {
    if (!allow(req, "login")) return fail(res, 429, "试得太快了，等一分钟再试");
    let body;
    try {
      body = JSON.parse(await readBody(req) || "{}");
    } catch {
      return fail(res, 400, "请求格式不对");
    }
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    const user = accounts[email];
    // 统一的失败文案：不透露邮箱是否存在
    if (!user) return fail(res, 401, "邮箱或密码不正确");
    const hash = scrypt(password, user.salt);
    const ok = crypto.timingSafeEqual(Buffer.from(hash, "hex"), Buffer.from(user.hash, "hex"));
    if (!ok) return fail(res, 401, "邮箱或密码不正确");

    const token = issueToken(user.id, deviceName(req));
    await writeJson(F.tokens, tokens);
    snapshot.markDirty();
    return send(res, 200, { token, email, userId: user.id, quotaBytes: user.quotaBytes });
  }

  // ---- 用恢复码重设密码（不需要登录）----
  // 这是「忘了密码」的唯一出路：用户事先抄下 16 位恢复码，用它换新密码。
  // 恢复码一次性，用掉就作废，必须重新生成。
  if (p === "/api/auth/recovery/reset" && method === "POST") {
    if (!allow(req, "reset")) return fail(res, 429, "试得太快了，等一分钟再试");
    let body;
    try {
      body = JSON.parse(await readBody(req) || "{}");
    } catch {
      return fail(res, 400, "请求格式不对");
    }
    const email = String(body.email || "").trim().toLowerCase();
    const code = String(body.code || "").replace(/[^A-Za-z0-9]/g, "").toUpperCase();
    const newPassword = String(body.newPassword || "");
    if (newPassword.length < 8) return fail(res, 400, "新密码至少 8 位");
    if (!validEmail(email)) return fail(res, 400, "邮箱格式不对");

    // 统一文案：不透露邮箱是否存在、是否生成过恢复码
    const bad = () => fail(res, 400, "邮箱或恢复码不正确");
    const u = accounts[email];
    if (!u || !u.recovery) return bad();
    if (u.recovery.createdAt && Date.now() - u.recovery.createdAt > 365 * 86400_000) {
      return fail(res, 400, "恢复码过期了，请登录后重新生成");
    }
    const got = scrypt(code, u.recovery.salt);
    const want = u.recovery.hash;
    if (got.length !== want.length) return bad();
    if (!crypto.timingSafeEqual(Buffer.from(got, "hex"), Buffer.from(want, "hex"))) return bad();

    const salt = crypto.randomBytes(16).toString("hex");
    u.salt = salt;
    u.hash = scrypt(newPassword, salt);
    delete u.recovery;                     // 一次性，用掉即失效
    accounts[email] = u;
    await writeJson(F.accounts, accounts);

    // 全部设备下线：能拿到恢复码的人应该是主人，但保险起见重登一次
    for (const [k, v] of Object.entries(tokens)) {
      if (v.userId === u.id) delete tokens[k];
    }
    await writeJson(F.tokens, tokens);
    snapshot.markDirtySoon();
    return send(res, 200, { ok: true });
  }

  // ---- 以下都要登录 ----
  const user = authUser(req);
  if (!user) return fail(res, 401, "登录已过期，请重新登录");

  if (p === "/api/auth/logout" && method === "POST") {
    const h = req.headers["authorization"] || "";
    const m = /^Bearer\s+(.+)$/i.exec(h);
    if (m) {
      delete tokens[sha256(Buffer.from(m[1]))];
      await writeJson(F.tokens, tokens);
      snapshot.markDirty();
    }
    return send(res, 200, { ok: true });
  }

  // ---- 登录设备 ----
  if (p === "/api/auth/sessions" && method === "GET") {
    const cur = sha256(Buffer.from(rawToken(req) || ""));
    const list = Object.entries(tokens)
      .filter(([, v]) => v.userId === user.id && v.expiresAt > Date.now())
      .map(([k, v]) => ({
        id: k.slice(0, 8),
        device: v.device || "未知设备",
        createdAt: v.createdAt || 0,
        lastSeen: v.lastSeen || v.createdAt || 0,
        current: k === cur,
      }))
      .sort((a, b) => Number(b.current) - Number(a.current) || b.lastSeen - a.lastSeen);
    return send(res, 200, { sessions: list });
  }

  // 踢掉一台设备；id=others 表示「除了当前这台全踢」
  if (p === "/api/auth/sessions" && method === "DELETE") {
    const id = String(url.searchParams.get("id") || "").trim();
    const cur = sha256(Buffer.from(rawToken(req) || ""));
    if (id === "others") {
      let n = 0;
      for (const [k, v] of Object.entries(tokens)) {
        if (v.userId === user.id && k !== cur) { delete tokens[k]; n += 1; }
      }
      await writeJson(F.tokens, tokens);
      snapshot.markDirty();
      return send(res, 200, { ok: true, removed: n });
    }
    if (!/^[0-9a-f]{8}$/.test(id)) return fail(res, 400, "设备标识不对");
    const hit = Object.entries(tokens).find(([k, v]) => k.startsWith(id) && v.userId === user.id);
    if (!hit) return fail(res, 404, "这个设备已经不在了");
    delete tokens[hit[0]];
    await writeJson(F.tokens, tokens);
    snapshot.markDirty();
    return send(res, 200, { ok: true, self: hit[0] === cur });
  }

  // ---- 恢复码 ----
  if (p === "/api/auth/recovery" && method === "GET") {
    return send(res, 200, {
      hasRecovery: !!user.recovery,
      createdAt: user.recovery ? user.recovery.createdAt : 0,
    });
  }

  if (p === "/api/auth/recovery" && method === "POST") {
    // 去掉容易看错的 0/O/1/I/L，抄写不易出错
    const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    const group = () => Array.from({ length: 4 },
      () => alphabet[crypto.randomInt(alphabet.length)]).join("");
    const code = [group(), group(), group(), group()].join("-");
    const salt = crypto.randomBytes(16).toString("hex");
    user.recovery = {
      salt,
      hash: scrypt(code.replace(/-/g, ""), salt),
      createdAt: Date.now(),
    };
    const email = Object.keys(accounts).find((e) => accounts[e].id === user.id) || "";
    if (email) accounts[email] = user;
    await writeJson(F.accounts, accounts);
    snapshot.markDirtySoon();
    // 明文只在这里出现一次，服务端只存哈希
    return send(res, 200, { code, createdAt: user.recovery.createdAt });
  }

  if (p === "/api/auth/recovery" && method === "DELETE") {
    delete user.recovery;
    const email = Object.keys(accounts).find((e) => accounts[e].id === user.id) || "";
    if (email) accounts[email] = user;
    await writeJson(F.accounts, accounts);
    snapshot.markDirty();
    return send(res, 200, { ok: true });
  }

  // ---- 改密码 ----
  if (p === "/api/auth/password" && method === "POST") {
    if (!allow(req, "login")) return fail(res, 429, "试得太快了，等一分钟再试");
    let body;
    try {
      body = JSON.parse(await readBody(req) || "{}");
    } catch {
      return fail(res, 400, "请求格式不对");
    }
    const oldPassword = String(body.oldPassword || "");
    const newPassword = String(body.newPassword || "");
    if (newPassword.length < 8) return fail(res, 400, "新密码至少 8 位");
    if (oldPassword === newPassword) return fail(res, 400, "新密码和旧密码一样");

    const hash = scrypt(oldPassword, user.salt);
    if (!crypto.timingSafeEqual(Buffer.from(hash, "hex"), Buffer.from(user.hash, "hex"))) {
      return fail(res, 401, "当前密码不对");
    }

    const salt = crypto.randomBytes(16).toString("hex");
    user.salt = salt;
    user.hash = scrypt(newPassword, salt);
    const email = Object.keys(accounts).find((e) => accounts[e].id === user.id) || "";
    if (email) accounts[email] = user;
    await writeJson(F.accounts, accounts);
    snapshot.markDirty();

    // 其它设备上的登录作废，当前这台保留
    const keep = rawToken(req);
    const keepHash = keep ? sha256(Buffer.from(keep)) : null;
    for (const [k, v] of Object.entries(tokens)) {
      if (v.userId === user.id && k !== keepHash) delete tokens[k];
    }
    await writeJson(F.tokens, tokens);
    return send(res, 200, { ok: true });
  }

  if (p === "/api/me" && method === "GET") {
    const used = await usedBytes(user.id);
    const email = Object.keys(accounts).find((e) => accounts[e].id === user.id) || "";
    return send(res, 200, { email, userId: user.id, quotaBytes: user.quotaBytes, usedBytes: used });
  }

  // ---- 个人资料（昵称 / 头像） ----
  // 放在 /api/auth/ 下面是有意的：反代已经转发这个前缀，不用为它再加路由。
  // 单独开 /api/profile 会被官网自己的 404 页面吃掉（实测）。
  if (p === "/api/auth/profile" && method === "GET") {
    const email = Object.keys(accounts).find((e) => accounts[e].id === user.id) || "";
    const hit = await storage.locate(user.id, AVATAR_ID).catch(() => null);
    return send(res, 200, {
      email,
      displayName: user.displayName || "",
      hasAvatar: !!hit,
    });
  }

  if (p === "/api/auth/profile" && method === "PUT") {
    let body;
    try {
      body = JSON.parse(await readBody(req) || "{}");
    } catch {
      return fail(res, 400, "请求格式不对");
    }
    const name = String(body.displayName || "").trim();
    if (name.length > 20) return fail(res, 400, "名字最多 20 个字");
    user.displayName = name;
    const email = Object.keys(accounts).find((e) => accounts[e].id === user.id) || "";
    if (email) accounts[email] = user;
    await writeJson(F.accounts, accounts);
    snapshot.markDirty();
    return send(res, 200, { ok: true, displayName: name });
  }

  // 头像：取（gateway 302 到签名直链，disk 直接回文件）
  if (p === "/api/auth/avatar" && method === "GET") {
    const hit = await storage.locate(user.id, AVATAR_ID).catch(() => null);
    if (!hit) return fail(res, 404, "没有头像");
    if (hit.kind === "url") {
      return send(res, 302, Buffer.alloc(0), { location: hit.url, "cache-control": "no-store" });
    }
    try {
      const st = await fsp.stat(hit.file);
      res.writeHead(200, {
        "content-type": "image/png",
        "content-length": st.size,
        "cache-control": "no-store",
      });
      fs.createReadStream(hit.file).pipe(res);
      return;
    } catch {
      return fail(res, 404, "没有头像");
    }
  }

  // 头像：上传（客户端已缩到 256×256 PNG，这里再兜一道 512KB 上限）
  if (p === "/api/auth/avatar" && method === "PUT") {
    const size = Number(req.headers["content-length"] || 0);
    if (size > 512 * 1024) return fail(res, 413, "头像太大了");
    try {
      await storage.put(user.id, AVATAR_ID, req);
      snapshot.markDirty();
      return send(res, 200, { ok: true });
    } catch (e) {
      console.error("[dong-sync] avatar put failed", String(e.message || e));
      return fail(res, 502, "头像保存失败，请重试");
    }
  }

  if (p === "/api/auth/avatar" && method === "DELETE") {
    await storage.del(user.id, AVATAR_ID);
    snapshot.markDirty();
    return send(res, 200, { ok: true });
  }

  if (p === "/api/sync/manifest" && method === "GET") {
    const m = await readManifest(user.id);
    return send(res, 200, m);
  }

  if (p === "/api/sync/manifest" && method === "PUT") {
    const ifMatch = req.headers["if-match"];
    const current = await readManifest(user.id);
    if (ifMatch !== undefined && String(current.rev) !== String(ifMatch)) {
      return send(res, 409, { error: "rev 冲突", manifest: current });
    }
    let body;
    try {
      body = JSON.parse(await readBody(req, 4 * 1024 * 1024) || "{}");
    } catch {
      return fail(res, 400, "清单格式不对");
    }
    const items = Array.isArray(body.items) ? body.items : [];
    if (items.length > 5000) return fail(res, 413, "壁纸太多了");
    const next = {
      rev: current.rev + 1,
      items,
      order: Array.isArray(body.order) ? body.order.slice(0, 5000) : [],
      updatedAt: Date.now(),
    };
    await writeJson(manifestPath(user.id), next);
    snapshot.markDirty();
    return send(res, 200, { rev: next.rev, updatedAt: next.updatedAt });
  }

  // ---- 壁纸文件 ----
  const assetMatch = /^\/api\/sync\/asset\/([^/]+)$/.exec(p);
  if (assetMatch) {
    const id = safeId(decodeURIComponent(assetMatch[1]));
    if (method === "PUT") {
      const declared = req.headers["x-content-length"] || req.headers["content-length"];
      const size = Number(declared || 0);
      if (size > MAX_ASSET) return fail(res, 413, "这张壁纸太大了");

      // 覆盖上传时，先算「净增量」再判配额
      const used = await usedBytes(user.id);
      const existing = await storage.locate(user.id, id).catch(() => null);
      const replaceBytes = existing && existing.size ? existing.size : 0;
      if (used - replaceBytes + size > user.quotaBytes) return fail(res, 507, "空间不够了");

      try {
        const r = await storage.put(user.id, id, req);
        snapshot.markDirty();
        return send(res, 200, { id, bytes: r.bytes, sha256: r.sha256 });
      } catch (e) {
        const msg = String(e.message || e);
        if (msg.includes("too large")) return fail(res, 413, "这张壁纸太大了");
        console.error("[dong-sync] put failed", msg);
        return fail(res, 502, "存储写入失败，请重试");
      }
    }
    if (method === "GET") {
      const hit = await storage.locate(user.id, id);
      if (!hit) return fail(res, 404, "云端没有这个文件");
      if (hit.kind === "url") {
        // 302 给 App 直连对象存储，512MB 不经过本进程
        return send(res, 302, Buffer.alloc(0), { location: hit.url, "cache-control": "no-store" });
      }
      try {
        const st = await fsp.stat(hit.file);
        res.writeHead(200, {
          "content-type": "application/octet-stream",
          "content-length": st.size,
          "cache-control": "no-store",
        });
        fs.createReadStream(hit.file).pipe(res);
        return;
      } catch {
        return fail(res, 404, "云端没有这个文件");
      }
    }
    if (method === "DELETE") {
      await storage.del(user.id, id);
      snapshot.markDirty();
      return send(res, 200, { ok: true });
    }
  }

  return fail(res, 404, "没有这个接口");
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((e) => {
    console.error("[dong-sync] error", e);
    if (!res.headersSent) fail(res, 500, "服务器出错了");
    else res.end();
  });
});

(async () => {
  // 先看要不要从快照恢复：平台会清 /tmp，本地可能一个文件都不剩
  try {
    const r = await snapshot.restoreIfNeeded();
    if (!r.restored && r.reason) console.log(`[dong-sync] 未恢复快照：${r.reason}`);
  } catch (e) {
    console.error("[dong-sync] 快照恢复异常", String(e.message || e));
  }
  await initStore();
  // 启动时给每个用户做一次「对象→映射」自愈
  if (storage.configured()) {
    const usersDir = path.join(DATA_DIR, "users");
    const uids = await fsp.readdir(usersDir).catch(() => []);
    for (const uid of uids) {
      try { await storage.repairIndex(uid); } catch {}
    }
  }
})()
  .then(() => storage.selfCheck())
  .then((health) => {
    gatewayHealth = health;
    if (health.ok) {
      console.log(`[dong-sync] storage=${health.mode}` + (health.gateway ? ` gateway=${health.gateway}` : ""));
    } else {
      // 不直接退出：托管平台会不停重启，日志被刷屏反而看不出原因。
      // 需要「起不来就别起」的语义时设 DONG_GATEWAY_STRICT=1。
      console.error(`[dong-sync] 存储自检失败：${health.error}`);
      if (process.env.DONG_GATEWAY_STRICT === "1") process.exit(1);
    }
  })
  .catch((e) => console.error("[dong-sync] storage selfcheck error", e))
  .then(() => {
    server.listen(PORT, () => console.log(`[dong-sync] listening on :${PORT}`));
    snapshot.start();
  });

// 退出前尽量补一份，别把最后几分钟的改动丢掉
for (const sig of ["SIGTERM", "SIGINT"]) {
  process.on(sig, () => {
    snapshot.flush().finally(() => process.exit(0));
    setTimeout(() => process.exit(0), 5_000).unref();
  });
}
