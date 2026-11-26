"use strict";
// 给所有用户发「新版本已发布」的通知邮件。
//
// 发布时是可选项：官网后台勾上才发，不勾就只更新版本元数据。
// 三条安全线：
//   1. 同一个版本只发一次（记录在 data/notify-log.json，想重发要显式 force）
//   2. 每封带退订链接（HMAC 签名，不用登录），点了就永久跳过
//   3. 控制台模式只打日志不发信，方便先在本地空跑看内容

const crypto = require("node:crypto");
const mail = require("./mail");

/// 退订链接的签名：没有独立密钥时退回用管理员令牌派生，换令牌即全部失效（可以接受）
function unsubSecret() {
  return String(process.env.MAIL_UNSUB_SECRET || process.env.ADMIN_TOKEN || "dong-unsub");
}

function unsubToken(userId) {
  return crypto.createHmac("sha256", unsubSecret()).update(String(userId)).digest("hex").slice(0, 24);
}

function unsubUrl(baseUrl, userId) {
  const base = String(baseUrl || "").replace(/\/+$/, "");
  return `${base}/api/mail/unsubscribe?u=${encodeURIComponent(userId)}&t=${unsubToken(userId)}`;
}

/// 更新说明里的「· 一行一条」转成列表，其余当段落
function notesToHtml(notes) {
  const lines = String(notes || "").split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  if (!lines.length) return "";
  const bullets = [];
  const paras = [];
  for (const raw of lines) {
    const m = raw.match(/^[·•\-*]\s*(.+)$/) || raw.match(/^\d+[.、)]\s*(.+)$/);
    if (m) bullets.push(m[1]);
    else paras.push(raw);
  }
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  let html = paras.map((p) => `<p style="margin:0 0 10px">${esc(p)}</p>`).join("");
  if (bullets.length) {
    html += `<ul style="margin:6px 0 14px;padding-left:20px">` +
      bullets.map((b) => `<li style="margin:0 0 7px">${esc(b)}</li>`).join("") + `</ul>`;
  }
  return html;
}

function buildMail({ version, build, notes, downloadUrl, baseUrl, userId }) {
  const subject = `Dòng ${version} 已发布`;
  const body = notesToHtml(notes);
  const dl = downloadUrl || `${String(baseUrl || "").replace(/\/+$/, "")}/api/download?v=${version}&channel=stable`;
  const html = `
  <div style="margin:0;padding:26px 0;background:#f7f6f4">
    <div style="max-width:520px;margin:0 auto;padding:30px 30px 24px;background:#fff;border-radius:14px;
                font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Helvetica Neue',sans-serif;
                font-size:15px;line-height:1.75;color:#26262a">
      <div style="font-size:13px;letter-spacing:.08em;color:#b0aaa2;margin-bottom:10px">DÒNG · 新版本</div>
      <h1 style="margin:0 0 6px;font-size:21px;font-weight:600;letter-spacing:-.01em">
        Dòng ${version} 可以更新了
      </h1>
      <div style="font-size:13px;color:#8b857d;margin-bottom:18px">build ${build} · macOS 13+ · Apple Silicon</div>
      ${body || `<p style="margin:0 0 10px">这次更新修了一些问题，建议更新。</p>`}
      <a href="${dl}" style="display:inline-block;margin:6px 0 18px;padding:10px 20px;border-radius:9px;
         background:#e8944a;color:#fff;text-decoration:none;font-weight:600;font-size:14px">下载新版本</a>
      <div style="border-top:1px solid #eee;padding-top:14px;font-size:12px;color:#a09a92;line-height:1.7">
        你收到这封邮件，是因为你用这个邮箱注册了 Dòng。
        <a href="${unsubUrl(baseUrl, userId)}" style="color:#a09a92">不想再收到更新通知</a>
      </div>
    </div>
  </div>`;
  return { subject, html };
}

/**
 * 群发。调用方拿到 job 对象自行更新进度。
 * @param {object} opts
 * @param {Record<string,{id:string,emailOptOut?:boolean}>} opts.accounts
 * @param {string} opts.version
 * @param {number} opts.build
 * @param {string} opts.notes
 * @param {string} opts.baseUrl
 * @param {(state:{total:number,sent:number,failed:number,current?:string,done:boolean,errors:string[]})=>void} [opts.onProgress]
 * @param {()=>boolean} [opts.shouldStop]
 * @param {number} [opts.limit] 只处理前 N 个（试跑用）
 * @param {number} [opts.gapMs] 每封之间的间隔，默认 250ms，别把服务商打限流
 */
async function broadcast(opts) {
  const { accounts, version, build, notes, baseUrl, onProgress, shouldStop, limit, gapMs = 250 } = opts;
  const list = Object.entries(accounts || {})
    .filter(([, u]) => u && u.id && !u.emailOptOut)
    .slice(0, limit && limit > 0 ? limit : undefined);

  const state = { total: list.length, sent: 0, failed: 0, done: false, errors: [], current: "" };
  const report = () => { try { onProgress && onProgress({ ...state }); } catch { /* 别让回调把任务带崩 */ } };
  report();

  for (const [email, user] of list) {
    if (shouldStop && shouldStop()) { state.done = true; report(); return state; }
    state.current = email;
    const { subject, html } = buildMail({ version, build, notes, downloadUrl: opts.downloadUrl,
                                          baseUrl, userId: user.id });
    const r = await mail.send(email, subject, html);
    if (r.ok) state.sent += 1;
    else { state.failed += 1; state.errors.push(`${email}: ${r.error || "失败"}`); }
    report();
    if (gapMs > 0) await new Promise((res) => setTimeout(res, gapMs));
  }
  state.done = true;
  state.current = "";
  report();
  return state;
}

module.exports = { broadcast, buildMail, unsubUrl, unsubToken, notesToHtml };
