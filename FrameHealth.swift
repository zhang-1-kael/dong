import Cocoa
import AVFoundation

/// 「画面卡住」的现场取证。
///
/// 视频画面是由主线程提交给合成器的：主线程被占住，那一帧就上不了屏，
/// 表现出来正是「画面停住 100ms，然后一下跳到后面」。
/// 所以这里只盯两件事，成本几乎为零：
///
///   1. 主线程看门狗：RunLoop 每次进入休眠前记一次时间，两次之间超过 40ms
///      就算一次卡顿，记下次数、最久一次、累计时长。
///   2. 播放器探针：解码跟不上时 `AVPlayerItem` 会发 `PlaybackStalled`，
///      单独记一笔，用来区分「主线程挡住画面」和「解码供不上帧」。
///
/// 每分钟往 `Application Support/VideoWallpaper/diag.log` 追加一行数字。
/// 只写尺寸、次数、毫秒，**不写壁纸文件名、不写路径**。
final class FrameHealth {

    static let shared = FrameHealth()

    // MARK: 可调阈值

    /// 超过这个时长才算「卡」。一帧 30fps 是 33ms，40ms 已经意味着至少丢了一帧
    private let stallThreshold: Double = 40
    /// 每分钟落一行
    private let flushInterval: TimeInterval = 60
    /// 日志上限，超了砍掉前半
    private let logLimit = 128 * 1024

    // MARK: 状态

    private var observer: CFRunLoopObserver?
    /// 上一次「进入休眠前」的时刻；卡顿 = 两次之间的**醒着**时间
    private var lastBeforeWaiting: CFAbsoluteTime = 0
    /// 本次被唤醒的时刻，用来把休眠时长从计算里剔掉
    private var wakeTime: CFAbsoluteTime = 0
    private var timer: Timer?
    private var started = false

    private var stallCount = 0
    private var stallWorst: Double = 0
    private var stallTotal: Double = 0
    /// 本次会话里每一次卡顿的毫秒数（只留最近 300 条，够看分布）
    private var recent: [Double] = []

    private var playerStalls = 0
    private var playerFailures = 0
    private var loops = 0

    /// 最近几笔「哪段代码花了多久」，用来把卡顿归到具体动作上
    private var notes: [String] = []

    private weak var player: AVPlayer?
    private var itemObservers: [NSObjectProtocol] = []

    /// 现场信息，随日志一起写，方便判断是不是某类素材/某块屏才出问题
    private var sourceSize: CGSize = .zero
    private var planText = "?"
    private var screenText = "?"
    private var sessionStart = Date()

    private var logURL: URL {
        Source.libraryDir.deletingLastPathComponent().appendingPathComponent("diag.log")
    }

    private var verbose: Bool {
        ProcessInfo.processInfo.environment["VW_DIAG"] != nil
    }

    /// 素材尺寸优先用重建时传进来的；刚导入的文件那时还没读到，
    /// 就退回播放器已经就绪的 presentationSize，别让日志里全是 0x0
    private var context: String {
        var w = sourceSize.width
        var h = sourceSize.height
        if w < 1 || h < 1, let ps = player?.currentItem?.presentationSize, ps.width > 0 {
            w = ps.width
            h = ps.height
        }
        return String(format: "source=%.0fx%.0f screen=%@ plan=%@", w, h, screenText, planText)
    }

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true
        sessionStart = Date()

        // 主线程看门狗。
        //
        // 注意：不能直接量两次「准备休眠」之间的间隔 —— 主线程没事干的时候会
        // 一直睡在 mach_msg 里，那段时间是空闲，不是卡顿（我第一版就是这么错的，
        // 一分钟能报出 58 秒「卡顿」）。真正要量的是**醒着的那一段**：
        //   醒来(afterWaiting) → 处理事件 → 准备休眠(beforeWaiting)
        // 这一段超过阈值，才说明主线程被占住了、合成提交被拖住了。
        let obs = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue
                | CFRunLoopActivity.afterWaiting.rawValue
                | CFRunLoopActivity.exit.rawValue,
            true, 0
        ) { [weak self] _, activity in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()

            if activity == .afterWaiting {
                self.wakeTime = now
                return
            }
            // beforeWaiting 或 exit：算出这一轮醒着干了多久
            let start = max(self.wakeTime, self.lastBeforeWaiting)
            self.lastBeforeWaiting = now
            guard start > 0 else { return }
            let busy = (now - start) * 1000
            guard busy >= self.stallThreshold else { return }
            self.stallCount += 1
            self.stallTotal += busy
            if busy > self.stallWorst { self.stallWorst = busy }
            self.recent.append(busy)
            if self.recent.count > 300 { self.recent.removeFirst(self.recent.count - 300) }
        }
        if let obs {
            CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
            observer = obs
        }

        let t = Timer(timeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.flush()
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t

        flush("start")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
        unbind()
        started = false
    }

    // MARK: - 绑定播放器

    func bind(player: AVPlayer, source: CGSize, plan: RenderPlan) {
        unbind()
        self.player = player
        playerStalls = 0
        playerFailures = 0
        loops = 0

        let screen = NSScreen.main?.frame.size ?? .zero
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        sourceSize = source
        planText = plan.load.rawValue
        screenText = String(format: "%.0fx%.0f@%.0f", screen.width, screen.height, scale)

        let c = NotificationCenter.default
        if let item = player.currentItem {
            itemObservers.append(c.addObserver(
                forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
            ) { [weak self] _ in
                self?.playerStalls += 1
                self?.beatNote("stalled")
            })
            itemObservers.append(c.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.playerFailures += 1
                self?.beatNote("failed")
            })
            itemObservers.append(c.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.loops += 1
            })
        }
        // 换壁纸的时候也留一行：以后能对着日志看「哪次换完开始卡」。
        // 延后 3 秒再写，等 item 就绪，尺寸才不是 0x0
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.flush("bind")
        }
    }

    func unbind() {
        let c = NotificationCenter.default
        for o in itemObservers { c.removeObserver(o) }
        itemObservers = []
        player = nil
    }

    private func beatNote(_ what: String) {
        if verbose { print("[health] \(what)") }
    }

    /// 量一段主线程工作。超过 20ms 就记一笔，日志里能直接看到是哪一段。
    /// 只用在会走 IO / 解析 / 建图层的少数几处，免得自己变成开销。
    func measure<T>(_ name: String, _ body: () -> T) -> T {
        let t = CFAbsoluteTimeGetCurrent()
        let result = body()
        let ms = (CFAbsoluteTimeGetCurrent() - t) * 1000
        if ms >= 20 {
            let s = String(format: "%@=%.0fms", name, ms)
            notes.append(s)
            if notes.count > 12 { notes.removeFirst(notes.count - 12) }
            if verbose { print("[health] slow \(s)") }
        }
        return result
    }

    // MARK: - 落盘

    private func flush(_ tag: String = "tick") {
        let mins = Int(Date().timeIntervalSince(sessionStart) / 60)
        var line = String(
            format: "%@ #%@ up=%dm stall=%d worst=%.0fms sum=%.1fs play_stall=%d failed=%d loops=%d %@",
            stamp(), tag, mins,
            stallCount, stallWorst, stallTotal / 1000,
            playerStalls, playerFailures, loops, context
        )
        if tag != "bind", !notes.isEmpty {
            line += " slow=[" + notes.joined(separator: ",") + "]"
            notes.removeAll()
        }
        if verbose { print("[health] " + line) }
        append(line)
        // 每小时清零，日志里就是「每一小时一段」的干净数据
        if mins > 0, mins % 60 == 0, tag == "tick" {
            stallCount = 0; stallWorst = 0; stallTotal = 0; recent.removeAll()
            playerStalls = 0; playerFailures = 0
        }
    }

    private func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    private func append(_ line: String) {
        // 落盘一律到后台：诊断本身绝不能在主线程上做 IO，
        // 否则它自己就成了「卡顿」的新来源
        DispatchQueue.global(qos: .utility).async {
            let url = self.logURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > self.logLimit {
                // 只保留后半段，避免无限长
                if let all = try? String(contentsOf: url, encoding: .utf8) {
                    let lines = all.split(separator: "\n", omittingEmptySubsequences: false)
                    let keep = lines.suffix(lines.count / 2).joined(separator: "\n")
                    try? keep.write(to: url, atomically: false, encoding: .utf8)
                }
            }
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    // MARK: - 给人看的一段话

    /// 复制到剪贴板的那段：前几行是结论，后面跟着最近几行原始日志
    func summary() -> String {
        var s = ""
        s += "Dòng \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")"
        s += "  build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")\n"
        s += "系统 \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        s += "现场 \(context)\n"
        let mins = Int(Date().timeIntervalSince(sessionStart) / 60)
        s += "本次运行 \(mins) 分钟\n"
        if stallCount == 0 {
            s += "主线程卡顿（≥40ms）：0 次\n"
        } else {
            let rate = Double(stallCount) / max(Double(mins), 1.0)
            s += String(format: "主线程卡顿（≥40ms）：%d 次，最久 %.0fms，累计 %.1fs，约 %.1f 次/分钟\n",
                        stallCount, stallWorst, stallTotal / 1000, rate)
        }
        s += "播放器解码停顿：\(playerStalls) 次  失败：\(playerFailures) 次  循环：\(loops) 次\n"
        if !recent.isEmpty {
            let sorted = recent.sorted()
            let p50 = sorted[sorted.count / 2]
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            s += String(format: "卡顿分布 p50 %.0fms  p95 %.0fms\n", p50, p95)
        }
        if !notes.isEmpty {
            s += "慢操作：" + notes.joined(separator: "  ") + "\n"
        }
        s += "\n最近日志：\n"
        if let all = try? String(contentsOf: logURL, encoding: .utf8) {
            s += all.split(separator: "\n").suffix(8).joined(separator: "\n")
        } else {
            s += "（还没有日志）"
        }
        return s
    }

    func copySummary() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(summary(), forType: .string)
    }

    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    var logPath: String { logURL.path }
}
