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

const PORT = Number(process.env.SYNC_PORT || process.env.PORT || 8787);
const DATA_DIR = path.resolve(process.env.DATA_DIR || path.join(__dirname, "data"));
const QUOTA_BYTES = Number(process.env.DONG_QUOTA_GB || 2) * 1024 ** 3;
const MAX_ASSET = Number(process.env.DONG_MAX_ASSET_MB || 512) * 1024 ** 2;
const TOKEN_DAYS = Number(process.env.DONG_TOKEN_DAYS || 60);

// 简易限流：key = 客户端 IP，滑动窗口计数。托管平台没有 Nginx，只能自己兜一层。
// 注意反代场景必须用 X-Forwarded-For，否则所有请求都来自 127.0.0.1，会把所有人一起锁死。
const LIMITS = {
  register: { max: 5, windowMs: 60_000 },
  login: { max: 12, windowMs: 60_000 },
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
let gatewayHealth = { ok: true, mode: storage.mode() };

const F = {
  accounts: path.join(DATA_DIR, "accounts.json"),
  tokens: path.join(DATA_DIR, "tokens.json"),
  users: path.join(DATA_DIR, "users"),
};

// ── 极简持久化：内存一份 + 原子落盘 ─────────────────────────
let accounts = {}; // email -> { id, salt, hash, createdAt, quotaBytes }
let tokens = {};   // tokenHash -> { userId, expiresAt }

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

async function initStore() {
  await fsp.mkdir(F.users, { recursive: true });
  accounts = readJson(F.accounts, {});
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
  const entry = Object.values(accounts).find((a) => a.id === rec.userId);
  if (!entry) return null;
  return entry;
}

function issueToken(userId) {
  const raw = crypto.randomBytes(32).toString("hex");
  tokens[sha256(Buffer.from(raw))] = { userId, expiresAt: Date.now() + TOKEN_DAYS * 86400_000 };
  return raw;
}

function validEmail(s) {
  return typeof s === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) && s.length <= 160;
}

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
      ...(healthy ? {} : { error: gatewayHealth.error }),
    });
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

    const salt = crypto.randomBytes(16).toString("hex");
    const user = {
      id: crypto.randomUUID(),
      salt,
      hash: scrypt(password, salt),
      createdAt: Date.now(),
      quotaBytes: QUOTA_BYTES,
    };
    accounts[email] = user;
    await writeJson(F.accounts, accounts);
    await fsp.mkdir(assetDir(user.id), { recursive: true });

    const token = issueToken(user.id);
    await writeJson(F.tokens, tokens);
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

    const token = issueToken(user.id);
    await writeJson(F.tokens, tokens);
    return send(res, 200, { token, email, userId: user.id, quotaBytes: user.quotaBytes });
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
    }
    return send(res, 200, { ok: true });
  }

  if (p === "/api/me" && method === "GET") {
    const used = await usedBytes(user.id);
    const email = Object.keys(accounts).find((e) => accounts[e].id === user.id) || "";
    return send(res, 200, { email, userId: user.id, quotaBytes: user.quotaBytes, usedBytes: used });
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

initStore()
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
  });
