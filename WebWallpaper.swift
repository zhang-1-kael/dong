import Foundation
import AppKit
import WebKit

// MARK: - 网页 / 流媒体壁纸（F15）
//
// 借鉴 Lively Wallpaper 的「URL 即壁纸源」：贴一个网页链接 → 不下载、不转码，
// 直接用 WKWebView 渲染成动态壁纸。YouTube / Shadertoy 自动转 embed 播放器
// （autoplay + mute + loop），普通网页原样加载。
//
// 数据层：streams.json 存 URL 清单（id / 名字 / 链接 / 加入时间）。
// 库里用虚拟 URL `dongweb://<id>` 表示一条网页壁纸 —— videos: [URL]、轮播、
// 删除、自动暂停这些既有结构全部复用，只在 rebuild 时按 scheme 分流。

struct WebStream: Codable {
    let id: String
    var name: String
    var url: String
    let addedAt: Date
}

enum WebStreams {

    /// 虚拟 scheme：库里一条网页壁纸
    static let scheme = "dongweb"

    static var file: URL {
        Source.support.appendingPathComponent("streams.json")
    }

    // MARK: 读写

    static func load() -> [WebStream] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let dec = JSONDecoder()
        // 编码侧用了 iso8601，解码必须对应——否则类型不匹配静默返回空，
        // 库里所有网页壁纸凭空消失（harness 实测踩中过）
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([WebStream].self, from: data)) ?? []
    }

    static func save(_ list: [WebStream]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(list) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    @discardableResult
    static func add(urlString: String) -> WebStream {
        var list = load()
        // 同一个链接重复添加只保留一条（按原文去重）
        if let exist = list.first(where: { $0.url == urlString }) { return exist }
        let item = WebStream(id: UUID().uuidString,
                             name: defaultName(for: urlString),
                             url: urlString,
                             addedAt: Date())
        list.append(item)
        save(list)
        return item
    }

    static func remove(id: String) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }

    // MARK: 名字

    /// 面板 / 库卡片显示的名字：优先用户可见名
    static func displayName(for url: URL) -> String? {
        guard let id = streamID(of: url) else { return nil }
        if let hit = load().first(where: { $0.id == id }) { return hit.name }
        return "网页壁纸"
    }

    private static func defaultName(for urlString: String) -> String {
        if let url = URL(string: urlString), let host = url.host {
            // youtube.com/watch?v=x → 「YouTube · x」这种一眼能认的短名
            if host.contains("shadertoy.com"), let last = url.pathComponents.last,
               last.count >= 4, last != "/" {
                return "Shadertoy · \(last)"
            }
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "网页壁纸"
    }

    // MARK: 虚拟 URL ↔ id

    static func virtualURL(_ id: String) -> URL {
        URL(string: "\(scheme)://\(id)")!
    }

    static func streamID(of url: URL) -> String? {
        guard url.scheme == scheme, let host = url.host, !host.isEmpty else { return nil }
        return host
    }

    /// 网页壁纸真正要加载的地址（embed 转换后的）
    static func targetURL(for url: URL) -> URL {
        guard let id = streamID(of: url),
              let item = load().first(where: { $0.id == id })
        else { return Source.singleFile } // 理论到不了：数据没了就当黑屏处理
        return WebEmbed.playerURL(for: item.url)
    }

    static func virtualURLs() -> [URL] {
        load().map { virtualURL($0.id) }
    }

    // MARK: 导入分流

    /// 已知视频站继续走「下载 + 转码」那条高画质链路；
    /// 其它链接（网页、Shadertoy、在线播放页）当网页壁纸。
    static func isWebCandidate(_ link: String) -> Bool {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(),
              url.scheme == "http" || url.scheme == "https"
        else { return false }
        let downloadSites = [
            "bilibili.com", "b23.tv",
            "douyin.com", "iesdouyin.com",
            "youtube.com", "youtu.be",
        ]
        return !downloadSites.contains { host == $0 || host.hasSuffix(".\($0)") || host.hasSuffix($0) }
    }
}

// MARK: - 播放页 embed 转换

enum WebEmbed {

    /// (要加载的 URL, 是否播放器页面)
    static func playerURL(for urlString: String) -> URL {
        let converted = convert(urlString)
        return URL(string: converted) ?? URL(string: "about:blank")!
    }

    /// 是否播放器页面（决定要不要注入「铺满裁切」样式）
    static func isPlayerPage(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host == "youtu.be" || host.contains("shadertoy.com")
    }

    private static func convert(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return urlString }

        // YouTube：转 embed，静音自动播 + 循环 + 无控件
        if host.contains("youtube.com") || host == "youtu.be" {
            let vid: String?
            if host == "youtu.be" {
                vid = url.pathComponents.count > 1 && url.pathComponents[1] != "" ? url.pathComponents[1] : nil
            } else if url.path == "/embed" || url.path.hasPrefix("/embed/") {
                return urlString   // 本来就是 embed
            } else {
                vid = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            }
            if let v = vid, !v.isEmpty {
                return "https://www.youtube.com/embed/\(v)?autoplay=1&mute=1&loop=1&playlist=\(v)"
                     + "&controls=0&modestbranding=1&playsinline=1&rel=0&iv_load_policy=3"
            }
        }

        // Shadertoy：转 embed（实时着色器，gui 关掉）
        if host.contains("shadertoy.com") {
            let comp = url.pathComponents.filter { $0 != "/" && $0 != "" }
            if let id = comp.last, id.count >= 4, !url.path.hasPrefix("/embed") {
                return "https://www.shadertoy.com/embed/\(id)?gui=false&paused=false&muted=false"
            }
        }

        return urlString
    }
}

// MARK: - 渲染视图

final class WebWallpaperView: NSView {

    private(set) var webView: WKWebView?

    /// rAF 节流：把页面的 requestAnimationFrame 限到 capFPS。
    ///
    /// Shadertoy 这类 WebGL 页面会以屏幕刷新率满帧渲染，5K 屏上等于每秒
    /// 几千万像素的着色器运算跑在桌面层 —— 实测整机会明显卡顿。壁纸是背景，
    /// 30fps 完全够看，GPU 成本直接减半。
    ///
    /// 必须在 documentStart 注入：页面脚本一加载就会抓 rAF，晚了就劫持不住。
    private static func throttleJS(capFPS: Int) -> String {
        """
        (function(){
          var CAP = \(max(5, capFPS));
          var MIN = 1000 / CAP - 3;
          var last = 0;
          function wrap(orig){
            return function(cb){
              return orig.call(window, function(t){
                if (t - last < MIN) { window.requestAnimationFrame(cb); return; }
                last = t;
                cb(t);
              });
            };
          }
          if (window.requestAnimationFrame) window.requestAnimationFrame = wrap(window.requestAnimationFrame);
          if (window.webkitRequestAnimationFrame) window.webkitRequestAnimationFrame = wrap(window.webkitRequestAnimationFrame);
        })();
        """
    }

    /// 静音 + 自动播 + 播放器页铺满裁切。documentEnd 注入，每次导航都会跑。
    private static let bootJS: String = {
        let playerCSS = """
        var s=document.createElement('style');
        s.textContent='video{object-fit:cover!important;width:100vw!important;height:100vh!important;'
            +'position:fixed!important;left:0!important;top:0!important}body{overflow:hidden!important;background:#000}';
        document.head.appendChild(s);
        """
        let core = """
        document.querySelectorAll('video,audio').forEach(function(e){e.muted=true;e.volume=0;});
        document.querySelectorAll('video').forEach(function(e){
            e.loop=true; e.setAttribute('loop','');
            var p=e.play(); if(p&&p.catch){p.catch(function(){});}
        });
        document.body&&(document.body.style.overflow='hidden');
        """
        let script = core + "\nif(window.location.host.indexOf('youtube.com')>=0||window.location.host.indexOf('shadertoy.com')>=0){\(playerCSS)}"
        return script
    }()

    private static let jsPause  = "document.querySelectorAll('video,audio').forEach(function(e){e.pause();});"
    private static let jsResume = """
    document.querySelectorAll('video,audio').forEach(function(e){
        var p=e.play(); if(p&&p.catch){p.catch(function(){});}
    });
    """

    init(frame: NSRect, urlString: String, isPlayerPage: Bool, capFPS: Int = 30) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let cfg = WKWebViewConfiguration()
        // 自动播放不需要用户手势（壁纸没人去点）
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // 注：老写法 preferences/webView 的 KVC drawsBackground 在新 macOS 上
        // 已直接抛 NSUnknownKeyException（实测 SIGTRAP），不能再用。
        // 壁纸窗口本身就是黑底，网页露边就是黑边，跟视频 letterbox 一致。

        let user = WKUserContentController()
        // 限帧必须最先注入（页面脚本一跑就会抓 rAF）
        user.addUserScript(WKUserScript(source: Self.throttleJS(capFPS: capFPS),
                                        injectionTime: .atDocumentStart,
                                        forMainFrameOnly: false))
        let us = WKUserScript(source: Self.bootJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        user.addUserScript(us)
        cfg.userContentController = user

        let wv = WKWebView(frame: bounds, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.allowsLinkPreview = false
        // 页面加载完成前的底色用黑，避免壁纸位置白屏一闪（公开 API）
        if #available(macOS 12.0, *) { wv.underPageBackgroundColor = .black }
        addSubview(wv)
        webView = wv

        if let url = URL(string: urlString) {
            wv.load(URLRequest(url: url))
        }
        _ = isPlayerPage // 样式已经并入 bootJS 按 host 判断，这里只是保住参数签名
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 自动暂停：停页面里的媒体（不拆窗口，恢复时原地续播）
    func pauseMedia() {
        webView?.evaluateJavaScript(Self.jsPause, completionHandler: nil)
    }

    /// 条件解除：从暂停处续播
    func resumeMedia() {
        webView?.evaluateJavaScript(Self.jsResume, completionHandler: nil)
    }

    /// 彻底释放（换壁纸 / 关闭时）：停加载 + 拆视图，WebContent 进程随之回收
    func shutdown() {
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView?.removeFromSuperview()
        webView = nil
    }
}

// MARK: - 缩略图（网页壁纸没有视频帧可抽，用统一的地球图标）

enum WebThumb {
    static func icon() -> NSImage? {
        let img = NSImage(systemSymbolName: "globe",
                          accessibilityDescription: "网页壁纸")?
            .withSymbolConfiguration(.init(pointSize: 34, weight: .medium))
        img?.isTemplate = false
        return img
    }
}
