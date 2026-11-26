"use strict";
// 邮箱「能不能真收到信」的检查。
//
// 只校验格式是不够的：`asdf@asdf.com` 这种看着合法、实际永远收不到信的地址也能过。
// 这里做三件事：
//   1. 域名必须真的存在，并且有 MX 记录——乱打的域名、解析不了的域名一律拦掉
//   2. 一次性 / 临时邮箱域名黑名单
//   3. 常见拼写纠正提示（gmail.con → gmail.com），让用户少填错
//
// 注意：DNS 抖动不能把人挡在门外。只有「域名明确不存在 / 明确没有收信能力」才拒绝，
// 解析超时之类的临时错误一律放行（fail-open），否则我们的 DNS 一出问题就没人能注册。

const dns = require("node:dns").promises;

/// 公开的一次性 / 临时邮箱（够用即可，不做全量；命中就拒绝）
const DISPOSABLE = new Set([
  "mailinator.com", "mailinator.net", "mailinator2.com", "yopmail.com", "yopmail.fr",
  "guerrillamail.com", "guerrillamail.net", "guerrillamail.org", "sharklasers.com",
  "grr.la", "10minutemail.com", "10minutemail.net", "temp-mail.org", "temp-mail.io",
  "tempmail.com", "tempmail.net", "tempail.com", "throwawaymail.com", "trashmail.com",
  "trashmail.net", "getnada.com", "nada.email", "dispostable.com", "discard.email",
  "maildrop.cc", "mailnesia.com", "mintemail.com", "spamgourmet.com", "mohmal.com",
  "emailondeck.com", "fakeinbox.com", "mytemp.email", "burnermail.io", "mail.tm",
  "inboxkitten.com", "mailcatch.com", "spambox.us", "tempr.email", "cock.li",
  "anonaddy.me", "simplelogin.com", "relay.firefox.com",
]);

/// 常见手误（只提示，不自动改，免得改错别人的地址）
const TYPOS = {
  "gmail.con": "gmail.com", "gmail.co": "gmail.com", "gmail.cm": "gmail.com",
  "gmial.com": "gmail.com", "gmai.com": "gmail.com", "gmail.com.cn": "gmail.com",
  "qq.con": "qq.com", "qq.co": "qq.com", "q q.com": "qq.com",
  "163.con": "163.com", "126.con": "126.com", "yeah.con": "yeah.net",
  "outlook.con": "outlook.com", "hotmail.con": "hotmail.com", "hotmai.com": "hotmail.com",
  "icloud.con": "icloud.com", "icloud.co": "icloud.com", "yahoo.con": "yahoo.com",
  "foxmail.con": "foxmail.com", "sina.con": "sina.com", "sohu.con": "sohu.com",
};

/// 明确没有收信能力的域名（占位 / 测试域名）
const NO_MAIL = new Set([
  "example.com", "example.org", "example.net", "test.com", "test",
  "localhost", "invalid", "local",
]);

const cache = new Map(); // domain -> { ok, reason, at }
const TTL = 3600_000;

function normalize(email) {
  return String(email || "").trim().toLowerCase();
}

function domainOf(email) {
  const i = email.lastIndexOf("@");
  return i < 0 ? "" : email.slice(i + 1).replace(/\.$/, "");
}

async function resolveDomain(domain) {
  const now = Date.now();
  const hit = cache.get(domain);
  if (hit && now - hit.at < TTL) return hit;

  let out;
  try {
    const mx = await dns.resolveMx(domain);
    // 必须有 MX。**不要**退一步看 A 记录：asdf.com 这种域名 A 记录有、MX 是坏的，
    // 放过去就正好放过「乱打一个像域名的东西」——真实邮箱服务一定有 MX。
    out = mx && mx.length
      ? { ok: true, at: now }
      : { ok: false, reason: "no_mx", at: now };
  } catch (e) {
    const code = e && e.code;
    if (code === "ETIMEOUT" || code === "ECONNREFUSED" || code === "EAI_AGAIN") {
      // 我们自己的解析器出问题：宁可放行，别因为一次抖动把所有人挡在门外
      out = { ok: true, reason: "dns_unavailable", at: now };
    } else {
      // ENOTFOUND / ENODATA / NXDOMAIN / ESERVFAIL：这个域名没有可用的收信配置
      out = { ok: false, reason: "no_mail_record", at: now };
    }
  }
  cache.set(domain, out);
  return out;
}

/**
 * @returns {{ok:boolean, message?:string, hint?:string, reason?:string}}
 */
async function check(email) {
  const addr = normalize(email);
  const domain = domainOf(addr);
  if (!domain || domain.includes("..") || !domain.includes(".")) {
    return { ok: false, reason: "bad_domain", message: "邮箱格式不对" };
  }
  if (/^\d+\.\d+\.\d+\.\d+$/.test(domain) || domain.startsWith("[")) {
    return { ok: false, reason: "ip_domain", message: "邮箱格式不对" };
  }
  if (NO_MAIL.has(domain)) {
    return { ok: false, reason: "no_mail", message: "这个邮箱域名收不到信，换一个常用的邮箱" };
  }
  if (DISPOSABLE.has(domain)) {
    return { ok: false, reason: "disposable", message: "不支持临时邮箱，请用常用邮箱注册" };
  }
  const typo = TYPOS[domain];
  if (typo) {
    return { ok: false, reason: "typo", message: `邮箱域名好像打错了，是不是 @${typo}？` };
  }
  const r = await resolveDomain(domain);
  if (!r.ok) {
    return {
      ok: false,
      reason: r.reason,
      message: "这个邮箱域名收不到信，检查一下有没有打错，或者换一个常用的邮箱",
    };
  }
  return { ok: true, reason: r.reason || "mx" };
}

module.exports = { check, normalize, domainOf, DISPOSABLE, TYPOS };
