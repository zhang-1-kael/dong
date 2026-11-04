import Foundation

/// 匿名使用统计。
///
/// 只记「有多少台机器在用、点了哪个功能、成功还是失败」——
/// 不上传文件名、目录路径、链接内容、壁纸画面，也不上传任何可以指回个人的东西。
/// 设备标识是首次启动随机生成的一串 UUID，只存在本机，卸载即消失。
///
/// 首次启动默认打开；设置里可以关。关掉之后本地队列清空，不再发任何请求。
final class Analytics {

    static let shared = Analytics()

    /// 收集端：官网那台服务器上的 /api/collect
    private let collectURL = URL(string: "https://video-wallpaper.app.workbuddy.host/api/collect")!
    private let fm = FileManager.default
    private let dir: URL
    private let idFile: URL
    private let queueFile: URL

    /// 队列上限：攒到这么多就先丢最旧的，避免离线久了无限涨
    private let maxQueue = 500
    /// 一次最多发这么多条
    private let batchSize = 60

    private let lock = NSLock()
    private var pending: [[String: Any]] = []
    private var sending = false
    private var started = false
    private var sessionStart = Date()
    private var lastFlush = Date.distantPast
    private var timer: Timer?

    private static let keyEnabled = "analyticsEnabled"
    private static let keyLaunches = "analyticsLaunches"

    private init() {
        let base = Source.libraryDir.deletingLastPathComponent().appendingPathComponent("analytics")
        dir = base
        idFile = base.appendingPathComponent("install-id")
        queueFile = base.appendingPathComponent("queue.jsonl")
    }

    // MARK: 开关

    /// 默认打开：只有用户明确关过才是关闭状态
    var isEnabled: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: Self.keyEnabled) == nil { return true }
            return d.bool(forKey: Self.keyEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.keyEnabled)
            if newValue {
                start()
            } else {
                stopAndWipe()
            }
        }
    }

    // MARK: 生命周期

    /// 截图 / 菜单转储 / 导入测试这些自动化跑法不算真实使用，别污染统计
    private static var isAutomationRun: Bool {
        let keys = ["VW_PANEL_SHOT", "VW_DUMP_MENU", "VW_SNAPSHOT", "VW_PRESETS_TEST",
                    "VW_NO_ANALYTICS", "VW_GALLERY_DEBUG"]
        return keys.contains { ProcessInfo.processInfo.environment[$0] != nil }
    }

    /// 主流程启动时调一次（命令行模式不要调）
    func start() {
        guard isEnabled, !Self.isAutomationRun else { return }
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        loadQueue()

        let n = UserDefaults.standard.integer(forKey: Self.keyLaunches) + 1
        UserDefaults.standard.set(n, forKey: Self.keyLaunches)

        sessionStart = Date()
        track("app_launch", ["first": n == 1, "n": n])
        flush(force: true)

        // 每 60 秒把攒下的事件推一次；没有事件就什么也不做
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.flush(force: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 退出前调：记一次时长并把剩下的推上去（最多等 3 秒，绝不拖住退出）
    func finish() {
        guard isEnabled, started else { return }
        let secs = Int(Date().timeIntervalSince(sessionStart))
        track("app_quit", ["sec": secs])
        flush(force: true, wait: true)
        timer?.invalidate()
        timer = nil
    }

    // MARK: 打点

    func track(_ event: String, _ props: [String: Any] = [:]) {
        guard isEnabled, started else { return }
        var row: [String: Any] = [
            "install_id": installID(),
            "event": event,
            "props": props,
            "app_version": Self.appVersion,
            "os_version": Self.osVersion,
            "arch": Self.arch,
            "locale": Self.language,
            "event_day": Self.today,
            "client_ts": Self.isoNow,
        ]
        if row["props"] as? [String: Any] == nil { row["props"] = [:] }

        lock.lock()
        pending.append(row)
        if pending.count > maxQueue { pending.removeFirst(pending.count - maxQueue) }
        let shouldGo = pending.count >= 12 && Date().timeIntervalSince(lastFlush) > 20
        lock.unlock()

        persist()
        if shouldGo { flush(force: false) }
    }

    // MARK: 上报

    private func flush(force: Bool, wait: Bool = false) {
        guard isEnabled else { return }

        lock.lock()
        if sending || pending.isEmpty {
            lock.unlock()
            return
        }
        if !force && Date().timeIntervalSince(lastFlush) < 20 {
            lock.unlock()
            return
        }
        sending = true
        lastFlush = Date()
        let batch = Array(pending.prefix(batchSize))
        lock.unlock()

        let body: [String: Any] = ["events": batch]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            lock.lock(); sending = false; lock.unlock()
            return
        }

        var req = URLRequest(url: collectURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = wait ? 3 : 10

        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            guard let self else { sem.signal(); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            self.lock.lock()
            if (200..<300).contains(code) {
                // 只删掉确实发出去的那一段；期间新加的留在队里
                let sent = batch.count
                if self.pending.count >= sent { self.pending.removeFirst(sent) }
            }
            self.sending = false
            self.lock.unlock()
            if (200..<300).contains(code) { self.persist() }
            sem.signal()
        }
        task.resume()
        if wait { _ = sem.wait(timeout: .now() + 3) }
    }

    // MARK: 本地存储

    private func loadQueue() {
        guard let text = try? String(contentsOf: queueFile, encoding: .utf8) else { return }
        var rows: [[String: Any]] = []
        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            rows.append(o)
        }
        lock.lock()
        pending = Array(rows.suffix(maxQueue))
        lock.unlock()
    }

    private func persist() {
        lock.lock()
        let rows = pending
        lock.unlock()
        let lines = rows.compactMap { r -> String? in
            guard let d = try? JSONSerialization.data(withJSONObject: r) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        try? lines.joined(separator: "\n").write(to: queueFile, atomically: true, encoding: .utf8)
    }

    private func stopAndWipe() {
        lock.lock()
        started = false
        pending.removeAll()
        lock.unlock()
        timer?.invalidate()
        timer = nil
        try? fm.removeItem(at: queueFile)
    }

    /// 首次调用时生成，之后一直用同一个
    private func installID() -> String {
        if let s = try? String(contentsOf: idFile, encoding: .utf8), s.count >= 8 {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let s = UUID().uuidString
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? s.write(to: idFile, atomically: true, encoding: .utf8)
        return s
    }

    // MARK: 环境信息（都不涉及个人）

    private static var appVersion: String {
        let d = Bundle.main.infoDictionary
        let short = d?["CFBundleShortVersionString"] as? String ?? "0"
        let build = d?["CFBundleVersion"] as? String ?? "0"
        return "\(short)(\(build))"
    }

    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// 只要语言，不要地区（zh-Hans / en）
    private static var language: String {
        if #available(macOS 13, *) {
            return Locale.current.language.languageCode?.identifier ?? "unknown"
        }
        return Locale.current.languageCode ?? "unknown"
    }

    private static var today: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static var isoNow: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
