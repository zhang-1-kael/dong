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

    /// 判断一段文字像不像视频链接（避免把随便粘贴的东西丢给 yt-dlp）
    static func looksLikeLink(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > 8, !s.contains(" ") else { return false }
        if let url = URL(string: s), let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()), url.host != nil {
            return true
        }
        return false
    }

    // MARK: 下载

    func fetch(_ link: String, into dir: URL, ffmpeg: URL?) throws -> URL {
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
