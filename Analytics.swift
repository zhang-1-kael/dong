import Foundation

/// 云服务地址。
///
/// 文档里的 `<SERVER_BASE_URL>`，**部署后要填真实域名**。三个来源，优先级从高到低：
///   1. 环境变量 `VW_API_BASE`（本地联调用）
///   2. Info.plist 里的 `ApiBaseURL`（打包时注入，改这个不用重编译）
///   3. 都没有 → 视为「未配置」，**一条请求都不发**（绝不往猜的域名上报）
enum Api {
    static let base: URL = {
        if let s = ProcessInfo.processInfo.environment["VW_API_BASE"],
           let u = URL(string: s) { return u }
        if let s = Bundle.main.infoDictionary?["ApiBaseURL"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !t.contains("REPLACE-ME"), let u = URL(string: t) { return u }
        }
        return URL(string: "https://REPLACE-ME.invalid")!
    }()

    /// 域名没配好就别发请求：宁可不上报，也不能报错地方
    static var isConfigured: Bool {
        !(base.host ?? "").lowercased().contains("replace-me")
    }

    /// base + path。别用 URL(string:relativeTo:)：那样拿到的是相对 URL，
    /// 一旦交给 URLComponents(resolvingAgainstBaseURL: false) 就会把 host 丢掉。
    static func path(_ p: String) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: true) ?? URLComponents()
        c.path = p.hasPrefix("/") ? p : "/" + p
        return c.url ?? base
    }
}

/// 匿名使用统计。
///
/// 口径完全按《云服务接入文档》模块二：
///   • 只回答「有多少人在用、用了什么、成没成」，**不记录内容**：
///     文件名、目录路径、链接原文、视频标题一个字都不上传。
///   • `install_id` 是首次启动随机生成的 UUID，只存在本机，卸载即消失，无法对应真实身份。
///   • 设置里可彻底关闭：关掉即删除 install-id、清空队列、不再发任何请求。
///
/// 红线（写在这里防止以后被"顺手"加上）：
///   壁纸文件名 / 路径 / 库清单、链接原文与标题、画面与截图、剪贴板、
///   键鼠输入、用户名 / 序列号 / 硬件 UUID、Apple ID / 邮箱 / 手机号、
///   精确 IP / 地理位置 / 时区、IDFA —— 一律不上报。
final class Analytics {

    static let shared = Analytics()

    private let fm = FileManager.default
    private let dir: URL
    private let idFile: URL
    private let queueFile: URL

    /// 队列上限 500 条，满了丢最旧的（文档 §2.6-1）
    private let maxQueue = 500
    /// 单批上限（服务端上限 500，这里保守取 100）
    private let batchSize = 100

    private let lock = NSLock()
    private var pending: [[String: Any]] = []
    private var sending = false
    private var started = false
    private var sessionStart = Date()
    private var timer: Timer?

    /// 失败退避：30s → 1min → 2min → 5min，封顶 30min（文档 §2.3）
    private let backoffSteps: [TimeInterval] = [30, 60, 120, 300, 1800]
    private var backoffIndex = 0
    private var nextAttempt = Date.distantPast

    private static let keyEnabled = "analyticsEnabled"
    private static let keyLaunches = "analyticsLaunches"

    /// 文档 §2.4 的 16 个点位。客户端先自检一遍，别把服务端注定要拒的事件发上去。
    private static let whitelist: Set<String> = [
        "app_launch", "app_quit",
        "wallpaper_enable", "wallpaper_disable", "wallpaper_pause", "wallpaper_resume",
        "wallpaper_switch", "wallpaper_delete",
        "import_local", "import_link", "import_cancel",
        "lock_screen_toggle", "autostart_toggle", "loop_toggle",
        "panel_open", "analytics_toggle",
    ]

    private init() {
        let base = Source.libraryDir.deletingLastPathComponent().appendingPathComponent("analytics")
        dir = base
        idFile = base.appendingPathComponent("install-id")
        queueFile = base.appendingPathComponent("queue.jsonl")
    }

    // MARK: 开关

    /// 默认开启：只有用户明确关过才是关闭状态
    var isEnabled: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: Self.keyEnabled) == nil { return true }
            return d.bool(forKey: Self.keyEnabled)
        }
        set { setEnabled(newValue) }
    }

    /// 设置面板里的开关走这里：**先**记一条 analytics_toggle 并尽量发出去，再真正停掉。
    func setEnabled(_ on: Bool) {
        let was = isEnabled
        guard was != on else { return }
        if on == false {
            // 关到 OFF 之前先上报一条（文档 §2.4.5），发完再停
            track("analytics_toggle", ["on": false])
        }
        UserDefaults.standard.set(on, forKey: Self.keyEnabled)
        if on {
            start()
            track("analytics_toggle", ["on": true])
            flush(force: true)
        } else {
            flush(force: true, wait: true)
            stopAndWipe()
        }
    }

    // MARK: 生命周期

    /// 截图 / 菜单转储 / 导入测试这些自动化跑法不算真实使用，别污染统计
    private static var isAutomationRun: Bool {
        let keys = ["VW_PANEL_SHOT", "VW_DUMP_MENU", "VW_SNAPSHOT", "VW_PRESETS_TEST",
                    "VW_NO_ANALYTICS", "VW_GALLERY_DEBUG", "VW_IMPORT_TEST",
                    "VW_SWAY_DUMP", "VW_SWAY_TEST", "VW_ANALYTICS_TEST"]
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

        // first 的口径：install-id 文件不存在 = 这台机器第一次跑（文档 §2.5）
        let first = !fm.fileExists(atPath: idFile.path)
        _ = installID()

        let n = UserDefaults.standard.integer(forKey: Self.keyLaunches) + 1
        UserDefaults.standard.set(n, forKey: Self.keyLaunches)

        sessionStart = Date()

        if FakeProbe.active {
            // 探针测试包：只发一批定死的假数据（每台机器一次），真打点全部禁用（见 track()）
            injectProbeIfNeeded()
        } else {
            track("app_launch", ["first": first, "n": n])
            flush(force: true)
        }

        // 30 秒一拍：到点、有货、且不在退避窗口里才真正发
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.flush(force: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 退出前调：记一次时长并把剩下的推上去（最多等 3 秒，绝不拖住退出）
    func finish() {
        guard isEnabled, started else { return }
        let secs = Int(Date().timeIntervalSince(sessionStart))
        track("app_quit", ["sec": max(0, secs)])
        flush(force: true, wait: true)
        timer?.invalidate()
        timer = nil
    }

    // MARK: 打点

    func track(_ event: String, _ props: [String: Any] = [:]) {
        guard isEnabled, started, !FakeProbe.active, Self.whitelist.contains(event) else { return }
        var row: [String: Any] = [
            "install_id": installID(),
            "event": event,
            "props": props,
            "app_version": Self.appVersion,
            "os_version": Self.osVersion,
            "arch": Self.arch,
            "locale": Self.language,
            "client_ts": Self.isoNow,
        ]
        if row["props"] as? [String: Any] == nil { row["props"] = [:] }
        // props 序列化后要 ≤4096 字节（文档 §2.2）
        if let d = try? JSONSerialization.data(withJSONObject: row["props"] as Any), d.count > 4096 {
            row["props"] = [:]
        }

        lock.lock()
        pending.append(row)
        if pending.count > maxQueue { pending.removeFirst(pending.count - maxQueue) }
        let shouldGo = pending.count >= 20
        lock.unlock()

        persist()
        if shouldGo { flush(force: true) }
    }

    // MARK: 上报

    private func flush(force: Bool, wait: Bool = false) {
        // 没配服务器地址就只在本地攒着，什么也不发
        guard isEnabled, Api.isConfigured else { return }

        lock.lock()
        if sending || pending.isEmpty {
            lock.unlock()
            return
        }
        if !force, Date() < nextAttempt {
            lock.unlock()
            return
        }
        sending = true
        let batch = Array(pending.prefix(batchSize))
        lock.unlock()

        // source 固定 "app"（"site" 是官网前端专用）
        let body: [String: Any] = ["source": "app", "events": batch]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            lock.lock(); sending = false; lock.unlock()
            return
        }

        var req = URLRequest(url: Api.path("/api/collect"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = wait ? 3 : 15

        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: req) { [weak self] respData, resp, _ in
            guard let self else { sem.signal(); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200..<300).contains(code)

            self.lock.lock()
            if ok {
                // 200 就是"已处理"：accepted 入库、rejected 由服务端丢弃（白名单错重试也不会成功）。
                // 两种情况都不再重发，所以整批从队里移除。
                let sent = batch.count
                if self.pending.count >= sent { self.pending.removeFirst(sent) }
                self.backoffIndex = 0
                self.nextAttempt = .distantPast
            } else {
                // 网络失败 / 5xx：整批留着，等下次退避重试
                let step = min(self.backoffIndex, self.backoffSteps.count - 1)
                self.nextAttempt = Date().addingTimeInterval(self.backoffSteps[step])
                self.backoffIndex = min(self.backoffIndex + 1, self.backoffSteps.count - 1)
            }
            self.sending = false
            self.lock.unlock()

            if ok {
                self.persist()
                if ProcessInfo.processInfo.environment["VW_ANALYTICS_DEBUG"] != nil,
                   let d = respData,
                   let s = String(data: d, encoding: .utf8) {
                    print("[analytics] collect \(code) sent=\(batch.count) resp=\(s)")
                }
            }
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

    /// 启动时如果用户早就关掉了统计，把上一版可能残留的队列 / ID 一起清掉
    /// （老版本升级上来、或者是被别处改过 UserDefaults 的情况）
    func wipeIfDisabled() {
        guard !isEnabled else { return }
        lock.lock()
        pending.removeAll()
        lock.unlock()
        try? fm.removeItem(at: queueFile)
        try? fm.removeItem(at: idFile)
    }

    /// 关闭统计：清队列 + 删 install-id（下回打开会重新生成新 ID）
    private func stopAndWipe() {
        lock.lock()
        started = false
        pending.removeAll()
        lock.unlock()
        timer?.invalidate()
        timer = nil
        try? fm.removeItem(at: queueFile)
        try? fm.removeItem(at: idFile)
    }

    /// 首次调用时生成，之后一直用同一个
    @discardableResult
    private func installID() -> String {
        if let s = try? String(contentsOf: idFile, encoding: .utf8) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 8 { return t }
        }
        let s = UUID().uuidString
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? s.write(to: idFile, atomically: true, encoding: .utf8)
        return s
    }

    // MARK: 事件参数的小工具（只传档位 / 枚举，不传原值）

    /// 时长分档：<10s / 10-60s / 1-5min / 5-30min / >30min
    static func durBucket(_ seconds: Double) -> String {
        if seconds <= 0 { return "<10s" }
        if seconds < 10 { return "<10s" }
        if seconds < 60 { return "10-60s" }
        if seconds < 300 { return "1-5min" }
        if seconds < 1800 { return "5-30min" }
        return ">30min"
    }

    /// 体积分档：<50MB / 50-200MB / 200MB-1GB / >1GB
    static func sizeBucket(_ bytes: Int) -> String {
        let mb = Double(max(bytes, 0)) / 1_048_576
        if mb < 50 { return "<50MB" }
        if mb < 200 { return "50-200MB" }
        if mb < 1024 { return "200MB-1GB" }
        return ">1GB"
    }

    /// 错误码只允许这 6 个（文档 §2.4.3）——**禁止**把 ffmpeg 原始报错文本带上去，里面有文件路径
    static func errCode(_ error: Error) -> String {
        if let f = error as? Downloader.Failure {
            // 抓不到文件多半是链接内容不支持（直播 / 付费 / 需要登录）
            return f.message.contains("没下到可用的视频文件") ? "unsupported" : "network"
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain,
           ns.code == NSFileWriteOutOfSpaceError { return "disk_full" }
        if ns.domain == NSURLErrorDomain {
            return ns.code == NSURLErrorTimedOut ? "timeout" : "network"
        }
        if ns.domain == "Transcoder" {
            return ns.code == 2 ? "probe_failed" : "ffmpeg_failed"
        }
        let text = ns.localizedDescription
        if text.contains("space") || text.contains("磁盘") || text.contains("空间") { return "disk_full" }
        return "ffmpeg_failed"
    }

    /// 链接来源（只记站名，不记链接原文）
    static func provider(for link: String) -> String {
        guard let host = URL(string: link)?.host?.lowercased() ?? URL(string: link)?.absoluteString else {
            return "other"
        }
        if host.contains("bilibili") || host.contains("b23.tv") { return "bilibili" }
        if host.contains("youtube") || host.contains("youtu.be") { return "youtube" }
        return "other"
    }

    // MARK: 环境信息（都不涉及个人）

    // 探针假数据（FakeProbeBuilder，同文件）取环境字段用的别名
    static var appVersionForProbe: String { appVersion }
    static var osVersionForProbe: String { osVersion }
    static var archForProbe: String { arch }
    static var localeForProbe: String { language }

    private static var appVersion: String {
        let d = Bundle.main.infoDictionary
        let short = d?["CFBundleShortVersionString"] as? String ?? "0"
        let build = d?["CFBundleVersion"] as? String ?? "0"
        return "\(short)(\(build))"
    }

    /// 只要主次版本，不含补丁号
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

    /// 只要语言，不要地区（zh-Hans → zh）
    private static var language: String {
        var raw: String
        if #available(macOS 13, *) {
            raw = Locale.current.language.languageCode?.identifier ?? "unknown"
        } else {
            raw = Locale.current.languageCode ?? "unknown"
        }
        if let dash = raw.firstIndex(of: "-") { raw = String(raw[..<dash]) }
        return String(raw.prefix(16))
    }

    private static var isoNow: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

// MARK: - 探针假数据（⚠️ 3.26 build 48 测试包专用，发正式版前必须整段删除）

/// 用途：核对看板统计是不是真数——App 启动时往 /api/collect 发**一批定死的假数据**，
/// 每台机器只发一次（哨兵文件），之后真打点全部禁用（track() 有 guard）。
/// 假数据的完整清单见《探针版假数据清单.md》：100 个假设备 × 每种事件各 1 条 = 1600 条，
/// 看板上每个指标应该精确显示 100（装机 100、活跃 100、每种事件 100）。
/// 所有假 install_id 都带 "probe-" 前缀，一眼就能跟真实用户分开。
enum FakeProbe {
    /// 3.26 探针测试包用完已关闭：3.27 起恢复正常真实统计。
    /// （探针代码保留，将来要做数据核对时改回 true 再打包一个测试版即可）
    static let active = false

    /// 第 n 个假 install_id（n = 1…100）
    static func id(_ n: Int) -> String {
        String(format: "probe-%03d-20261109", n)
    }
}

extension Analytics {

    /// 哨兵放在数据目录 analytics/ 下（跟 install-id 同目录）：
    /// 本机只发一次；换机器、重装、删数据目录会重新发，正好符合"一台机器一条装机"的口径。
    private var probeSentFile: URL {
        dir.appendingPathComponent("probe-sent-48.flag")
    }

    fileprivate func injectProbeIfNeeded() {
        guard FakeProbe.active else { return }
        if fm.fileExists(atPath: probeSentFile.path) { return }
        // 清掉本地残留队列：保证这批发出去之后，看板上的数字恰好只多"清单"里那些
        lock.lock(); pending = FakeProbeBuilder.rows(); lock.unlock()
        persist()
        try? "sent".write(to: probeSentFile, atomically: true, encoding: .utf8)
        // 1600 条 > 单批 100：后台线程一批一批发，直到队列清空；
        // 中途断网/失败的批次留在队列里，交给 30 秒定时器按退避续传。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var turns = 0
            while turns < 40 {
                guard let self else { return }
                self.lock.lock(); let left = self.pending.count; self.lock.unlock()
                if left == 0 { return }
                self.flush(force: true, wait: true)
                turns += 1
            }
        }
    }
}

/// 探针假数据的拼装。props 字段名跟真实打点（main.swift trackImport 等）完全一致，
/// 服务端没法靠格式区分真假——只能靠 install_id 前缀和事件数对账。
private enum FakeProbeBuilder {

    /// 100 个假设备 × 16 种事件各 1 条 = 1600 条，每种事件的看板计数都是 100。
    /// props 里能取整的数字也全用 100（sec / ms / lib_n），风格统一好认。
    static func rows() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for n in 1...100 {
            let id = FakeProbe.id(n)
            rows.append(row(id, "app_launch", ["first": true, "n": 1]))
            rows.append(row(id, "app_quit", ["sec": 100]))
            rows.append(row(id, "wallpaper_enable", ["on": true]))
            rows.append(row(id, "wallpaper_disable", ["on": false]))
            rows.append(row(id, "wallpaper_pause", [:]))
            rows.append(row(id, "wallpaper_resume", [:]))
            rows.append(row(id, "wallpaper_switch", ["via": "library", "lib_n": 100]))
            rows.append(row(id, "wallpaper_delete", ["lib_n": 100]))
            rows.append(row(id, "import_local",
                            ["ok": true, "ms": 100, "dur_bucket": "1-5min", "size_bucket": "50-200MB"]))
            rows.append(row(id, "import_link", ["provider": "bilibili", "ok": true, "ms": 100]))
            rows.append(row(id, "import_cancel", [:]))
            rows.append(row(id, "lock_screen_toggle", ["on": true]))
            rows.append(row(id, "autostart_toggle", ["on": true]))
            rows.append(row(id, "loop_toggle", ["on": true]))
            rows.append(row(id, "panel_open", [:]))
            rows.append(row(id, "analytics_toggle", ["on": true]))
        }
        return rows
    }

    /// 单条事件。client_ts 往回排 seq 秒（只回看最近 10 分钟，(seq % 600)），
    /// 这样"今日"窗口一定能框住整批数据。
    private static func row(_ id: String, _ event: String,
                            _ props: [String: Any], _ seq: Int = 0) -> [String: Any] {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let ts = f.string(from: Date().addingTimeInterval(Double(seq % 600) * -1))
        return ["install_id": id, "event": event, "props": props,
                "app_version": Analytics.appVersionForProbe,
                "os_version": Analytics.osVersionForProbe,
                "arch": Analytics.archForProbe,
                "locale": Analytics.localeForProbe,
                "client_ts": ts]
    }
}
