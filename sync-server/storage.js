/**
 * 壁纸文件的存储层。
 *
 * 两种模式，由 DONG_STORAGE 切换：
 *   disk    —— 落到 DATA_DIR/users/<uid>/assets/<id>.bin（联调期用）
 *   gateway —— 走官网侧的内部存储网关 /api/sync-storage/*，文件进平台对象存储
 *
 * 为什么要抽象：官网那个托管平台的磁盘会被定期清理，正式环境必须把壁纸放进对象存储；
 * 但联调期没有网关凭证，先用磁盘跑通。**接口契约两种模式完全一致**，上层 server.js 不用关心。
 *
 * gateway 模式的内部凭证只从环境变量 SYNC_INTERNAL_TOKEN 读，仓库里不存任何 token。
 */
"use strict";

const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const http = require("node:http");
const https = require("node:https");

let DATA_DIR = ".";
let MAX_ASSET = 512 * 1024 * 1024;

const MODE = (process.env.DONG_STORAGE || "disk").toLowerCase();
const GW_BASE = (process.env.SYNC_GATEWAY_BASE || "https://dongisgood.coze.site").replace(/\/+$/, "");
const GW_TOKEN = process.env.SYNC_INTERNAL_TOKEN || "";
// 下载默认 302 给 App，让它直连对象存储；改成 pipe 则由本进程转发（多占一份带宽）
const GW_DOWNLOAD = (process.env.DONG_GATEWAY_DOWNLOAD || "redirect").toLowerCase();

function init(dataDir, opts = {}) {
  DATA_DIR = dataDir;
  if (opts.maxAsset) MAX_ASSET = opts.maxAsset;
}

const mode = () => MODE;
const configured = () => MODE === "gateway";

function userDir(uid) {
  return path.join(DATA_DIR, "users", uid);
}
function assetFile(uid, aid) {
  return path.join(userDir(uid), "assets", aid + ".bin");
}
function mapFile(uid) {
  return path.join(userDir(uid), "assets.json");
}

async function readMap(uid) {
  try {
    return JSON.parse(await fsp.readFile(mapFile(uid), "utf8"));
  } catch {
    return {};
  }
}

async function writeMap(uid, map) {
  const f = mapFile(uid);
  await fsp.mkdir(path.dirname(f), { recursive: true });
  const tmp = f + ".tmp";
  await fsp.writeFile(tmp, JSON.stringify(map));
  await fsp.rename(tmp, f);
}

// ── 网关调用 ────────────────────────────────────────────────

function gwURL(p, query) {
  const u = new URL(GW_BASE + p);
  for (const [k, v] of Object.entries(query || {})) u.searchParams.set(k, v);
  return u;
}

function gwHeaders(extra = {}) {
  return {
    "x-sync-internal": GW_TOKEN,
    ...extra,
  };
}

/** 小请求（list / url / delete），把响应读成 JSON */
function gwJSON(method, p, query) {
  return new Promise((resolve) => {
    const u = gwURL(p, query);
    const lib = u.protocol === "http:" ? http : https;
    const req = lib.request(
      { method, hostname: u.hostname, port: u.port, path: u.pathname + u.search,
        headers: gwHeaders(), timeout: 30_000 },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let body = {};
          try { body = JSON.parse(text || "{}"); } catch { body = { raw: text }; }
          resolve({ status: res.statusCode || 0, body });
        });
      }
    );
    req.on("timeout", () => req.destroy(new Error("gateway timeout")));
    req.on("error", (e) => resolve({ status: 0, body: { error: e.message } }));
    req.end();
  });
}

/** 上传：把入站请求直接管道到网关，边传边算 sha256，不落临时文件 */
function gwUpload(uid, aid, req) {
  return new Promise((resolve, reject) => {
    const u = gwURL("/api/sync-storage/upload", { userId: uid, assetId: aid });
    const lib = u.protocol === "http:" ? http : https;
    const hash = crypto.createHash("sha256");
    let bytes = 0;

    const out = lib.request(
      { method: "PUT", hostname: u.hostname, port: u.port, path: u.pathname + u.search,
        headers: gwHeaders({ "content-type": "application/octet-stream" }), timeout: 600_000 },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let body = {};
          try { body = JSON.parse(text || "{}"); } catch { body = {}; }
          if (res.statusCode !== 200 || !body.key) {
            reject(new Error(`gateway upload ${res.statusCode} ${text.slice(0, 160)}`));
            return;
          }
          resolve({ key: body.key, bytes, sha256: hash.digest("hex") });
        });
      }
    );

    out.on("timeout", () => out.destroy(new Error("gateway upload timeout")));
    out.on("error", reject);

    req.on("data", (c) => {
      bytes += c.length;
      if (bytes > MAX_ASSET) {
        req.destroy();
        out.destroy(new Error("too large"));
        return;
      }
      hash.update(c);
    });
    req.on("error", reject);
    req.pipe(out);
  });
}

// ── 对外接口 ────────────────────────────────────────────────

/** 存一个文件，返回 {bytes, sha256}。gateway 模式下同时把 assetId→key 记进 assets.json */
async function put(uid, aid, req) {
  if (MODE !== "gateway") {
    const file = assetFile(uid, aid);
    await fsp.mkdir(path.dirname(file), { recursive: true });
    const tmp = file + ".part";
    const hash = crypto.createHash("sha256");
    let bytes = 0;
    await new Promise((resolve, reject) => {
      const out = fs.createWriteStream(tmp);
      req.on("data", (c) => {
        bytes += c.length;
        if (bytes > MAX_ASSET) {
          req.destroy();
          reject(new Error("too large"));
          return;
        }
        hash.update(c);
      });
      req.pipe(out);
      out.on("finish", resolve);
      out.on("error", reject);
      req.on("error", reject);
    }).catch(async (e) => {
      await fsp.rm(tmp, { force: true });
      throw e;
    });
    await fsp.rename(tmp, file);
    return { bytes, sha256: hash.digest("hex") };
  }

  if (!GW_TOKEN) throw new Error("SYNC_INTERNAL_TOKEN 没配置，gateway 模式不可用");
  const map = await readMap(uid);
  const oldKey = map[aid];
  const r = await gwUpload(uid, aid, req);
  map[aid] = r.key;
  await writeMap(uid, map);
  // 网关每次上传都会追加新 UUID，同名覆盖会留下旧对象 → 主动回收，别白占配额
  if (oldKey && oldKey !== r.key) {
    await gwJSON("DELETE", "/api/sync-storage/object", { key: oldKey });
  }
  return { bytes: r.bytes, sha256: r.sha256 };
}

/** 取下载地址：disk 返回本地文件路径，gateway 返回签名直链 */
async function locate(uid, aid) {
  if (MODE !== "gateway") {
    const file = assetFile(uid, aid);
    try {
      const st = await fsp.stat(file);
      return { kind: "file", file, size: st.size };
    } catch {
      return null;
    }
  }
  const map = await readMap(uid);
  const key = map[aid];
  if (!key) return null;
  const r = await gwJSON("GET", "/api/sync-storage/url", { key });
  if (r.status !== 200 || !r.body.url) return null;
  return { kind: "url", url: r.body.url };
}

/** 删除一个对象（两处都删干净：文件/对象 + 映射） */
async function del(uid, aid) {
  if (MODE !== "gateway") {
    await fsp.rm(assetFile(uid, aid), { force: true });
    return;
  }
  const map = await readMap(uid);
  const key = map[aid];
  if (key) {
    await gwJSON("DELETE", "/api/sync-storage/object", { key });
    delete map[aid];
    await writeMap(uid, map);
  }
}

/** 该用户已占用的字节数。gateway 模式下用清单里的 bytes 汇总（网关 list 不返回大小） */
async function usedBytes(uid) {
  if (MODE !== "gateway") {
    let total = 0;
    let names = [];
    try {
      names = await fsp.readdir(path.join(userDir(uid), "assets"));
    } catch {
      return 0;
    }
    for (const n of names) {
      try {
        const st = await fsp.stat(path.join(userDir(uid), "assets", n));
        if (st.isFile()) total += st.size;
      } catch {}
    }
    return total;
  }
  try {
    const m = JSON.parse(await fsp.readFile(path.join(userDir(uid), "manifest.json"), "utf8"));
    return (m.items || [])
      .filter((i) => !i.deleted)
      .reduce((sum, i) => sum + (Number(i.bytes) || 0), 0);
  } catch {
    return 0;
  }
}

/**
 * 自愈：把网关里已有的对象重新挂回 assets.json。
 *
 * 网关的 key 形如 `sync/<uid>/<assetId>_<8位uuid>`，assetId 就在里面——
 * 所以哪怕 assets.json 被清掉（容器重建、快照丢了），对象还在就还能认回来。
 * 这是「壁纸找不到」的最后一道保险。
 */
async function repairIndex(uid) {
  if (MODE !== "gateway") return 0;
  const prefix = `sync/${uid}/`;
  const r = await gwJSON("GET", "/api/sync-storage/list", { prefix });
  if (r.status !== 200) return 0;
  const keys = r.body.keys || [];
  const map = await readMap(uid);
  const known = new Set(Object.values(map));
  let added = 0;
  for (const key of keys) {
    if (known.has(key)) continue;
    const rest = String(key).slice(prefix.length);
    const m = /^(.*)_([0-9a-f]{8})$/.exec(rest);
    const aid = m ? m[1] : rest;
    if (!aid || map[aid]) continue;
    map[aid] = key;
    known.add(key);
    added += 1;
  }
  if (added) {
    await writeMap(uid, map);
    console.log(`[dong-sync] 自愈：${uid} 挂回 ${added} 个对象`);
  }
  return added;
}

/** 启动自检：gateway 模式下确认凭证和连通性，别让服务「起来了但一上传就 401」 */
async function selfCheck() {
  if (MODE !== "gateway") return { ok: true, mode: MODE };
  if (!GW_TOKEN) {
    return { ok: false, mode: MODE, error: "SYNC_INTERNAL_TOKEN 未设置" };
  }
  const r = await gwJSON("GET", "/api/sync-storage/list", { prefix: "sync/selfcheck/" });
  if (r.status !== 200) {
    return { ok: false, mode: MODE, error: `网关返回 ${r.status} ${JSON.stringify(r.body).slice(0, 120)}` };
  }
  return { ok: true, mode: MODE, gateway: GW_BASE };
}

// ── 给快照模块用的底层能力 ──────────────────────────────────
// 快照要往网关推整包、还要列举/取回/删除，复用同一套鉴权和 base

/** PUT 一个 Buffer 到网关的任意内部路由 */
function gwPutBuffer(pathName, query, buffer) {
  return new Promise((resolve) => {
    const u = gwURL(pathName, query);
    const lib = u.protocol === "http:" ? http : https;
    const req = lib.request(
      { method: "PUT", hostname: u.hostname, port: u.port, path: u.pathname + u.search,
        headers: gwHeaders({ "content-type": "application/octet-stream",
                             "content-length": buffer.length }),
        timeout: 120_000 },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let body = {};
          try { body = JSON.parse(text || "{}"); } catch {}
          resolve({ status: res.statusCode || 0, body });
        });
      }
    );
    req.on("timeout", () => req.destroy(new Error("gateway timeout")));
    req.on("error", (e) => resolve({ status: 0, body: { error: e.message } }));
    req.end(buffer);
  });
}

/** 跟随签名直链把对象取回内存（只用于快照，体积很小） */
function fetchURL(url) {
  return new Promise((resolve) => {
    let u;
    try { u = new URL(url); } catch { resolve(null); return; }
    const lib = u.protocol === "http:" ? http : https;
    lib.get(u, (res) => {
      if (res.statusCode !== 200) { res.resume(); resolve(null); return; }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve(Buffer.concat(chunks)));
    }).on("error", () => resolve(null));
  });
}

module.exports = {
  init, put, locate, del, usedBytes, selfCheck,
  mode, configured, downloadMode: () => GW_DOWNLOAD,
  gwJSON, gwPutBuffer, fetchURL, repairIndex,
};
