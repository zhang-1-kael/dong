import Foundation
import AVFoundation
import Cocoa

/// 视频自动优化：统一帧率 → 按屏幕比例裁切 → 轻微锐化 → 首尾交叉淡化做成无缝循环 → 压缩
final class Transcoder {

    struct Info {
        var duration: Double
        var fps: Double
        var width: Int
        var height: Int
    }

    let ffmpeg: URL
    var onProgress: ((Double) -> Void)?
    var onStage: ((String) -> Void)?
    /// 回调投递队列：GUI 用主线程，命令行没有 run loop，改成后台队列才收得到
    var callbackQueue: DispatchQueue = .main

    init(ffmpeg: URL) { self.ffmpeg = ffmpeg }

    // MARK: ffmpeg 位置

    static var ffmpegURL: URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin"),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let local = LockScreen.home.appendingPathComponent(".local/bin/ffmpeg")
        if fm.isExecutableFile(atPath: local.path) { return local }
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    // MARK: 探测

    static func probe(_ url: URL) -> Info? {
        let asset = AVURLAsset(url: url)
        let dur = CMTimeGetSeconds(asset.duration)
        guard dur.isFinite, dur > 0.2 else { return nil }
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        let fps = Double(track.nominalFrameRate) > 0 ? Double(track.nominalFrameRate) : 30
        return Info(duration: dur,
                    fps: fps,
                    width: Int(abs(size.width).rounded()),
                    height: Int(abs(size.height).rounded()))
    }

    /// 目标尺寸：等比例缩进屏幕框内，保持原片比例（不再强改成屏幕比例，避免把上下/左右裁掉）
    static func targetSize(for info: Info) -> (w: Int, h: Int) {
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1600, height: 1000)
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        // 屏幕的物理像素框（上限 3200×2000，省点体积）
        let boxW = min(3200.0, screen.width * scale)
        let boxH = min(2000.0, screen.height * scale)
        let sw = Double(max(info.width, 2))
        let sh = Double(max(info.height, 2))
        // 只缩不放，等比塞进框里
        let k = min(1.0, min(boxW / sw, boxH / sh))
        var w = Int((sw * k).rounded())
        var h = Int((sh * k).rounded())
        w -= w % 2
        h -= h % 2
        return (max(w, 2), max(h, 2))
    }

    // MARK: 片尾水印 / 片尾卡检测

    /// 上一次 importVideo 的处理结果（给界面提示用）
    private(set) var lastTrimmed: Double = 0        // 片尾
    private(set) var lastHeadTrimmed: Double = 0    // 片头
    private(set) var lastWatermark: Watermark?      // 画面内角标

    /// 找视频结尾那段"几乎不动"的片尾卡（作者名、logo、片尾水印），返回应该截到哪儿。
    /// 做法：每秒取 8 帧、算相邻帧差（运动量），结尾若有一大段运动量骤降就认定是片尾卡。
    func detectEndCard(url: URL, duration: Double) -> (end: Double, removed: Double)? {
        guard duration > 7 else { return nil }
        let window = min(30.0, max(6.0, duration * 0.6))
        let start = max(0.0, duration - window)

        let vf = "fps=8,scale=160:-2,tblend=all_mode=difference,"
            + "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-"
        let r = run(["-nostdin", "-hide_banner", "-loglevel", "error",
                     "-ss", String(format: "%.3f", start), "-copyts",
                     "-i", url.path, "-an", "-vf", vf, "-f", "null", "-"])
        guard r.code == 0 else { return nil }

        let samples = Self.parseMotion(r.out, fallbackStart: start)
        guard samples.count > 24 else { return nil }

        // 前 60% 的窗口当作"正片"，用中位数当基准（壁纸很多本身就很静，所以要相对比较）
        let pivot = start + window * 0.6
        let content = samples.filter { $0.t < pivot }.map { $0.v }.sorted()
        guard content.count > 12 else { return nil }
        let baseline = content[content.count / 2]

        func meanMotion(after t: Double) -> Double {
            // 不含切点自身那一帧（那一帧的帧差是两个场景的差，数值巨大）
            let tail = samples.filter { $0.t > t + 0.001 }.map { $0.v }
            guard !tail.isEmpty else { return 0 }
            return tail.reduce(0, +) / Double(tail.count)
        }

        // ── 信号 A：结尾有一次"硬切"，切完就没动静了 → 片尾卡 ──
        let spike = max(baseline * 4, 10.0)
        var cut: Double?
        for s in samples where s.t >= duration * 0.5 {
            if s.v >= spike { cut = s.t }        // 取符合条件的最后一个
        }
        if let c = cut {
            let removed = duration - c
            if removed >= 1.0, removed <= max(4.0, duration * 0.4),
               meanMotion(after: c) <= max(baseline * 0.8, 2.5) {
                return (c, removed)
            }
        }

        // ── 信号 B：结尾一段几乎全静止（淡出到黑屏 / 静态 logo） ──
        let still = max(baseline * 0.12, 0.25)
        var idx = samples.count - 1
        var quietStart: Double?
        while idx >= 0, samples[idx].v <= still {
            quietStart = samples[idx].t
            idx -= 1
        }
        if let qs = quietStart {
            let removed = duration - qs
            if removed >= 1.2, removed <= max(4.0, duration * 0.4) {
                return (qs, removed)
            }
        }

        return nil
    }

    /// 跑一个 ffmpeg 子进程，把 stdout / stderr 都收回来
    private func run(_ args: [String]) -> (out: String, err: String, code: Int32) {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e

        var errData = Data()
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            errData = e.fileHandleForReading.readDataToEndOfFile()
            sem.signal()
        }
        do { try p.run() } catch {
            return ("", error.localizedDescription, -1)
        }
        let outData = o.fileHandleForReading.readDataToEndOfFile()
        sem.wait()
        p.waitUntilExit()
        return (String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "",
                p.terminationStatus)
    }

    // MARK: 片头 / 角标

    /// 画面里常驻不动的一小块（平台角标、作者水印），坐标按最终输出尺寸算
    struct Watermark {
        var x: Int
        var y: Int
        var w: Int
        var h: Int
        var corner: String
    }

    /// 解析 ffmpeg 的 metadata=print 输出，拿到 (时间, 运动量)
    private static func parseMotion(_ text: String, fallbackStart: Double) -> [(t: Double, v: Double)] {
        var samples: [(t: Double, v: Double)] = []
        var t = fallbackStart
        for line in text.split(separator: "\n") {
            if line.hasPrefix("frame:") {
                if let rng = line.range(of: "pts_time:") {
                    let num = line[rng.upperBound...].prefix { "0123456789.-".contains($0) }
                    if let d = Double(num) { t = d }
                }
            } else if line.hasPrefix("lavfi.signalstats.YAVG=") {
                if let v = Double(line.dropFirst("lavfi.signalstats.YAVG=".count)), v.isFinite {
                    samples.append((t, v))
                }
            }
        }
        return samples
    }

    /// 整段扫一遍运动量（1/fps 秒一帧，数值 = 相邻帧平均亮度差）
    private func scanMotion(url: URL, from: Double, to: Double,
                            fps: Int, width: Int) -> [(t: Double, v: Double)] {
        let vf = "fps=\(fps),scale=\(width):-2,tblend=all_mode=difference,"
            + "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-"
        let r = run(["-nostdin", "-hide_banner", "-loglevel", "error",
                     "-ss", String(format: "%.3f", from), "-copyts",
                     "-i", url.path, "-an",
                     "-t", String(format: "%.3f", max(to - from, 0.5)),
                     "-vf", vf, "-f", "null", "-"])
        guard r.code == 0 else { return [] }
        return Self.parseMotion(r.out, fallbackStart: from)
    }

    /// 片头介绍：开头那段运动明显比主体大，且有一次硬切或骤降进入主体 → 返回该剪到哪儿
    func detectHead(url: URL, duration: Double) -> Double? {
        guard duration > 8 else { return nil }
        let samples = scanMotion(url: url, from: 0, to: duration, fps: 6, width: 128)
        guard samples.count > 30 else { return nil }

        // 主体基准：后半段运动量的中位数（壁纸本身也可能在动，所以只做相对比较）
        let body = samples.filter { $0.t >= duration * 0.55 }.map { $0.v }.sorted()
        guard body.count > 10 else { return nil }
        let baseline = body[body.count / 2]

        let quiet = max(baseline * 1.25, 2.5)
        let loud = max(baseline * 2.5, 6.0)
        let limit = duration * 0.4

        var candidate: Double?

        // 信号 A：开头有一次硬切，切完就进入主体（介绍多半是多镜头剪辑）
        let spike = max(baseline * 4, 12.0)
        let cuts = samples.filter { $0.v >= spike && $0.t <= limit }.map { $0.t }
        candidate = nil
        if let last = cuts.last, last >= 1.2 {
            let before = samples.filter { $0.t < last }.map { $0.v }
            let after = samples.filter { $0.t > last + 0.35 && $0.t < last + 2.4 }.map { $0.v }
            if !before.isEmpty, !after.isEmpty {
                let bm = before.reduce(0, +) / Double(before.count)
                let am = after.reduce(0, +) / Double(after.count)
                if bm >= loud, am <= quiet,
                   cuts.count >= 2 || bm >= max(baseline * 3, 8),
                   duration - last >= 4.0 {
                    candidate = last
                }
            }
        }

        // 信号 B：没有硬切，但开头更"热闹"，之后突然安静下来
        if candidate == nil {
            for s in samples where s.t >= 1.2 && s.t <= limit {
                let before = samples.filter { $0.t < s.t }.map { $0.v }
                let after = samples.filter { $0.t >= s.t && $0.t < s.t + 1.6 }.map { $0.v }
                guard before.count > 8, after.count > 6 else { continue }
                let bm = before.reduce(0, +) / Double(before.count)
                let am = after.reduce(0, +) / Double(after.count)
                if bm >= loud, am <= quiet, duration - s.t >= 4.0 {
                    candidate = s.t
                    break
                }
            }
        }

        guard let c = candidate else { return nil }
        // 最后的把关：开头那一段得是「另一种画面」。
        // 很多壁纸开头本来就有推镜/淡入，运动量也大，但那还是同一张壁纸，不能剪。
        return headDiffersFromBody(url: url, cut: c, duration: duration) ? c : nil
    }

    /// 开头段落和主体段落是不是两种画面（黑底标题卡 / 口播 vs 正片）。
    /// 用 16 档灰度直方图的 L1 距离判断，同一张壁纸的前后差异会很小。
    private func headDiffersFromBody(url: URL, cut: Double, duration: Double) -> Bool {
        guard cut > 0.8, duration - cut > 2.5 else { return false }

        func hist(at t: Double) -> [Float]? {
            let r = runData(["-nostdin", "-hide_banner", "-loglevel", "error",
                             "-ss", String(format: "%.3f", t),
                             "-i", url.path, "-frames:v", "1",
                             "-vf", "scale=160:-2,format=gray", "-f", "rawvideo", "-"])
            guard r.code == 0, r.data.count > 800 else { return nil }
            var bins = [Float](repeating: 0, count: 16)
            for b in r.data { bins[Int(b) / 16] += 1 }
            let total = Float(r.data.count)
            return bins.map { $0 / total }
        }

        var heads: [[Float]] = []
        var bodies: [[Float]] = []
        for k in 1...3 {
            if let h = hist(at: cut * Double(k) / 4) { heads.append(h) }
            if let b = hist(at: cut + 1.5 + (duration - cut - 2) * Double(k) / 4) { bodies.append(b) }
        }
        guard !heads.isEmpty, !bodies.isEmpty else { return false }

        var sum: Float = 0
        var pairs = 0
        for h in heads {
            for b in bodies {
                var d: Float = 0
                for i in 0..<16 { d += abs(h[i] - b[i]) }
                sum += d / 2
                pairs += 1
            }
        }
        return sum / Float(max(pairs, 1)) >= 0.34
    }

    /// 画面内角标：找四角里「一段时间内始终是纯白、且有文字笔画」的小条块。
    /// 依据：平台水印是叠上去的白字（三通道都亮、几乎无色偏），而且位置不动。
    /// 画面里的白色高光虽然也白，但要么成片、要么没有密集笔画，会被形状与边缘密度筛掉。
    func detectWatermark(url: URL, from start: Double, to end: Double,
                         target: (w: Int, h: Int)) -> Watermark? {
        let span = end - start
        guard span > 2.0, target.w > 0, target.h > 0 else { return nil }

        let W = 480
        var ph = Int((Double(W) * Double(target.h) / Double(target.w)).rounded())
        if ph % 2 != 0 { ph += 1 }
        ph = max(ph, 64)
        // 按成片的裁切方式缩到小图，检测到的框可以直接映射回成片坐标
        let vf = "scale=\(W):\(ph):flags=area:force_original_aspect_ratio=increase,crop=\(W):\(ph)"

        let wanted = 9
        let need = W * ph * 3
        var frames: [[UInt8]] = []
        for i in 0..<wanted {
            let t = start + span * (Double(i) + 0.5) / Double(wanted)
            let r = runData(["-nostdin", "-hide_banner", "-loglevel", "error",
                             "-ss", String(format: "%.3f", t),
                             "-i", url.path, "-frames:v", "1",
                             "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
            guard r.code == 0, r.data.count >= need else { continue }
            frames.append(Array(r.data.prefix(need)))
        }
        guard frames.count >= 5 else { return nil }

        let fc = Float(frames.count)
        let n = W * ph
        var sumGray = [Float](repeating: 0, count: n)
        var whiteHits = [Float](repeating: 0, count: n)

        for img in frames {
            for i in 0..<n {
                let r = Float(img[i * 3])
                let g = Float(img[i * 3 + 1])
                let b = Float(img[i * 3 + 2])
                sumGray[i] += (r + g + b) / 3
                let mn = min(r, min(g, b))
                let mx = max(r, max(g, b))
                if mn > 185 && mx - mn < 22 { whiteHits[i] += 1 }
            }
        }

        var gray = [Float](repeating: 0, count: n)
        for i in 0..<n { gray[i] = sumGray[i] / fc }

        var mask = [Bool](repeating: false, count: n)
        var grad = [Float](repeating: 0, count: n)
        for y in 1..<(ph - 1) {
            let row = y * W
            for x in 1..<(W - 1) {
                let i = row + x
                let g = abs(gray[i + 1] - gray[i - 1]) + abs(gray[i + W] - gray[i - W])
                grad[i] = g
                if g > 22 && whiteHits[i] / fc > 0.72 { mask[i] = true }
            }
        }

        let regions: [(String, Int, Int, Int, Int)] = [
            ("左上角", 0, 0, Int(Double(W) * 0.45), Int(Double(ph) * 0.27)),
            ("右上角", Int(Double(W) * 0.55), 0, W, Int(Double(ph) * 0.27)),
            ("左下角", 0, Int(Double(ph) * 0.73), Int(Double(W) * 0.45), ph),
            ("右下角", Int(Double(W) * 0.55), Int(Double(ph) * 0.73), W, ph),
        ]

        var best: (corner: String, x0: Int, y0: Int, x1: Int, y1: Int, score: Int)?
        let maxArea = Double(W * ph) * 0.045

        for (name, rx0, ry0, rx1, ry1) in regions {
            let rowTh = max(3, Int(Double(rx1 - rx0) * 0.02))
            func rowHits(_ y: Int) -> Int {
                var c = 0
                let base = y * W
                for x in rx0..<rx1 where mask[base + x] { c += 1 }
                return c
            }

            var y = max(ry0, 1)
            while y < min(ry1, ph - 1) {
                guard rowHits(y) > rowTh else { y += 1; continue }
                var ya = y, yb = y, gap = 0
                while y < min(ry1, ph - 1), gap <= 1 {
                    if rowHits(y) > rowTh { yb = y; gap = 0 } else { gap += 1 }
                    y += 1
                }
                // 这一条横带里的左右边界
                var minX = Int.max, maxX = -1, area = 0
                for yy in ya...yb {
                    let base = yy * W
                    for x in rx0..<rx1 where mask[base + x] {
                        area += 1
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                    }
                }
                guard maxX >= minX, area > 0 else { continue }
                let bw = maxX - minX + 1
                let bh = yb - ya + 1
                guard bw >= 26, bh >= 6 else { continue }
                guard Double(bw) <= Double(W) * 0.38, Double(bh) <= Double(ph) * 0.20 else { continue }
                guard Double(bw * bh) <= maxArea else { continue }
                guard Double(bh) <= Double(ph) * 0.065 else { continue }

                // 水印是细长的字行；成片的白色高光宽高比小、内部也没那么多笔画
                let aspect = Double(bw) / Double(bh)
                guard aspect >= 4.2 else { continue }
                var edges = 0
                for yy in ya...yb {
                    let base = yy * W
                    for x in minX...maxX where grad[base + x] > 22 { edges += 1 }
                }
                let dens = Double(edges) / Double(bw * bh)
                guard dens >= 0.55 else { continue }
                guard Double(area) / Double(bw * bh) >= 0.08 else { continue }

                // 水印一定贴着画面边角；画面自带的 UI / 白色图案通常离边远
                let gapX = min(minX - rx0 + (rx0 == 0 ? 0 : 0), W - 1 - maxX)
                let gapY = min(ya, ph - 1 - yb)
                guard Double(gapX) <= Double(W) * 0.06 else { continue }
                guard Double(gapY) <= Double(ph) * 0.12 else { continue }

                let score = bw * bh
                if best == nil || score > best!.score {
                    best = (name, minX, ya, maxX, yb, score)
                }
            }
        }
        guard let b = best else { return nil }

        // 外扩一点，把抗锯齿边缘和阴影一起盖住
        let pad = 6
        let sx = Double(target.w) / Double(W)
        let sy = Double(target.h) / Double(ph)
        var x = Int((Double(b.x0 - pad) * sx).rounded(.down))
        var y = Int((Double(b.y0 - pad) * sy).rounded(.down))
        var w = Int((Double(b.x1 - b.x0 + 1 + pad * 2) * sx).rounded(.up))
        var h = Int((Double(b.y1 - b.y0 + 1 + pad * 2) * sy).rounded(.up))

        x = max(0, min(x, target.w - 4))
        y = max(0, min(y, target.h - 4))
        w = min(w, target.w - x)
        h = min(h, target.h - y)
        if x % 2 != 0 { x -= 1 }
        if y % 2 != 0 { y -= 1 }
        if w % 2 != 0 { w -= 1 }
        if h % 2 != 0 { h -= 1 }
        guard w >= 12, h >= 10 else { return nil }

        return Watermark(x: x, y: y, w: w, h: h, corner: b.corner)
    }

    /// 读二进制输出（抽帧灰度图用）
    private func runData(_ args: [String]) -> (data: Data, code: Int32) {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        DispatchQueue.global().async { _ = e.fileHandleForReading.readDataToEndOfFile() }
        do { try p.run() } catch { return (Data(), -1) }
        let d = o.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (d, p.terminationStatus)
    }

    // MARK: 转码

    func transcode(input: URL, output: URL, info: Info, size: (w: Int, h: Int),
                   start: Double = 0, end: Double? = nil,
                   watermark: Watermark? = nil) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 片头介绍 / 片尾卡被切掉后，一切时长都按剩下的算
        let s = min(max(start, 0), max(info.duration - 1.0, 0))
        let e = min(max(end ?? info.duration, s + 0.6), info.duration)
        let dur = max(e - s, 0.6)
        // 帧率 / 淡化来自「画面微调」的生成设置；默认仍是跟随源、上限 30、0.4s
        let cfr = Tuning.effectiveFPS(source: info.fps)
        let fade = dur > 2.0 ? min(Tuning.fadeSeconds, dur * 0.4) : 0.0
        let cut = max(dur - fade, 0.2)
        // 尺寸已经按原片比例算好，这里只做等比缩放，不再裁切（以前会把两侧/上下裁掉，画面看着被放大）
        let base = "fps=\(cfr),scale=\(size.w):\(size.h):flags=lanczos,"
            + "unsharp=5:5:0.4:5:5:0,format=yuv420p"

        func f(_ v: Double) -> String { String(format: "%.3f", v) }

        var args = ["-y", "-nostdin", "-hide_banner", "-loglevel", "error",
                    "-progress", "pipe:1", "-nostats"]

        // 每路输入都要走的同一条链：统一帧率 → 裁到目标尺寸 → 锐化 → 糊掉角标 → 统一像素格式
        var pipe = base
        if let wm = watermark {
            // delogo 用四周像素插值把这块填掉，比「打一块模糊」自然得多，不会留下一个灰方块
            let dx = max(1, min(wm.x, size.w - wm.w - 2))
            let dy = max(1, min(wm.y, size.h - wm.h - 2))
            pipe += ",delogo=x=\(dx):y=\(dy):w=\(wm.w):h=\(wm.h)"
        }
        pipe += ",setsar=1"

        if fade > 0 {
            // 首尾淡化分三段、各自独立 seek 取：片尾 fade、片头 fade、中间主体。
            //
            // 以前是在同一个输入上 split 再 trim 到片尾，问题在于 concat 会先等首段（来自片尾），
            // 等于要求 ffmpeg 把整片逐帧缓存下来等最后几秒 —— 内存随长度线性涨（约 130MB/分钟），
            // 20 分钟的片子飙到 2.6GB 就被系统 SIGKILL，界面报「处理失败」。
            // 现在三段分别 seek，只缓存 0.4 秒，20 分钟片子峰值内存约 170MB。
            args += ["-ss", f(s + dur - fade), "-t", f(fade), "-i", input.path,
                     "-ss", f(s),               "-t", f(fade), "-i", input.path,
                     "-ss", f(s + fade),        "-t", f(dur - fade), "-i", input.path]
            let graph = "[0:v]setpts=PTS-STARTPTS,\(pipe)[a];"
                + "[1:v]setpts=PTS-STARTPTS,\(pipe)[b];"
                + "[a][b]blend=all_expr='A*(1-T/\(f(fade)))+B*(T/\(f(fade)))':shortest=1[mix];"
                + "[2:v]setpts=PTS-STARTPTS,\(pipe)[mid];"
                + "[mix][mid]concat=n=2:v=1:a=0[out]"
            args += ["-filter_complex", graph, "-map", "[out]"]
        } else {
            args += ["-ss", f(s), "-t", f(dur), "-i", input.path]
            args += ["-filter_complex", "[0:v]setpts=PTS-STARTPTS,\(pipe)[out]", "-map", "[out]"]
        }

        args += ["-an", "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
                 "-crf", "20", "-preset", "medium",
                 "-maxrate", "14M", "-bufsize", "28M",
                 "-r", "\(cfr)", "-g", "\(cfr * 2)",
                 "-movflags", "+faststart", output.path]

        try? fm.removeItem(at: output)

        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = args
        // 后台进程若还连着终端，ffmpeg 读 stdin 会被 SIGTTIN 挂住，永远跑不完
        p.standardInput = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        let errPipe = Pipe()
        p.standardError = errPipe
        // stderr 必须有人读，否则缓冲区满了一样会卡住；顺便留个尾巴用于报错
        let errLock = NSLock()
        var errTail = Data()
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            errLock.lock()
            errTail.append(chunk)
            if errTail.count > 4096 { errTail = errTail.suffix(4096) }
            errLock.unlock()
        }

        let total = max(cut, 0.1)
        var buffer = Data()
        out.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<nl]
                buffer.removeSubrange(...nl)
                guard let s = String(data: line, encoding: .utf8) else { continue }
                if s.hasPrefix("out_time_us="), let us = Double(s.dropFirst(12)) {
                    let pct = min(1.0, max(0.0, us / 1_000_000.0 / total))
                    self.callbackQueue.async { self.onProgress?(pct) }
                }
            }
        }

        try p.run()
        p.waitUntilExit()
        out.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        if p.terminationStatus != 0 {
            try? fm.removeItem(at: output)
            errLock.lock()
            let detail = String(data: errTail, encoding: .utf8)?
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .suffix(1)
                .joined() ?? ""
            errLock.unlock()
            let code = Int(p.terminationStatus)
            let reason: String
            if code > 128 {
                // 被信号终止：ffmpeg 不会往 stderr 写任何东西，只能说清是哪种中断
                reason = "处理被系统中断了（通常是内存不够）。太长或太清晰的片子，"
                    + "先用剪辑工具剪到 10 分钟以内再导入"
            } else if detail.isEmpty {
                reason = "视频处理失败（源文件可能不受支持）"
            } else {
                reason = "视频处理失败：\(detail)"
            }
            throw NSError(domain: "Transcoder", code: code,
                          userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    /// 一步到位：优化并放进壁纸库，返回新文件
    func importVideo(source: URL, into libraryDir: URL) throws -> URL {
        guard let info = Self.probe(source) else {
            throw NSError(domain: "Transcoder", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                            "读不出这个视频的信息。只认 mp4 / mov / m4v 三种外壳，"
                            + "文件也可能是坏的、没下载完，或者还在 iCloud 里没落到本地"])
        }
        onStage?("读取视频信息…")
        let size = Self.targetSize(for: info)

        var name = source.deletingPathExtension().lastPathComponent
        name = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "壁纸" }
        var dest = libraryDir.appendingPathComponent(name + ".mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = libraryDir.appendingPathComponent("\(name) \(n).mp4")
            n += 1
        }

        let fps = Tuning.effectiveFPS(source: info.fps)

        // 片头介绍 / 片尾卡 / 画面角标：先都判一遍，再把中间的主体送去转码
        lastTrimmed = 0
        lastHeadTrimmed = 0
        lastWatermark = nil

        var tail = info.duration
        onStage?("检查片头片尾…")
        if let trim = detectEndCard(url: source, duration: info.duration) {
            tail = trim.end
            lastTrimmed = trim.removed
        }
        var head = 0.0
        if let h = detectHead(url: source, duration: tail) {
            head = h
            lastHeadTrimmed = h
        }
        // 两头都剪完至少要剩 3 秒，不然宁可留着片头
        if tail - head < 3.0 {
            head = 0
            lastHeadTrimmed = 0
        }
        // 「最长片段」：自动裁头尾之后再做一次上限截断
        if Tuning.maxDuration > 0, tail - head > Tuning.maxDuration {
            tail = head + Tuning.maxDuration
        }
        var notes: [String] = []
        if lastHeadTrimmed > 0 { notes.append(String(format: "片头 %.1f 秒", lastHeadTrimmed)) }
        if lastTrimmed > 0 { notes.append(String(format: "片尾 %.1f 秒", lastTrimmed)) }
        if !notes.isEmpty {
            onStage?("已裁掉" + notes.joined(separator: "、") + "，只留主体")
        }

        onStage?("检查画面里的角标…")
        if let wm = detectWatermark(url: source, from: head, to: tail, target: size) {
            lastWatermark = wm
            onStage?("已抹掉\(wm.corner)的角标")
        }

        onStage?("优化中（\(size.w)×\(size.h)，\(fps) fps，去跳帧 + 首尾淡化）…")
        try transcode(input: source, output: dest, info: info, size: size,
                      start: head, end: tail, watermark: lastWatermark)
        onStage?("生成缩略图…")
        _ = Thumbs.image(for: dest)
        return dest
    }
}
