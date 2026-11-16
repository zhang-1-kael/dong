import Foundation
import AppKit
import WebKit
import AVFoundation

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

    /// 从详情接口里解析出的一条可下载素材
    private struct Media {
        let title: String
        let urls: [String]      // 候选直链，按优先级排列（play_addr > bitrate > download_addr）
        let isLivePhoto: Bool   // 是否来自实况图（image_post_info）
    }

    private let handlerName = "__vwDetail"
    private let probeName = "__vwProbe"
    private let ssrName = "__vwSSR"
    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var captured: Media?
    private var cookieHeader = ""
    private var onStage: ((String) -> Void)?
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
                let media = try Self.awaitOnMain(timeout: index == 0 ? 45 : 30) { done in
                    self.loadAndCapture(p, completion: done)
                }
                guard !media.urls.isEmpty else {
                    throw Failure(message: "这条内容没有可下载的视频：如果是纯图片笔记（没有实况动画），请换一条视频。")
                }
                // 只有真拿到直链才提示「正在下载」，抛错路径不闪误导性提示
                DispatchQueue.main.async {
                    onStage?(media.isLivePhoto ? "正在下载实况视频…" : "正在下载视频…")
                }
                Self.diag("第 \(index + 1) 轮截获详情，\(media.urls.count) 条候选直链，开始下载")
                let result = try download(media, into: dir)
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
        // 2026-11-16 防抓错：严格校验 aweme_id 后，纯图文笔记（静态图 + BGM，
        // 没有视频画面）根本不会有可用的详情直链。SSR 页面里有封面大图却始终
        // 没抓到带画面的视频 → 明确告诉用户「这条做不成动态壁纸」，绝不再退而
        // 抓 related 推荐流里别人的视频（旧版会把「天使壁纸」下载成「紫黑礼服」）。
        let hasCover = ssrCandidates.contains { $0.kind == "image" && max($0.w, $0.h) > 400 }
        if hasCover {
            Self.diag("判定为纯图文笔记（SSR 有封面大图、无动态详情），拒绝抓推荐流冒充")
            throw Failure(message: "这条是纯图文笔记（只有静态图片和背景音乐，没有动态画面），"
                + "做不成动态壁纸。请换成会动的视频，或点开几秒会自动播放的实况图再复制分享。")
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
          window.__vwProbeT0 = Date.now();
          window.__vwHB = setInterval(function () {
            try {
              window.webkit.messageHandlers.__vwProbe.postMessage(
                JSON.stringify({ u: location.href, t: document.title || '' }));
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

        // 无边框、屏幕外的隐藏窗口：不打扰用户，但 WKWebView 仍会正常执行 JS
        let win = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 1200, height: 800),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.alphaValue = 0
        win.contentView = wv
        win.orderFront(nil)
        self.hostWindow = win

        // 把 completion 存起来，收到合法详情后由 messageHandler 触发
        self.pendingCompletion = completion
        guard let url = URL(string: link) else {
            completion(Media(title: "", urls: [], isLivePhoto: false))
            return
        }
        wv.load(URLRequest(url: url, timeoutInterval: 30))
    }

    private var pendingCompletion: ((Media) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // 换形态重试时，上一轮 webView 可能有迟到的消息；只认当前这一个
        guard message.webView === webView else { return }

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
              !media.urls.isEmpty else { return }

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
            done(Media(title: "", urls: [], isLivePhoto: false))
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
        webView = nil
        hostWindow = nil
        pendingCompletion = nil

        let work = {
            wv?.configuration.userContentController.removeScriptMessageHandler(forName: name)
            wv?.configuration.userContentController.removeScriptMessageHandler(forName: probe)
            wv?.configuration.userContentController.removeScriptMessageHandler(forName: ssr)
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

        if let video = detail["video"] as? [String: Any] {
            collect(video, into: &urls)
        }
        // 实况图的图片列表在不同版本里可能挂在不同字段，两个都试：
        // 老版 aweme_detail.images[]，新版 aweme_detail.image_post_info.images[]
        func harvestImages(_ images: [[String: Any]]) {
            for image in images {
                // 实况图：只有带 video 字段的那几张才有几秒的 MP4
                if let video = image["video"] as? [String: Any] {
                    let before = urls.count
                    collect(video, into: &urls)
                    if urls.count > before { isLive = true }
                }
            }
        }
        if let direct = detail["images"] as? [[String: Any]] { harvestImages(direct) }
        if let info = detail["image_post_info"] as? [String: Any],
           let nested = info["images"] as? [[String: Any]] { harvestImages(nested) }

        // 同一条直链可能在多个字段里重复出现，去重但保序
        var seen = Set<String>()
        urls = urls.filter { seen.insert($0).inserted }
        return Media(title: title, urls: urls, isLivePhoto: isLive)
    }

    private static func collect(_ video: [String: Any], into urls: inout [String]) {
        func add(_ addr: Any?) {
            guard let a = addr as? [String: Any], let list = a["url_list"] as? [String] else { return }
            urls.append(contentsOf: list.filter { $0.hasPrefix("http") })
        }
        add(video["play_addr"])
        if let bitrates = video["bitrate_info"] as? [[String: Any]] {
            for b in bitrates { add(b["play_addr"]) }
        }
        add(video["download_addr"])
        add(video["play_addr_h264"])
    }

    // MARK: - 下载直链

    private func download(_ media: Media, into dir: URL) throws -> URL {
        guard !media.urls.isEmpty else {
            throw Failure(message: "这条内容没有可下载的视频：如果是纯图片笔记（没有实况动画），请换一条视频。")
        }
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        let name = Self.safeFileName(media.title)
        let dest = dir.appendingPathComponent(name + ".mp4")
        return try Self.downloadVideo(from: media.urls, ua: ua, cookie: cookieHeader,
                                      into: dir, dest: dest)
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
    private static func awaitOnMain<T>(timeout: TimeInterval,
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

        if Thread.isMainThread {
            setup(finish)
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                lock.lock(); let done = finished; lock.unlock()
                if done { break }
            }
        } else {
            DispatchQueue.main.async { setup(finish) }
            _ = sem.wait(timeout: .now() + timeout)
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
