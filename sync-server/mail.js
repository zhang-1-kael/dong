"use strict";
// 发信通道。零依赖：只用 Node 自带的 fetch（Node 18+）。
//
// 三种模式，靠环境变量切，代码不用改：
//   MAIL_PROVIDER=console   不真发，验证码打在服务端日志里（本地联调 / 未配置时）
//   MAIL_PROVIDER=resend    Resend  HTTP API（最省事，需要已验证的发信域名）
//   MAIL_PROVIDER=aliyun    阿里云邮件推送 DirectMail（国内送达率好，需要发信域名 + 密钥）
//
// 没配好就当「邮箱验证未开通」：注册接口仍然接受无验证码的请求，
// 但域名真实性检查（emailcheck.js）照常生效——这一步不需要任何凭据。

const crypto = require("node:crypto");

const PROVIDER = String(process.env.MAIL_PROVIDER || "").trim().toLowerCase();
const FROM = String(process.env.MAIL_FROM || "").trim();
const FROM_NAME = String(process.env.MAIL_FROM_NAME || "Dòng").trim();

const RESEND_KEY = String(process.env.MAIL_RESEND_KEY || "").trim();

const ALI_KEY_ID = String(process.env.MAIL_ALIYUN_KEY_ID || "").trim();
const ALI_KEY_SECRET = String(process.env.MAIL_ALIYUN_KEY_SECRET || "").trim();
const ALI_REGION = String(process.env.MAIL_ALIYUN_REGION || "cn-hangzhou").trim();
const ALI_TEMPLATE = String(process.env.MAIL_ALIYUN_TEMPLATE || "").trim();

function providerName() {
  if (PROVIDER === "console") return "console";
  if (PROVIDER === "resend") return RESEND_KEY && FROM ? "resend" : "off";
  if (PROVIDER === "aliyun") {
    return ALI_KEY_ID && ALI_KEY_SECRET && FROM && ALI_TEMPLATE ? "aliyun" : "off";
  }
  return "off";
}

function isConfigured() {
  return providerName() !== "off";
}

// ── 阿里云 RPC 签名（和官方 SDK 同一套算法，只是手写） ──────────
function pe(s) {
  return encodeURIComponent(s)
    .replace(/\+/g, "%20").replace(/\*/g, "%2A").replace(/%7E/g, "~")
    .replace(/!/g, "%21").replace(/'/g, "%27").replace(/\(/g, "%28").replace(/\)/g, "%29");
}

function aliyunSign(params, method = "POST") {
  const sorted = Object.keys(params).sort()
    .map((k) => `${pe(k)}=${pe(params[k])}`).join("&");
  const toSign = `${method}&${pe("/")}&${pe(sorted)}`;
  return crypto.createHmac("sha1", ALI_KEY_SECRET + "&").update(toSign).digest("base64");
}

async function sendViaAliyun(to, subject, html) {
  const params = {
    Action: "SingleSendMail",
    Version: "2015-11-23",
    Format: "JSON",
    AccessKeyId: ALI_KEY_ID,
    SignatureMethod: "HMAC-SHA1",
    SignatureVersion: "1.0",
    SignatureNonce: crypto.randomUUID(),
    Timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    RegionId: ALI_REGION,
    AccountName: FROM,
    AddressType: "1",
    ReplyToAddress: "false",
    ToAddress: to,
    Subject: subject,
    HtmlBody: html,
  };
  params.Signature = aliyunSign(params);
  const body = Object.keys(params)
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`).join("&");
  const r = await fetch("https://dm.aliyuncs.com/", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const text = await r.text();
  let j = {};
  try { j = JSON.parse(text); } catch { /* 保留原文 */ }
  if (!r.ok || (j.Code && j.Code !== "OK")) {
    throw new Error(`aliyun ${r.status} ${j.Code || ""} ${j.Message || text.slice(0, 120)}`);
  }
  return j;
}

async function sendViaResend(to, subject, html) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${RESEND_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_NAME ? `${FROM_NAME} <${FROM}>` : FROM,
      to: [to],
      subject,
      html,
    }),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`resend ${r.status} ${text.slice(0, 160)}`);
  return text;
}

function codeMail(code, purpose) {
  const why = purpose === "reset" ? "重设密码" : "注册";
  const subject = `Dòng 验证码：${code}`;
  const html = `
  <div style="font-family:-apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;font-size:15px;color:#222;line-height:1.7">
    <p>你正在${why} Dòng 账号，验证码是：</p>
    <p style="font-size:30px;font-weight:600;letter-spacing:6px;margin:18px 0">${code}</p>
    <p style="color:#666">10 分钟内有效。不是你操作的可以忽略这封邮件。</p>
  </div>`;
  return { subject, html };
}

/// 通用发信。验证码和「新版本通知」都走这里。
/// @returns {Promise<{ok:boolean, dev?:boolean, error?:string}>}
async function send(to, subject, html) {
  const p = providerName();
  if (p === "console") {
    console.log(`[mail] 模拟发送 → ${to}｜${subject}`);
    return { ok: true, dev: true };
  }
  if (p === "off") return { ok: false, error: "邮箱验证暂未开通" };
  try {
    if (p === "resend") await sendViaResend(to, subject, html);
    else await sendViaAliyun(to, subject, html);
    console.log(`[mail] 已发送 → ${to}｜${subject}`);
    return { ok: true };
  } catch (e) {
    console.error("[mail] 发送失败", String(e && e.message || e));
    return { ok: false, error: "发送失败，稍后再试" };
  }
}

/// @returns {Promise<{ok:boolean, dev?:boolean, error?:string}>}
async function sendCode(to, code, purpose = "register") {
  const { subject, html } = codeMail(code, purpose);
  return send(to, subject, html);
}

module.exports = { isConfigured, send, sendCode, providerName };
