import Foundation
import AppKit
import WebKit
import AVFoundation
import UniformTypeIdentifiers

/// 抖音专用抓取器。
///
/// 为什么不用 yt-dlp：抖音 2026 年的 Argus 安全墙要求 `UIFID` 设备指纹 cookie，
/// 这个 cookie 只有抖音网页的 JS 真正跑起来才会生成；yt-dlp 自己不算签名
/// （源码里至今是 `TODO: Run verification challenge code`），所以无论借不借浏览器
/// cookie 都只会拿到 `Blocked by ArgusSecurityPlugin Uifid Not Found`。
///
/// 这里的做法：用系统自带的 WKWebView 打开抖音页面，让抖音自己的 JS 完成签名和请求，
/// 我们在旁边 hook 它发出的详情接口响应，把里面的视频 / 实况图直链取出来下载。
/// WKWebView 是 Safari 内核、指纹接近真实浏览器，比 headless Chrome 更不容易触发验证码。
final class DouyinWebFetcher: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    struct Failure: LocalizedError {
        let message: String
        /// 是不是「等页面等到超时」这一类：fetch() 会在这类失败上附加页面状态探针
        var isTimeout: Bool = false
        var errorDescription: String? { message }
    }

    /// 抓取过程的诊断日志。用户真机上出现过「harness 全绿、App 里却超时」的环境差异
    /// （2026-11-16：同链接 CLI 后台线程 9s 成功，App 两轮 45s 超时），
    /// 关键节点必须留痕，出问题才能从 Console / 终端回放定位。
    static func diag(_ s: @autoclosure () -> String) {
        NSLog("[VWDouyin] \(s())")
    }

    /// 下载图片用的浏览器 UA（download 视频那条也用同一串，集中在这里避免分叉）。
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                  + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// 从页面 URL 里推一个还行的壁纸名：note/<id> → 「抖音图文 <id>」。
    static func pageTitle(from link: String) -> String {
        if let id = awemeID(from: link) { return "抖音图文 \(id)" }
        return "抖音图文"
    }

    /// 从详情接口里解析出的一条可下载素材
    private struct Media {
        let title: String
        let urls: [String]      // 视频候选直链，按画质降序（高码率 > 默认档 > 带水印兜底）
        let isLivePhoto: Bool   // 是否来自实况图（image_post_info）
        // F5.6：纯图文笔记没有视频轨，但 images[].url_list 里有高清静态图（实测 2364×1774）。
        // 下载成图片交给下游 importStillImage 做成静态壁纸，不再拒绝这类内容。
        let stillImageURLs: [String]
    }

    /// 带画质分数的候选直链。用于把 bit_rate 档位里的高画质档排到默认档前面。
    private struct ScoredURL {
        let url: String
        let score: Double   // 画质分（像素数为主 + 码率/帧率微调），越大越优先
        let order: Int      // 同分时的稳定顺序
    }

    private let handlerName = "__vwDetail"
    private let probeName = "__vwProbe"
    private let ssrName = "__vwSSR"
    private let captchaName = "__vwCaptcha"
    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var captured: Media?
    private var cookieHeader = ""
    private var onStage: ((String) -> Void)?
    /// 本轮是否已经把验证窗口显示给用户：避免心跳每 3 秒重复弹提示。
    private var captchaShown = false
    /// 检测到验证页后，等待截止时间延长到这里（用户手动过滑块要时间）。
    private var captchaGraceUntil: Date?
    /// 页面心跳探针最近一次回报的状态：当前 URL + 页面标题。
    /// JS 被系统节流（App Nap / occlusion）时心跳会停——超时报错时靠它还原页面死在哪一步。
    private var pageState: (url: String, title: String)?
    /// 图文笔记没有详情接口时，从 SSR 页面 DOM 里捞到的素材直链（视频轨/静态图）。
    private var ssrCandidates: [(kind: String, w: Int, h: Int, url: String)] = []

    /// 同步抓取：返回下载好的本地文件。可在主线程或后台线程调用。
    func fetch(_ link: String, into dir: URL, ffmpeg: URL?,
               onStage: ((String) -> Void)?) throws -> URL {
        self.onStage = onStage
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // App 是 LSUIElement 菜单栏应用，主线程平时几乎空闲，抓取期间 macOS 可能
        // 对整个进程 App Nap，把 WKWebView 页面里的 JS 定时器冻住、详情接口发不出来。
        // 抓取期间显式声明「用户发起的活动」，禁止系统打盹。
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Dòng 正在抓取抖音视频")

        let page = Self.resolvePageURL(link)
        Self.diag("fetch 开始: \(link) → 页面 \(page)")
        DispatchQueue.main.async { onStage?("正在打开抖音页面…") }

        // 无论成功、超时还是抛错都要清理：断开 WKUserContentController → self 的强引用，
        // 同时保证 WKWebView 的所有视图操作都在主线程执行（见 cleanupWebView 注释）。
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            cleanupWebView()
        }

        // 同一条内容抖音可能以 /note/（图文、实况图）或 /video/ 呈现，两种页面
        // 返回的详情字段不同：note 页才有 image_post_info，video 页才有 play_addr。
        // 先用用户给的原形态；若抓到的直链全都没有画面（或压根没抓到），
        // 自动换同 ID 的相反形态再试一次，覆盖「短链跳到 video 但内容是实况图」。
        let pages = Self.pageVariants(page)
        var lastFailure: Error = Failure(message: "没找到可下载的视频。")

        // 超时放宽：真机实测抖音详情接口通常 7-10 秒返回，但慢网络 / 首次生成
        // uifid 指纹时可能拖到 30 秒以上；25 秒会把偶发慢响应误判成失败。
        for (index, p) in pages.enumerated() {
            do {
                Self.diag("第 \(index + 1) 轮加载 \(p)")
                let media = try Self.awaitOnMain(timeout: index == 0 ? 45 : 30,
                                                 graceUntil: { [weak self] in self?.captchaGraceUntil }) { done in
                    self.loadAndCapture(p, completion: done)
                }
                guard !media.urls.isEmpty || !media.stillImageURLs.isEmpty else {
                    throw Failure(message: "这条内容没有可下载的视频或图片，请换一条链接。")
                }
                Self.diag("第 \(index + 1) 轮截获详情：\(media.urls.count) 条视频候选、\(media.stillImageURLs.count) 张静态图")
                let result = try downloadMedia(media, into: dir)
                Self.diag("下载完成: \(result.lastPathComponent)")
                return result
            } catch {
                lastFailure = error
                Self.diag("第 \(index + 1) 轮失败: \(error.localizedDescription) 页面状态: \(pageState.map { "url=\($0.url) title=\($0.title)" } ?? "无心跳")")
                // 换形态前拆掉上一轮 webView（内部统一回主线程，后台线程调用也安全）
                cleanupWebView()
                if index == 0 && pages.count > 1 {
                    DispatchQueue.main.async { onStage?("换个页面形态再试一次…") }
                }
            }
        }
        // 超时类失败用探针还原页面卡在哪一步，给用户能看懂的线索
        if let f = lastFailure as? Failure, f.isTimeout, let state = pageState {
            var message = f.message
            let title = state.title
            if title.contains("验证") || title.lowercased().contains("verify") {
                message = "抖音要安全验证（页面标题「\(title)」），可能抓取太频繁了。"
                    + "请过几分钟再试一次；还不行就先在 Safari 打开 douyin.com 一次再回来贴链接。"
            } else if !title.isEmpty {
                message += "（页面卡在「\(title)」）"
            }
            throw Failure(message: message)
        }
        // F5.6：详情接口没抓到（图文 note 页常不发详情），但 SSR 页面里捞到了目标封面大图。
        // 旧版在这里拒绝，用户做不成壁纸；现在退而用封面图做静态壁纸。
        // 关键：仍严格只用 ssrCandidates（harvestSSR 只收 aweme_images / AWEME_DETAIL /
        // douyinpic 大图），绝不碰 related 推荐流——旧版会把「天使壁纸」下载成「紫黑礼服」。
        let covers = ssrCandidates.filter { $0.kind == "image" && max($0.w, $0.h) > 300 }
            .sorted { ($0.w * $0.h) > ($1.w * $1.h) }
        if let cover = covers.first {
            Self.diag("两轮都没抓到详情，改用 SSR 封面图（\(cover.w)×\(cover.h)）做静态壁纸")
            DispatchQueue.main.async { onStage?("正在下载图片…") }
            do {
                let result = try Self.downloadStillImage([cover.url], title: Self.pageTitle(from: page),
                                                         ua: Self.ua, cookie: cookieHeader, into: dir)
                Self.diag("SSR 封面图下载完成: \(result.lastPathComponent)")
                return result
            } catch {
                Self.diag("SSR 封面图下载失败: \(error.localizedDescription)")
                throw Failure(message: "这条是图片内容，但封面图下载失败了，请重试一次。")
            }
        }
        throw lastFailure
    }

    /// 从链接路径里抠出 19 位 aweme_id（不取 query，避免把 web_id 之类参数误认成视频 ID）。
    static func awemeID(from link: String) -> String? {
        guard let c = URLComponents(string: link),
              let r = c.path.range(of: #"\d{19}"#, options: .regularExpression) else { return nil }
        return String(c.path[r])
    }

    /// 原页面优先，再补一个同 aweme_id 的相反形态（note ↔ video）。
    static func pageVariants(_ page: String) -> [String] {
        guard var c = URLComponents(string: page),
              let host = c.host?.lowercased(), host.contains("douyin.com"),
              let id = awemeID(from: page) else {
            return [page]
        }
        let isNote = c.path.contains("/note/")
        c.path = (isNote ? "/video/" : "/note/") + id
        c.query = nil
        c.fragment = nil
        guard let alt = c.string, alt != page else { return [page] }
        return [page, alt]
    }

    /// 把抖音短链 / 移动分享页收敛成 WKWebView 能稳定截获详情接口的页面。
    /// - `www.douyin.com` 正链（含 `/note/`）**原样保留**：实况图数据就在 note 页，
    ///   改成 video 会拿到背景音乐音频流。
    /// - `v.douyin.com/xxx/` 短链：先跟随 302 拿最终地址，用抖音自己的跳转结果。
    /// - `iesdouyin.com/share/(note|video)/<id>/` 移动页：换成同形态的 PC 页。
    /// 任何一步失败都回退原链接（WKWebView 自己也会跟随 302），不会让入口变窄。
    static func resolvePageURL(_ link: String) -> String {
        guard let url = URL(string: link), let host = url.host?.lowercased() else { return link }
        let isShort = host == "v.douyin.com" || host.hasSuffix(".v.douyin.com")
        let isShare = host.contains("iesdouyin.com")
        guard isShort || isShare else { return link }

        var final = link
        if isShort {
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                         + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
            let sem = DispatchSemaphore(value: 0)
            var finalURL: URL?
            URLSession.shared.dataTask(with: req) { _, resp, _ in
                finalURL = resp?.url
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 12)
            if let resolved = finalURL?.absoluteString { final = resolved }
        }

        if let u = URL(string: final),
           u.host?.lowercased().contains("iesdouyin.com") == true,
           let r = u.path.range(of: #"\d{19}"#, options: .regularExpression) {
            let id = String(u.path[r])
            let kind = (u.path.contains("/note/") || u.path.contains("/slides/")) ? "note" : "video"
            return "https://www.douyin.com/\(kind)/\(id)"
        }
        return final
    }

    // MARK: - WKWebView 加载与拦截

    private func loadAndCapture(_ link: String, completion: @escaping (Media) -> Void) {
        captured = nil
        pageState = nil
        ssrCandidates = []

        let config = WKWebViewConfiguration()
        let cc = WKUserContentController()
        cc.add(self, name: handlerName)
        cc.add(self, name: probeName)
        cc.add(self, name: ssrName)
        cc.add(self, name: captchaName)
        captchaShown = false
        captchaGraceUntil = nil

        // 目标内容的 aweme_id：用于把「当前这条」和「推荐流里别人那条」严格区分开。
        // 2026-11-16 的真机事故：图文笔记（note 页）不发 aweme/detail 接口，
        // 旧的 grab() 拿不到 detail 就退而抓 aweme_list[0]——那是 related 推荐流的
        // 第一条（别人的视频），于是用户贴「天使壁纸」却下载成「紫黑礼服女孩」。
        // 现在：aweme_detail 必须字段齐全且 aweme_id 对得上才放行，其余一律不认。
        let wantedID = Self.awemeID(from: link) ?? ""
        // aweme_id 是纯数字，安全当 JS 字符串字面量用（非数字则退化成空，交给页面标题判定）
        let wantedJS = wantedID.range(of: #"^\d+$"#, options: .regularExpression) != nil
            ? "\"\(wantedID)\"" : "\"\""
        Self.diag("目标 aweme_id = \(wantedID.isEmpty ? "(无)" : wantedID)")

        // 这段脚本在页面任何 JS 之前运行，hook fetch 和 XHR，
        // 但只放行「响应 JSON 里确实带目标 aweme_id 的 aweme_detail」，
        // 避免把推荐流 / 无关请求的视频误当成目标内容。
        let js = """
        (function () {
          var WANTED = \(wantedJS);
          function matches(d) {
            if (!d || !(d.video || d.image_post_info || d.images)) return false;
            if (!WANTED) return true;
            var id = String(d.aweme_id || '');
            if (id === WANTED) return true;
            // 极少数详情接口会把 id 放在这些别名里，都认
            var alt = String(d.item_id || d.group_id || (d.stat && d.stat.aweme_id) || '');
            return alt === WANTED;
          }
          function grab(text, url) {
            if (!text || text.length < 200) return;
            var obj;
            try { obj = JSON.parse(text); } catch (e) { return; }
            // 只认真正的详情接口数据；绝不用 aweme_list[0]（那是推荐流，是别人的视频）
            var d = obj && obj.aweme_detail;
            if (!d && obj && obj.data && obj.data.aweme_detail) d = obj.data.aweme_detail;
            if (!matches(d)) return;
            try {
              window.webkit.messageHandlers.__vwDetail.postMessage(JSON.stringify({ url: url, detail: d }));
            } catch (e) {}
          }

          // 从 SSR 页面里直接捞目标内容的素材直链。
          // 图文笔记（/note/）不发详情接口，但页面 HTML 里嵌着 <img>/<video>，
          // 用 aweme_id 或页面标题能锁定目标这条，取其原图 / 封面作为静态壁纸兜底。
          function harvestSSR() {
            try {
              var out = [];
              var imgs = document.querySelectorAll('img');
              for (var i = 0; i < imgs.length && out.length < 12; i++) {
                var s = imgs[i].currentSrc || imgs[i].src || '';
                if (s.indexOf('aweme_images') >= 0 || s.indexOf('PackSourceEnum_AWEME_DETAIL') >= 0 ||
                    (s.indexOf('douyinpic.com') >= 0 && (imgs[i].naturalWidth||0) > 400)) {
                  out.push({ kind: 'image', w: imgs[i].naturalWidth||0, h: imgs[i].naturalHeight||0, url: s });
                }
              }
              var vids = document.querySelectorAll('video');
              for (var j = 0; j < vids.length && out.length < 20; j++) {
                var vs = vids[j].currentSrc || vids[j].src || '';
                if (vs.indexOf('http') === 0 && vs.indexOf('blob:') !== 0)
                  out.push({ kind: 'video', w: vids[j].videoWidth||0, h: vids[j].videoHeight||0, url: vs });
              }
              if (out.length) window.webkit.messageHandlers.__vwSSR.postMessage(JSON.stringify(out));
            } catch (e) {}
          }
          window.addEventListener('load', function () { setTimeout(harvestSSR, 4000); });
          // 页面加载完再补一发，有些 SSR 图片是懒加载插入的
          setTimeout(harvestSSR, 9000);

          var origFetch = window.fetch;
          window.fetch = function () {
            var args = arguments;
            var u = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) || '';
            return origFetch.apply(this, args).then(function (resp) {
              try { resp.clone().text().then(function (t) { grab(t, u); }).catch(function () {}); } catch (e) {}
              return resp;
            });
          };

          var origOpen = XMLHttpRequest.prototype.open;
          var origSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (m, u) {
            this.__vwUrl = u;
            return origOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function () {
            var self = this;
            this.addEventListener('load', function () {
              try { grab(self.responseText, self.__vwUrl || ''); } catch (e) {}
            });
            return origSend.apply(this, arguments);
          };

          // 心跳探针：每 3 秒回报当前 URL + 页面标题。
          // 原生层靠它区分「页面在慢加载」/「跳到验证页」/「JS 被系统节流冻住」，
          // 超时时把页面状态带回错误信息，不再只给一句笼统的「超时」。
          // 安全验证页检测：抖音对部分网络出口 IP 会弹滑块 / 短信验证，
          // 这种页面不发详情接口，抓取必然超时。过去窗口是全透明的，
          // 用户根本不知道发生了什么、也没法手动过验证。这里检测到就上报，
          // 让原生层把窗口显示出来交还给用户。
          function looksLikeCaptcha() {
            var u = (location.href || '').toLowerCase();
            var t = document.title || '';
            // URL 命中verify/captcha 基本可确定；title 则要求明确的验证字样，
            // 避免正常视频标题里恰好带个「验证」二字就误判。
            // 注意：抖音每个页面都会挂一个 rmc-nocaptcha（NoCaptcha=被动检测，
            // 不需要用户操作）的 iframe，绝不能把它当验证页，否则每条链接都误判。
            if (u.indexOf('/verify') >= 0 || u.indexOf('/captcha') >= 0) return true;
            if (t.indexOf('安全验证') >= 0 || t.indexOf('验证码') >= 0 ||
                t.indexOf('滑动验证') >= 0 || t.toLowerCase().indexOf('verify') >= 0) return true;
            // 只认真正需要用户手动滑/点的验证容器；排除 nocaptcha / 被动检测组件。
            var sels = ['#captcha_container', '.captcha-verify', '.captcha_verify',
                        '.slide-verify', '.geetest_slider', '.sm-slide-verify'];
            for (var i = 0; i < sels.length; i++) {
              try { if (document.querySelector(sels[i])) return true; } catch (e) {}
            }
            return false;
          }
          window.__vwProbeT0 = Date.now();
          window.__vwHB = setInterval(function () {
            try {
              window.webkit.messageHandlers.__vwProbe.postMessage(
                JSON.stringify({ u: location.href, t: document.title || '' }));
              if (!window.__vwCaptchaSent && looksLikeCaptcha()) {
                window.__vwCaptchaSent = true;
                window.webkit.messageHandlers.__vwCaptcha.postMessage(
                  JSON.stringify({ u: location.href, t: document.title || '' }));
              }
            } catch (e) {}
          }, 3000);
        })();
        """
        cc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController = cc

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        wv.navigationDelegate = self
        // 桌面版 UA：让抖音走 PC 页面，详情接口才会返回 play_addr
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView = wv

        // 平时是透明窗口，不打扰用户；一旦抖音弹安全验证，就把它显示到屏幕中央，
        // 让用户亲自过验证（滑块/短信）。所以窗口必须有标题栏、能成为 key window，
        // 否则用户看不到也点不了验证控件，只能干等到超时——这正是「我能过、别人过不了」
        // 的环境差异根源：别人的出口 IP 被要求验证，而我们这边没有。
        let win = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 1200, height: 800),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "Dòng · 抖音安全验证"
        win.alphaValue = 0
        win.contentView = wv
        win.orderFront(nil)
        self.hostWindow = win

        // 把 completion 存起来，收到合法详情后由 messageHandler 触发
        self.pendingCompletion = completion
        guard let url = URL(string: link) else {
            completion(Media(title: "", urls: [], isLivePhoto: false, stillImageURLs: []))
            return
        }
        wv.load(URLRequest(url: url, timeoutInterval: 30))
    }

    private var pendingCompletion: ((Media) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // 换形态重试时，上一轮 webView 可能有迟到的消息；只认当前这一个
        guard message.webView === webView else { return }

        // 抖音弹安全验证：把原来透明的窗口显示到屏幕中央，交还给用户手动过验证。
        // 所有 NSWindow / NSApp 操作必须在主线程（F5.1 崩溃教训），这里统一派发。
        if message.name == captchaName {
            guard !captchaShown else { return }
            captchaShown = true
            // 给用户 2 分钟过验证；过了这段时间还没过就按超时处理，不会无限等
            captchaGraceUntil = Date().addingTimeInterval(120)
            Self.diag("检测到安全验证页，显示窗口请用户手动验证（宽限 120s）")
            let win = hostWindow
            DispatchQueue.main.async { [weak self] in
                guard let win else { return }
                win.center()
                win.level = .floating
                win.alphaValue = 1
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self?.onStage?("抖音需要安全验证：请在弹出的窗口里完成验证，会自动继续…")
            }
            return
        }

        if message.name == ssrName {
            if let raw = message.body as? String,
               let data = raw.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let items = arr.compactMap { o -> (kind: String, w: Int, h: Int, url: String)? in
                    guard let k = o["kind"] as? String, let u = o["url"] as? String else { return nil }
                    return (k, o["w"] as? Int ?? 0, o["h"] as? Int ?? 0, u)
                }
                Self.diag("SSR 素材 \(items.count) 条: \(items.map { "\($0.kind)\($0.w)x\($0.h)" }.joined(separator: ", "))")
                self.ssrCandidates = items
            }
            return
        }

        if message.name == probeName {
            if let raw = message.body as? String,
               let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let u = obj["u"] as? String {
                let t = (obj["t"] as? String) ?? ""
                if pageState?.title != t || pageState?.url != u {
                    Self.diag("页面心跳: title=\(t.isEmpty ? "(空)" : t) url=\(u)")
                }
                pageState = (url: u, title: t)
            }
            return
        }

        guard message.name == handlerName,
              let raw = message.body as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = obj["detail"] as? [String: Any],
              let media = Self.parse(detail),
              (!media.urls.isEmpty || !media.stillImageURLs.isEmpty) else { return }

        // 留下页面此刻的 cookie，下载直链时要带 Referer + Cookie
        webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let pairs = cookies.filter { $0.domain.contains("douyin") || $0.domain.contains("snssdk") }
                .map { "\($0.name)=\($0.value)" }
            self?.cookieHeader = pairs.joined(separator: "; ")
            DispatchQueue.main.async {
                guard let self, let done = self.pendingCompletion else { return }
                self.pendingCompletion = nil
                self.captured = media
                done(media)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.diag("页面加载失败: \(error.localizedDescription)")
        finishEmpty()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Self.diag("页面预加载失败: \(error.localizedDescription)")
        finishEmpty()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Self.diag("页面加载完成: \(webView.url?.absoluteString ?? "?")")
    }

    private func finishEmpty() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let done = self.pendingCompletion else { return }
            self.pendingCompletion = nil
            done(Media(title: "", urls: [], isLivePhoto: false, stillImageURLs: []))
        }
    }

    /// WKWebView 的视图层级操作（removeFromSuperview / orderOut）必须在主线程。
    /// GUI 里 `importLink(_:background:)` 是在后台队列调 fetch 的，若在这里直接拆视图，
    /// WebKit 内部的 WKWindowVisibilityObserver 会触发 EXC_BREAKPOINT 把进程 trap 掉
    /// （2026-11-15 真机崩溃栈已确认）。所以统一派发回主线程。
    ///
    /// 这里刻意只捕获局部强引用的 wv/win/name，不捕获 self：
    /// fetch 结束后 self 可能已被释放，捕获局部对象能保证主线程 block 执行时
    /// 「断开 messageHandler → self 强引用」这一步一定发生，不会留下循环引用。
    private func cleanupWebView() {
        let wv = webView
        let win = hostWindow
        let name = handlerName
        let probe = probeName
        let ssr = ssrName
        let captcha = captchaName
        webView = nil
        hostWindow = nil
        pendingCompletion = nil

        let work = {
            wv?.configuration.userContentController.removeScriptMessageHandler(forName: name)
            wv?.configuration.userContentController.removeScriptMessageHandler(forName: probe)
            wv?.configuration.userContentController.removeScriptMessageHandler(forName: ssr)
            wv?.configuration.userContentController.removeScriptMessageHandler(forName: captcha)
            wv?.stopLoading()
            wv?.removeFromSuperview()
            win?.orderOut(nil)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    // MARK: - 解析详情 JSON

    private static func parse(_ detail: [String: Any]) -> Media? {
        let title = (detail["desc"] as? String ?? "抖音视频")
            .replacingOccurrences(of: "\n", with: " ")
        var urls: [String] = []
        var isLive = false
        var stills: [(url: String, pixels: Double, order: Int)] = []
        var stillSeq = 0

        if let video = detail["video"] as? [String: Any] {
            collect(video, into: &urls)
        }
        // 图片列表在不同版本里挂在不同字段，两个都试：
        // 老版 aweme_detail.images[]，新版 aweme_detail.image_post_info.images[]
        func harvestImages(_ images: [[String: Any]]) {
            for image in images {
                // 实况图：带 video 字段的那几张有几秒 MP4 —— 优先做成动态壁纸
                if let video = image["video"] as? [String: Any] {
                    let before = urls.count
                    collect(video, into: &urls)
                    if urls.count > before { isLive = true }
                }
                // F5.6 纯静态图：images[].url_list / download_url_list 是高清原图直链。
                // 没有视频轨时用它做静态壁纸。按 width×height 打分，挑最大那张。
                let w = (image["width"] as? NSNumber)?.doubleValue ?? 0
                let h = (image["height"] as? NSNumber)?.doubleValue ?? 0
                let pixels = w * h
                for key in ["url_list", "download_url_list"] {
                    guard let list = image[key] as? [String] else { continue }
                    for u in list where u.hasPrefix("http") {
                        stills.append((u, pixels, stillSeq)); stillSeq += 1
                    }
                }
            }
        }
        if let direct = detail["images"] as? [[String: Any]] { harvestImages(direct) }
        if let info = detail["image_post_info"] as? [String: Any],
           let nested = info["images"] as? [[String: Any]] { harvestImages(nested) }

        // 同一条直链可能在多个字段里重复出现，去重但保序
        var seen = Set<String>()
        urls = urls.filter { seen.insert($0).inserted }
        // 静态图按分辨率降序、去重。download_url_list 常带水印，排在 url_list 之后：
        // 同分辨率时靠「先 url_list 后 download」的原始顺序保证无水印优先。
        var seenStill = Set<String>()
        let stillURLs = stills
            .sorted { $0.pixels == $1.pixels ? $0.order < $1.order : $0.pixels > $1.pixels }
            .compactMap { seenStill.insert($0.url).inserted ? $0.url : nil }
        return Media(title: title, urls: urls, isLivePhoto: isLive, stillImageURLs: stillURLs)
    }

    private static func collect(_ video: [String: Any], into urls: inout [String]) {
        var cands: [ScoredURL] = []
        var seq = 0

        func num(_ v: Any?) -> Double {
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String { return Double(s) ?? 0 }
            return 0
        }
        func add(_ addr: Any?, score: Double) {
            guard let a = addr as? [String: Any], let list = a["url_list"] as? [String] else { return }
            for u in list where u.hasPrefix("http") {
                cands.append(ScoredURL(url: u, score: score, order: seq)); seq += 1
            }
        }

        // 默认档 play_addr：它自己的 width/height 才是真实下载分辨率，
        // video 顶层的 width/height 只是「源片标称值」（实测可能标称 3840×2160 但实际只给 1024×576），
        // 绝不能用标称值给它打分，否则会把低清流误排到第一。
        let defAddr = video["play_addr"] as? [String: Any]
        let dw = num(defAddr?["width"]), dh = num(defAddr?["height"])
        let defaultScore = (dw > 0 && dh > 0) ? dw * dh : -2

        // 真正的多档位列表是 bit_rate（不是 bitrate_info！字段名写错过一次，导致漏掉 4K 档）。
        // 每档的真实分辨率写在它自己的 play_addr.width/height 里，不是档位字典顶层。
        // 评分：以像素数为主；同分辨率再叠加码率做微弱的二级区分；再轻推 h264 以利兼容。
        if let bitrates = video["bit_rate"] as? [[String: Any]] {
            for b in bitrates {
                guard let pa = b["play_addr"] as? [String: Any] else { continue }
                let w = num(pa["width"]), h = num(pa["height"])
                let pixels = w * h
                let bitrate = num(b["bit_rate"])          // bps，例如 7174200
                let fps = num(b["FPS"])
                // 主分 = 像素数；码率换算到「等效像素」量级做次级区分（7M bps ≈ +0.7M 分）
                let score = pixels + bitrate / 10_000_000.0 * 1_000_000 + fps
                add(pa, score: score)
            }
        }
        // 默认档（play_addr / play_addr_h264）：按它自己的真实分辨率打分
        add(video["play_addr"], score: defaultScore)
        add(video["play_addr_h264"], score: defaultScore)
        // download_addr 通常带水印，永远垫底兜底
        add(video["download_addr"], score: -1)

        // 按画质分降序；同分保持原始顺序（稳定）。去重在 parse() 里做。
        let sorted = cands.sorted { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
        urls.append(contentsOf: sorted.map { $0.url })
        diag("collect 候选 \(sorted.count) 条，最高分 \(sorted.first?.score ?? 0)")
    }

    // MARK: - 下载直链

    /// F5.6：统一下载入口。优先视频/实况图；若 url_list 里全是音频（纯图文笔记的
    /// video.play_addr 其实指向背景音乐），downloadVideo 会失败，此时回退到
    /// images[].url_list 的高清静态图，做成静态壁纸——不再让纯图文笔记失败。
    private func downloadMedia(_ media: Media, into dir: URL) throws -> URL {
        if !media.urls.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onStage?(media.isLivePhoto ? "正在下载实况视频…" : "正在下载视频…")
            }
            do {
                return try download(media, into: dir)
            } catch {
                Self.diag("视频下载失败（\(error.localizedDescription)），尝试静态图兜底")
                if media.stillImageURLs.isEmpty { throw error }
            }
        }
        guard !media.stillImageURLs.isEmpty else {
            throw Failure(message: "这条内容没有可下载的视频或图片，请换一条链接。")
        }
        DispatchQueue.main.async { [weak self] in self?.onStage?("正在下载图片…") }
        Self.diag("改用 \(media.stillImageURLs.count) 张静态图做壁纸")
        return try Self.downloadStillImage(media.stillImageURLs, title: media.title,
                                           ua: Self.ua, cookie: cookieHeader, into: dir)
    }

    private func download(_ media: Media, into dir: URL) throws -> URL {
        guard !media.urls.isEmpty else {
            throw Failure(message: "这条内容没有可下载的视频：如果是纯图片笔记（没有实况动画），请换一条视频。")
        }
        let name = Self.safeFileName(media.title)
        let dest = dir.appendingPathComponent(name + ".mp4")
        return try Self.downloadVideo(from: media.urls, ua: Self.ua, cookie: cookieHeader,
                                      into: dir, dest: dest)
    }

    /// F5.6：把纯图文笔记的静态图下载成本地图片文件。
    /// 返回的文件名带 .webp 扩展名——下游 pumpImport 靠扩展名识别图片，
    /// 走 Transcoder.importStillImage 做成 2 秒静止壁纸（不会再当视频转码）。
    /// 逐个候选尝试：抖音的 url_list 也可能带签名过期的地址，取第一个成功且体积合理的。
    static func downloadStillImage(_ urls: [String], title: String, ua: String,
                                   cookie: String, into dir: URL) throws -> URL {
        var lastError = ""
        let fm = FileManager.default
        for (index, raw) in urls.enumerated() {
            guard let url = URL(string: raw) else { continue }
            var req = URLRequest(url: url)
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            req.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
            if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }

            let sem = DispatchSemaphore(value: 0)
            var gotData: Data?
            var gotResp: URLResponse?
            URLSession.shared.dataTask(with: req) { d, r, e in
                if let e { lastError = e.localizedDescription }
                gotData = d; gotResp = r; sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 45)

            let status = (gotResp as? HTTPURLResponse)?.statusCode ?? 0
            let size = gotData?.count ?? 0
            guard let bytes = gotData, status == 200, size > 3_000 else {
                lastError = "图片地址返回 \(status) / \(size) 字节"
                continue
            }
            // 必须能被 ImageIO 解码才算有效图片（排除错误页 HTML / 音频文件）
            guard let src = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let type = CGImageSourceGetType(src),
                  UTType(type as String)?.conforms(to: .image) == true else {
                lastError = "地址返回的不是有效图片"
                continue
            }
            let ext = imageExtension(for: type as String)
            let name = safeFileName(title)
            let dest = dir.appendingPathComponent("\(name).\(ext)")
            do {
                try? fm.removeItem(at: dest)
                try bytes.write(to: dest)
                diag("静态图下载成功: \(dest.lastPathComponent) \(bytes.count) 字节（候选 \(index + 1)）")
                return dest
            } catch {
                lastError = error.localizedDescription
            }
        }
        throw Failure(message: lastError.isEmpty ? "图片下载失败，请重试。" : "图片下载失败：\(lastError)")
    }

    /// 把 ImageIO 的 UTI 转成用作文件扩展名的字符串。
    private static func imageExtension(for uti: String) -> String {
        let u = uti.lowercased()
        if u.contains("jpeg") { return "jpg" }
        if u.contains("png") { return "png" }
        if u.contains("heic") { return "heic" }
        if u.contains("tiff") { return "tiff" }
        if u.contains("gif") { return "gif" }
        return "webp"   // 抖音 images[].url_list 默认就是 webp
    }

    /// 从候选直链里挑出第一个**真正带画面**的文件。
    /// 抖音详情接口的 url_list 会混入音频 CDN / 错误页（实测有一条返回 649KB 纯 MP3，
    /// 被当成 MP4 存下后 ffmpeg 找不到画面、整条导入失败），只看 HTTP 200 + 体积不够。
    /// 抽成 static 是为了能用本地 HTTP server 精确单测「跳过音频、选中真视频」。
    static func downloadVideo(from urls: [String], ua: String, cookie: String,
                              into dir: URL, dest: URL) throws -> URL {
        var lastError = ""
        var skipped = 0
        let fm = FileManager.default

        for (index, raw) in urls.enumerated() {
            guard let url = URL(string: raw) else { continue }
            var req = URLRequest(url: url)
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            req.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
            if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }

            do {
                // URLSession 回调本来就在后台队列，用独立信号量等待即可，无需主线程 RunLoop
                let sem = DispatchSemaphore(value: 0)
                var gotData: Data?
                var gotResp: URLResponse?
                URLSession.shared.dataTask(with: req) { d, r, e in
                    if let e { lastError = e.localizedDescription }
                    gotData = d
                    gotResp = r
                    sem.signal()
                }.resume()
                _ = sem.wait(timeout: .now() + 60)

                // 阈值放宽：实况图的短视频可能只有几十 KB，不能再靠体积判断是不是视频。
                guard let bytes = gotData, let http = gotResp as? HTTPURLResponse,
                      http.statusCode == 200, bytes.count > 8_000 else {
                    skipped += 1
                    continue
                }

                let probe = dir.appendingPathComponent("probe-\(index).mp4")
                try bytes.write(to: probe)
                defer { try? fm.removeItem(at: probe) }
                guard hasVideoTrack(probe) else {
                    skipped += 1
                    lastError = "抖音返回的直链没有画面，已跳过 \(skipped) 条音频/无效地址"
                    continue
                }
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: probe, to: dest)
                return dest
            } catch {
                lastError = error.localizedDescription
            }
        }
        // 所有直链都只有音频没有画面 = 纯图文笔记（图片配乐），本就做不成动态壁纸。
        // 给明确指引，别只丢一句技术化的「跳过 N 条音频」，用户看不懂也没法处置。
        if skipped > 0 {
            throw Failure(message: "这条是纯图文笔记（图片配背景音乐，画面本身不会动），"
                + "做不成动态壁纸。请换一条会动的视频，或点开几秒会自动播放的实况图再分享。")
        }
        throw Failure(message: lastError.isEmpty
            ? "拿到视频地址了，但下载失败，可能是链接已过期。"
            : "没找到带画面的视频：\(lastError)")
    }

    /// 文件里是否真的存在视频轨。纯音频 / 错误页会返回 false。
    static func hasVideoTrack(_ file: URL) -> Bool {
        let asset = AVURLAsset(url: file)
        return !asset.tracks(withMediaType: .video).isEmpty
    }

    private static func safeFileName(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:\"|<>*?\n\r")
        let cleaned = s.components(separatedBy: invalid).joined(separator: "_")
        return String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 同步等待异步回调（兼容主线程 / 后台线程）

    /// 在主线程执行 setup 并把回调里的结果同步等回来。
    /// 主线程调用时用 RunLoop 驱动，保证 WKWebView / URLSession 的主线程回调能执行；
    /// 后台线程调用时用信号量，避免阻塞主线程的 UI。
    private static func awaitOnMain<T>(timeout: TimeInterval, graceUntil: (() -> Date?)? = nil,
                                       _ setup: @escaping (@escaping (T) -> Void) -> Void) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: T?
        var finished = false

        let finish: (T) -> Void = { value in
            lock.lock()
            if !finished {
                finished = true
                result = value
                sem.signal()
            }
            lock.unlock()
        }
        // 有效截止时间 = 基础超时 与「验证宽限期」取较大者。
        // 用户手动过滑块可能要几十秒，检测到验证页后把 deadline 往后推。
        // 注意 base 必须在进入等待前固定一次；早先每次重算 base 导致 deadline
        // 永远比 now 晚 timeout，后台线程分段等待时会死循环卡住（F5.6 修复）。
        let base = Date().addingTimeInterval(timeout)
        func deadline() -> Date {
            if let grace = graceUntil?(), grace > base { return grace }
            return base
        }

        if Thread.isMainThread {
            setup(finish)
            while Date() < deadline() {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                lock.lock(); let done = finished; lock.unlock()
                if done { break }
            }
        } else {
            DispatchQueue.main.async { setup(finish) }
            // 分段等待：每 2 秒醒一次重算 deadline，好让验证宽限期生效
            while true {
                let remaining = deadline().timeIntervalSinceNow
                if remaining <= 0 { break }
                if sem.wait(timeout: .now() + min(remaining, 2)) == .success { break }
            }
        }

        lock.lock()
        let done = finished
        let value = result
        lock.unlock()
        guard done, let value else {
            throw Failure(message: "等待抖音页面响应超时，请重试；或把视频存本地拖进 Dòng。", isTimeout: true)
        }
        return value
    }
}
