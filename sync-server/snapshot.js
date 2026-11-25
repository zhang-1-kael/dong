/**
 * 快照 + 恢复（B 方案）。
 *
 * 背景：托管平台的 /tmp 会被定期清理，而账号、令牌、清单、assetId→key 映射都是本地 JSON。
 * 壁纸本体在对象存储里不会丢，但这些小 JSON 一丢，用户就「登录不上、壁纸也找不回来」。
 *
 * 做法：
 *   - 把 DATA_DIR 里的**记账文件**（不含壁纸本体）打成一份 gzip JSON，推到网关的
 *     `sync-snapshots/` 命名空间，保留最近 N 份
 *   - 启动时如果发现本地没有 accounts.json，就把最近一份快照拉回来解包
 *   - 写操作只标 dirty，定时器每 N 分钟检查一次，避免频繁打包上传
 *
 * 敏感数据：快照里有密码 hash 和登录令牌。**只走内部鉴权通道，不打日志、不进错误信息。**
 */
"use strict";

const fsp = require("node:fs/promises");
const path = require("node:path");
const zlib = require("node:zlib");
const storage = require("./storage");

const PREFIX = "sync-snapshots/";
const SNAPSHOT_ENDPOINT = "/api/sync-storage/snapshot";

const INTERVAL_MIN = Number(process.env.DONG_SNAPSHOT_INTERVAL_MIN || 10);
const KEEP = Number(process.env.DONG_SNAPSHOT_KEEP || 12);
const ENABLED = (() => {
  const v = process.env.DONG_SNAPSHOT;
  if (v === "0") return false;
  if (v === "1") return true;
  return storage.configured();     // 默认只在 gateway 模式下开
})();
const STRICT = process.env.DONG_GATEWAY_STRICT === "1";

let dataDir = ".";
let dirty = false;
let timer = null;
let lastResult = { at: 0, ok: null, key: "", error: "" };

function init(dir) {
  dataDir = dir;
}

function status() {
  return {
    enabled: ENABLED,
    intervalMin: INTERVAL_MIN,
    keep: KEEP,
    dirty,
    last: lastResult,
  };
}

// ── 打包 / 解包 ────────────────────────────────────────────

/** 只收记账文件：任何 assets/ 目录（壁纸本体）和 locks 都跳过 */
async function collectFiles(root, rel = "") {
  const out = [];
  const dir = path.join(root, rel);
  let entries = [];
  try {
    entries = await fsp.readdir(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const r = rel ? path.posix.join(rel, e.name) : e.name;
    if (e.isDirectory()) {
      if (e.name === "assets" || e.name === "locks") continue;
      out.push(...(await collectFiles(root, r)));
    } else if (e.isFile()) {
      out.push(r);
    }
  }
  return out;
}

async function pack() {
  const files = {};
  const list = await collectFiles(dataDir);
  let total = 0;
  for (const rel of list) {
    try {
      const buf = await fsp.readFile(path.join(dataDir, rel));
      files[rel] = buf.toString("base64");
      total += buf.length;
    } catch {}
  }
  const payload = JSON.stringify({ v: 1, at: Date.now(), files });
  return { gzip: zlib.gzipSync(Buffer.from(payload)), fileCount: list.length, rawBytes: total };
}

async function unpack(buf) {
  const parsed = JSON.parse(zlib.gunzipSync(buf).toString("utf8"));
  const files = parsed.files || {};
  let n = 0;
  for (const [rel, b64] of Object.entries(files)) {
    const dest = path.join(dataDir, rel);
    await fsp.mkdir(path.dirname(dest), { recursive: true });
    await fsp.writeFile(dest, Buffer.from(b64, "base64"));
    n += 1;
  }
  return n;
}

// ── 推送 / 列举 / 恢复 ─────────────────────────────────────

function keyName(at = Date.now()) {
  return `${PREFIX}${at}.json.gz`;
}

async function push(force = false) {
  if (!ENABLED) return { ok: false, error: "未启用" };
  if (!force && !dirty) return { ok: true, skipped: true };
  try {
    const { gzip, fileCount, rawBytes } = await pack();
    if (fileCount === 0) return { ok: true, skipped: true };   // 空数据不推，免得覆盖可用快照
    const key = keyName();
    const r = await storage.gwPutBuffer(SNAPSHOT_ENDPOINT, { key }, gzip);
    // 网关可能改写 key（追加后缀），以返回值为准
    const realKey = (r.body && r.body.key) || key;
    if (r.status !== 200) throw new Error(`网关返回 ${r.status}`);
    dirty = false;
    lastResult = { at: Date.now(), ok: true, key: realKey, error: "" };
    console.log(`[dong-sync] 快照已推送 ${fileCount} 个文件 / ${rawBytes}B → ${realKey}`);
    await prune(realKey);
    return { ok: true, key: realKey };
  } catch (e) {
    lastResult = { at: Date.now(), ok: false, key: "", error: String(e.message || e) };
    console.error(`[dong-sync] 快照失败：${lastResult.error}`);
    return { ok: false, error: lastResult.error };
  }
}

async function list() {
  const r = await storage.gwJSON("GET", "/api/sync-storage/list", { prefix: PREFIX });
  if (r.status !== 200) return [];
  return (r.body.keys || []).filter((k) => k.startsWith(PREFIX)).sort();
}

async function prune(keepKey) {
  const keys = await list();
  if (keys.length <= KEEP) return;
  for (const k of keys.slice(0, keys.length - KEEP)) {
    await storage.gwJSON("DELETE", "/api/sync-storage/object", { key: k });
  }
}

async function latestKey() {
  const keys = await list();
  return keys.length ? keys[keys.length - 1] : null;
}

async function fetchSnapshot(key) {
  const r = await storage.gwJSON("GET", "/api/sync-storage/url", { key });
  if (r.status !== 200 || !r.body.url) return null;
  return storage.fetchURL(r.body.url);
}

/**
 * 启动时调用：本地缺 accounts.json 才恢复，避免把「用户刚改过的数据」用过时快照盖掉。
 * 返回 { restored, files } 或 { restored: false, reason }
 */
async function restoreIfNeeded() {
  if (!ENABLED) return { restored: false, reason: "未启用" };
  const accountsFile = path.join(dataDir, "accounts.json");
  const exists = await fsp.access(accountsFile).then(() => true).catch(() => false);
  if (exists) return { restored: false, reason: "本地已有数据" };

  const key = await latestKey().catch(() => null);
  if (!key) return { restored: false, reason: "云端没有快照" };

  const buf = await fetchSnapshot(key);
  if (!buf) {
    const msg = "快照下载失败";
    console.error(`[dong-sync] ${msg}（${key}）`);
    if (STRICT) process.exit(1);
    return { restored: false, reason: msg };
  }
  try {
    const n = await unpack(buf);
    console.log(`[dong-sync] 已从快照恢复 ${n} 个文件（${key}）`);
    return { restored: true, files: n, key };
  } catch (e) {
    const msg = `快照解包失败：${String(e.message || e)}`;
    console.error(`[dong-sync] ${msg}`);
    if (STRICT) process.exit(1);
    return { restored: false, reason: msg };
  }
}

// ── 调度 ───────────────────────────────────────────────────

/** 写操作后调用：只标脏，真正上传交给定时器 */
function markDirty() {
  dirty = true;
}

/**
 * 「重要写操作」用：标脏后 3 秒内立刻补一份。
 * 典型场景是注册——刚建好的账号如果落在「定时器还没到」的窗口里被清盘，就白注册了。
 */
let soonTimer = null;
function markDirtySoon() {
  dirty = true;
  if (soonTimer) return;
  soonTimer = setTimeout(() => {
    soonTimer = null;
    push().catch(() => {});
  }, 3000);
  soonTimer.unref?.();
}

function start() {
  if (!ENABLED) return;
  if (timer) return;
  // 启动后先补一份：如果本地有数据但云端没快照，别等下一次崩溃才想起来
  setTimeout(() => { push(true).catch(() => {}); }, 30_000);
  timer = setInterval(() => { push().catch(() => {}); }, INTERVAL_MIN * 60_000);
  timer.unref?.();
  console.log(`[dong-sync] 快照已启用：每 ${INTERVAL_MIN} 分钟 / 保留 ${KEEP} 份`);
}

async function flush() {
  if (!ENABLED) return;
  await push(false).catch(() => {});
}

module.exports = { init, start, markDirty, markDirtySoon, flush, push, status, restoreIfNeeded, list, KEEP };
