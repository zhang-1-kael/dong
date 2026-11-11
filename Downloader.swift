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

    // MARK: 下载

    func fetch(_ link: String, into dir: URL, ffmpeg: URL?) throws -> URL {
        let fm = FileManager.default
        // 入口统一清洗一次：用户贴进来的可能是「标题 + 链接」一整段，只把链接交给 yt-dlp
        let link = Downloader.extractLink(link)
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
        if let ffmpeg { args += ["--ffmpeg-location", ffmpeg.path] }
        args.append(link)

        DispatchQueue.main.async { self.onStage?("正在解析链接…") }

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
            // 抖音这类平台有 a_bogus 反爬，yt-dlp 会抛
            // "Fresh cookies (not necessarily logged in) are needed"。
            // 原话对用户没有意义，翻译成一句能照着做的。
            if link.lowercased().contains("douyin") || tail.localizedCaseInsensitiveContains("cookie") {
                throw Failure(message: "这个平台的视频要登录后才能抓取（抖音有反爬，必须带登录态）。"
                    + "请先在 App 里把视频保存到本地，再拖进 Dòng。")
            }
            let brief = tail
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("[download]") }
                .suffix(2)
                .joined(separator: "；")
            throw Failure(message: brief.isEmpty
                ? "下载失败。链接可能不合法，或者这个视频需要登录才能看。"
                : "下载失败：\(brief)")
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
