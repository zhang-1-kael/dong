import Foundation

/// 链接下载：把网页上的视频抓成本地文件，再交给 Transcoder 走同一条优化流水线。
/// 只负责「拿到原始文件」，画质裁切、去跳帧、首尾淡化都还是 Transcoder 的事。
final class Downloader {

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let tool: URL
    var onProgress: ((Double) -> Void)?
    var onStage: ((String) -> Void)?

    init(tool: URL) { self.tool = tool }

    /// 内置优先，其次看系统里有没有装的（开发时方便）
    static var ytdlpURL: URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "bin"),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let paths = [
            LockScreen.home.appendingPathComponent(".local/bin/yt-dlp").path,
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
        ]
        for p in paths where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// 平台复制出来的多是「标题 + 链接」，只留里面那条链接。
    ///
    /// 抖音 App 里点「复制链接」，剪贴板拿到的是一整段文案：
    ///     「8.38 复制打开抖音，看看【鹿鸣的作品】月亮之上 云层之下 … https://v.douyin.com/iRNxxxx/ …」
    /// 里面既有中文又有空格，谁拿「不含空格」去判真假都会把它判成「不是链接」。
    /// 所以先正则捞出 URL，再把紧跟在后面的中文句读削掉。
    static func extractLink(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 注意：这里必须是普通字符串，不能用 raw string(#"..."#)——
        // raw string 里 \u{3000} 不会被转义，ICU 正则会把它当成字面字符而抛异常。
        // \\s 排除 ASCII 空白，\u{3000} 是全角空格，分享文案里两种都会有。
        guard let r = t.range(of: "https?://[^\\s\u{3000}]+", options: .regularExpression) else {
            return t
        }
        // 中文常常紧贴在链接后面（「…/abc/。复制打开抖音」「…/abc/”这个」），
        // 正则只按空白断句，会把整段中文一起吃进来。从尾部逐个削掉不像 URL 的字符。
        var link = String(t[r])
        while let last = link.unicodeScalars.last, !Self.urlChars.contains(Character(last)) {
            link.removeLast()
        }
        return link
    }

    /// URL 里会出现的字符（**只含 ASCII**）。
    /// 用来把链接后面跟着的中文文案切掉。
    /// 不能用 CharacterSet.alphanumerics —— 那个集合按 Unicode 分类算，中文也属于「字母」。
    private static let urlChars: Set<Character> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%"
    )

    /// 判断一段文字像不像视频链接（避免把随便粘贴的东西丢给 yt-dlp）
    ///
    /// 先提取、后判定。以前要求「不含空格」，结果从抖音复制出来的分享文本
    /// （带大段中文和空格）必然被拒，用户看到的就是「这不像一条视频链接」。
    static func looksLikeLink(_ raw: String) -> Bool {
        let s = Self.extractLink(raw)
        guard s.count > 8 else { return false }
        if let url = URL(string: s), let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()), url.host != nil {
            return true
        }
        return false
    }

    // MARK: 平台判定 / 浏览器探测

    /// 是不是抖音系链接：v.douyin.com 短链、www.douyin.com 正链、iesdouyin.com 分享页。
    /// 抖音的 a_bogus / msToken 签名墙要的是 `s_v_web_id` 这个游客 cookie，得借浏览器。
    static func isDouyin(_ link: String) -> Bool {
        let host = (URL(string: link)?.host ?? "").lowercased()
        return host.contains("douyin.com") || host.contains("iesdouyin.com")
    }

    /// 抖音把视频和图文的分享直链都写成 `/note/<id>`，但 yt-dlp 的 douyin extractor
    /// 只认 `/video/<id>`——note 路径会直接报 `Unsupported URL`，连借 cookie 那关都走不到。
    /// 同一个 aweme_id 两条路径指向同一条内容，所以下载前把 note 归一化成 video。
    /// 纯图文笔记（只有图片没有视频）转成 video 后没有视频流，交给下载阶段的报错/引导处理。
    static func normalizeDouyinLink(_ link: String) -> String {
        guard var c = URLComponents(string: link),
              let host = c.host?.lowercased(), host.contains("douyin.com"),
              c.path.hasPrefix("/note/") else { return link }
        c.path = "/video/" + String(c.path.dropFirst("/note/".count))
        return c.string ?? link
    }

    /// 本机装了哪些能借 cookie 的浏览器（按成功率高到低排序）。
    /// 只列 cookie 库真实存在的，免得 yt-dlp 对每个没装的浏览器都白跑一遍、刷一屏报错。
    /// Chrome 系取 Default 配置；多用户场景若主配置没访问过抖音，可能因缺少 s_v_web_id 失败，
    /// 届时的引导文案会告诉用户怎么办。
    static func availableCookieBrowsers() -> [String] {
        let fm = FileManager.default
        let h = NSHomeDirectory()
        let candidates: [(String, [String])] = [
            ("chrome",  ["\(h)/Library/Application Support/Google/Chrome/Default/Cookies"]),
            ("edge",    ["\(h)/Library/Application Support/Microsoft Edge/Default/Cookies"]),
            ("brave",   ["\(h)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies"]),
            ("vivaldi", ["\(h)/Library/Application Support/Vivaldi/Default/Cookies"]),
            ("firefox", ["\(h)/Library/Application Support/Firefox/Profiles"]),
            ("safari",  ["\(h)/Library/Cookies/Cookies.binarycookies"]),
        ]
        return candidates
            .filter { $0.1.contains { fm.fileExists(atPath: $0) } }
            .map { $0.0 }
    }

    private static func displayName(_ browser: String) -> String {
        ["chrome": "Chrome", "edge": "Edge", "brave": "Brave", "vivaldi": "Vivaldi",
         "firefox": "Firefox", "safari": "Safari"][browser] ?? browser
    }

    // MARK: 下载入口

    func fetch(_ link: String, into dir: URL, ffmpeg: URL?) throws -> URL {
        // 入口统一清洗一次：用户贴进来的可能是「标题 + 链接」一整段，只取链接部分。
        // 注意：抖音**不要**再做 /note/ → /video/ 归一化。那是 F4（yt-dlp）时代的遗留，
        // WKWebView 方案是靠加载用户给的原页面来截获详情接口的，/note/ 页面才是
        // 实况图（image_post_info.images[].video）的正确来源，转成 /video/ 反而会
        // 拿到背景音乐音频流、后续转码找不到画面。
        let link = Downloader.extractLink(link)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if Downloader.isDouyin(link) {
            // 抖音改用内置 WKWebView 抓取：让抖音自己的 JS 完成 Argus 签名，
            // 我们从详情接口响应里取视频 / 实况图直链。yt-dlp 路线已确认走不通。
            let fetcher = DouyinWebFetcher()
            return try fetcher.fetch(link, into: dir, ffmpeg: ffmpeg, onStage: self.onStage)
        }
        DispatchQueue.main.async { self.onStage?("正在解析链接…") }
        return try downloadOnce(link, into: dir, ffmpeg: ffmpeg, browser: nil)
    }

    /// 抖音：借用本机浏览器的游客 cookie 逐个尝试。
    ///
    /// 实测结论（2026-11）：yt-dlp 的抖音 extractor 复用 TikTok 逻辑，真正卡人的是
    /// `Fresh cookies (not necessarily logged in) are needed`——要的是 `s_v_web_id`
    /// 这个游客 cookie，**不需要登录**，但要求用户最近在浏览器里打开过抖音网页。
    /// 所以这里不弹「必须登录」这种误导文案，而是自动借、失败时给出能照做的引导。
    private func fetchDouyin(_ link: String, into dir: URL, ffmpeg: URL?) throws -> URL {
        let browsers = Downloader.availableCookieBrowsers()
        guard !browsers.isEmpty else { throw Failure(message: Self.guideNoBrowser) }

        var lastDetail = ""
        for browser in browsers {
            DispatchQueue.main.async {
                self.onStage?("正在借 \(Self.displayName(browser)) 的浏览记录解析…")
            }
            do {
                return try downloadOnce(link, into: dir, ffmpeg: ffmpeg, browser: browser)
            } catch let f as Failure {
                lastDetail = f.message
                // 清掉这次失败留下的空壳/半成品，免得下一个浏览器成功后取到错误文件
                try? FileManager.default.removeItem(at: dir)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        throw Failure(message: Self.guideWithDetail(lastDetail))
    }

    /// 用户没装任何主流浏览器时，没法借 cookie。
    private static let guideNoBrowser =
        "没检测到 Chrome / Safari 等浏览器，借不到抖音需要的浏览记录。"
        + "请先在浏览器打开一次抖音网页，或把视频在抖音 App 里存到本地、再拖进 Dòng。"

    /// 借了 cookie 仍失败——把「先打开一次抖音网页」这句可操作的话放最前面。
    private static func guideWithDetail(_ detail: String) -> String {
        let tail = detail.isEmpty ? "" : "（上次失败：\(tidy(detail))）"
        return "抖音的视频需要一份新鲜的浏览记录才能抓取，不用登录。"
            + "请在 Chrome 里打开一次抖音网页、随便看一个视频，然后回到 Dòng 重新粘贴链接。"
            + "若刚打开过仍不行，把视频在抖音 App 里存到本地、再拖进 Dòng。"
            + "注意：纯图文笔记（只有图片、没有视频）无法做成动态壁纸。" + tail
    }

    /// 失败详情压成一行、限长，避免引导文案被 yt-dlp 的整段报错撑爆。
    private static func tidy(_ s: String) -> String {
        let one = s.split(separator: "\n").last.map(String.init) ?? s
        return one.count > 90 ? String(one.prefix(90)) + "…" : one
    }

    /// 真正跑一次 yt-dlp。browser 为 nil 表示不借 cookie（B站 / YouTube 等普通平台）。
    private func downloadOnce(_ link: String, into dir: URL, ffmpeg: URL?, browser: String?) throws -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 只要视频流（壁纸不需要声音）；优先 h264，AVFoundation 解起来最稳，
        // 拿不到再退 HEVC / 任意编码，最后才退「音视频合一的单文件」。
        var args = [
            "--no-playlist",
            "--newline",
            "--no-warnings",
            "--no-mtime",
            "--no-part",
            "-f", "bv*[height<=1080][vcodec^=avc1]/bv*[height<=1080][vcodec^=hev]/"
                + "bv*[height<=1080]/b[height<=1080]/b",
            "--merge-output-format", "mp4",
            "--remux-video", "mp4",
            "-o", dir.appendingPathComponent("%(title).70s.%(ext)s").path,
        ]
        // 抖音唯一的通行证：借浏览器的游客 cookie（含 s_v_web_id）。
        // 其他平台不传，行为与改动前完全一致。
        if let browser { args += ["--cookies-from-browser", browser] }
        if let ffmpeg { args += ["--ffmpeg-location", ffmpeg.path] }
        args.append(link)

        let p = Process()
        p.executableURL = tool
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        let lock = NSLock()
        var pending = Data()
        var errors = ""

        outPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            lock.lock(); pending.append(chunk)
            var lines: [String] = []
            while let nl = pending.firstIndex(of: 0x0A) {
                let piece = pending[..<nl]
                pending.removeSubrange(...nl)
                if let s = String(data: piece, encoding: .utf8) { lines.append(s) }
            }
            lock.unlock()
            for s in lines { self.consume(line: s) }
        }

        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty, let s = String(data: chunk, encoding: .utf8) else { return }
            lock.lock(); errors += s; lock.unlock()
        }

        try p.run()
        p.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        guard p.terminationStatus == 0 else {
            lock.lock(); let tail = errors; lock.unlock()
            let brief = tail
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("[download]") }
                .suffix(2)
                .joined(separator: "；")
            throw Failure(message: brief.isEmpty
                ? "下载失败。链接可能不合法，或者这个视频需要登录才能看。"
                : brief)
        }

        // 取目录里最大的那个视频，就是正片
        let items = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm"]
        let candidates = items.filter { videoExts.contains($0.pathExtension.lowercased()) }
        let sizeOf: (URL) -> Int = { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        guard let best = candidates.max(by: { sizeOf($0) < sizeOf($1) }), sizeOf(best) > 100_000 else {
            throw Failure(message: "没下到可用的视频文件（可能是直播流或付费内容）")
        }
        return best
    }

    // MARK: 输出解析

    private func consume(line raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }

        if line.hasPrefix("[download]"), let pct = Self.percent(in: line) {
            DispatchQueue.main.async { self.onProgress?(pct) }
            return
        }
        if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") || line.hasPrefix("[VideoConvertor]") {
            DispatchQueue.main.async { self.onStage?("整理视频容器…") }
            return
        }
        if line.hasPrefix("[info]") && line.contains("Downloading 1 format") {
            DispatchQueue.main.async { self.onStage?("开始下载…") }
        }
    }

    private static func percent(in line: String) -> Double? {
        guard let r = line.range(of: #"[0-9]+\.[0-9]+%"#, options: .regularExpression) else { return nil }
        let text = line[r].dropLast()   // 去掉 %
        guard let v = Double(text) else { return nil }
        return min(max(v / 100.0, 0), 1)
    }
}
