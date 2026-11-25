import Foundation

/// 同步中枢：谁在触发、什么时候跑、跑完通知谁。
///
/// 触发点三个：
///   1. 启动时已登录 → 立刻跑一次（换设备打开就能看到自己的壁纸）
///   2. 壁纸库目录有变化（导入、删除、重命名）→ 4 秒防抖后跑
///   3. 设置里手动点「立即同步」
///
/// 自己下载/删除文件也会触发目录监听，所以执行期间挂 `suppressWatch`，
/// 免得同步完立刻又跑一轮。
final class SyncCenter {

    static let shared = SyncCenter()
    static let changed = Notification.Name("VWSyncChanged")
    /// 同步改动过本地库，界面需要重新读盘
    static let libraryDidChange = Notification.Name("VWSyncLibraryChanged")

    enum Status: Equatable {
        case signedOut
        case idle
        case syncing(String)
        case failed(String)
        case done(String)

        var text: String {
            switch self {
            case .signedOut: return "未登录"
            case .idle: return "已登录"
            case let .syncing(s): return s
            case let .failed(s): return s
            case let .done(s): return s
            }
        }

        var isBusy: Bool {
            if case .syncing = self { return true }
            return false
        }
    }

    private(set) var session: AccountSession? = AccountStore.load()
    private(set) var status: Status = .signedOut {
        didSet {
            guard status != oldValue else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: SyncCenter.changed, object: nil)
            }
        }
    }
    private(set) var lastReport: SyncEngine.Report?
    /// 昵称 / 头像（登录后拉一次，改完再拉）
    private(set) var profile: AccountAPI.Profile?
    private(set) var avatarData: Data?
    /// 当前这轮同步的进度（没在同步时为 nil）
    private(set) var progress: SyncEngine.Progress?
    /// 调试：只摆拍不联网（截「同步中」的界面时用）
    private var previewOnly = false
    /// 切换壁纸库归属期间不跑同步，否则会把「不该属于这个账号的本地壁纸」传上去
    private var isSwitchingLibrary = false
    /// 上一次是不是因为登录过期被打断（设置里据此提示「重新登录」）
    private(set) var lastExpired = false

    private let queue = DispatchQueue(label: "com.zhanghangshuo.dong.sync", qos: .utility)
    private var watcher: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    /// 同步自己改文件时不再触发监听
    private var suppressWatch = false

    var isLoggedIn: Bool { session != nil }

    private init() {
        // 调试用：VW_SYNC_FAKE=1 造一个假登录态，只活在内存里，不写钥匙串。
        // 用于无头环境截「已登录」状态的界面，不参与任何请求。
        if let fake = ProcessInfo.processInfo.environment["VW_SYNC_FAKE"] {
            let parts = fake.split(separator: "|", maxSplits: 2).map(String.init)
            session = AccountSession(email: parts.first ?? "demo@example.com",
                                     userId: "demo",
                                     token: parts.count > 1 ? parts[1] : "demo",
                                     quotaBytes: 2 * 1024 * 1024 * 1024)
            // 第三个字段是进度百分比：截「同步中」的界面用，纯展示，不发请求
            if parts.count > 2, let pct = Double(parts[2]) {
                previewOnly = true
                previewOnly = true
                var p = SyncEngine.Progress()
                p.text = "正在上传 · 🌬️"
                p.fraction = pct
                p.done = 7
                p.total = 22
                p.bytesDone = Int64(pct * 443 * 1024 * 1024)
                p.bytesTotal = 443 * 1024 * 1024
                progress = p
                status = .syncing(p.text)
                // 摆拍用：给编辑资料面板一点内容
                profile = AccountAPI.Profile(email: parts[0], displayName: "Kael", hasAvatar: false)
            }
        }
        // 摆拍模式下面已经在上面设成 .syncing 了，别再覆盖回 idle
        if !previewOnly {
            status = session == nil ? .signedOut : .idle
        }
    }

    // MARK: 账号

    func signIn(_ s: AccountSession) {
        session = s
        AccountStore.save(s)
        status = .idle
        watchLibrary()

        // 规则（用户 2026-11-25）：登录后只显示这个账号的壁纸；账号是空的才把本地并进去。
        // 必须先切库再同步，否则会把本地壁纸误传进别人的账号。
        isSwitchingLibrary = true
        let token = s.token
        let userId = s.userId
        queue.async { [weak self] in
            guard let self else { return }
            var empty = true
            if case let .success(m) = AccountAPI.manifest(token: token) {
                empty = m.items.filter { !$0.isDeleted }.isEmpty
            }
            DispatchQueue.main.async {
                let msg = LibraryOwner.activate(accountId: userId, remoteIsEmpty: empty)
                SyncEngine.log(Source.support, "切换壁纸库：\(msg)（cloudEmpty=\(empty)）")
                self.isSwitchingLibrary = false
                // 库换了，界面和桌面都要重读
                NotificationCenter.default.post(name: SyncCenter.libraryDidChange, object: nil)
                self.refreshProfile()
                self.syncNow()
            }
        }
    }

    func signOut() {
        if let s = session { AccountAPI.logout(token: s.token) }

        // 规则（用户 2026-11-25）：退出后这台机器不能再显示该账号的壁纸。
        isSwitchingLibrary = true
        let msg = LibraryOwner.restoreAnonymous()
        SyncEngine.log(Source.support, "退出登录：\(msg)")
        isSwitchingLibrary = false
        NotificationCenter.default.post(name: SyncCenter.libraryDidChange, object: nil)

        AccountStore.clear()
        session = nil
        profile = nil
        avatarData = nil
        status = .signedOut
        watcher?.cancel()
        watcher = nil
    }

    func refreshAccount(_ done: @escaping (Result<AccountAPI.Me, AccountError>) -> Void) {
        guard let s = session else { return }
        queue.async {
            let r = AccountAPI.me(token: s.token)
            DispatchQueue.main.async { done(r) }
        }
    }

    // MARK: 触发

    /// 启动时调用：已登录就跑一次
    /// 拉昵称和头像。面板打开、登录、改完资料后都调一次。
    func refreshProfile(done: (() -> Void)? = nil) {
        guard let s = session else { done?(); return }
        queue.async { [weak self] in
            guard let self else { return }
            var p: AccountAPI.Profile?
            if case let .success(v) = AccountAPI.profile(token: s.token) { p = v }
            var avatar: Data?
            if let p, p.hasAvatar, case let .success(d) = AccountAPI.avatarData(token: s.token) {
                avatar = d
            }
            DispatchQueue.main.async {
                self.profile = p
                self.avatarData = avatar
                NotificationCenter.default.post(name: SyncCenter.changed, object: nil)
                done?()
            }
        }
    }

    func startIfLoggedIn() {
        guard isLoggedIn, !previewOnly else { return }
        watchLibrary()
        refreshProfile()
        syncNow()
    }

    /// 库目录变化后的防抖同步
    func scheduleSync() {
        guard isLoggedIn, !isSwitchingLibrary else { return }
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.syncNow() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    func syncNow() {
        guard let s = session, !isSwitchingLibrary else { return }
        guard !status.isBusy else { return }
        status = .syncing("正在同步…")

        let lib = Source.libraryDir
        let support = Source.support
        let streams = WebStreams.load().map { (id: $0.id, name: $0.name, url: $0.url, addedAt: $0.addedAt) }

        queue.async { [weak self] in
            guard let self else { return }
            self.suppressWatch = true
            let result = SyncEngine.run(
                session: s,
                libraryDir: lib,
                support: support,
                webStreams: streams,
                addWebStream: { id, name, url in
                    var list = WebStreams.load()
                    if !list.contains(where: { $0.url == url }) {
                        list.append(WebStream(id: id, name: name, url: url, addedAt: Date()))
                        WebStreams.save(list)
                    }
                },
                removeWebStream: { id in WebStreams.remove(id: id) },
                progress: { p in
                    DispatchQueue.main.async {
                        self.progress = p
                        self.status = .syncing(p.text)
                    }
                })
            self.suppressWatch = false

            DispatchQueue.main.async {
                self.progress = nil
                switch result {
                case let .success(rep):
                    self.lastReport = rep
                    self.applyOrder(rep)
                    if rep.errors.isEmpty {
                        self.status = .done(rep.summary)
                        if rep.downloaded > 0 || rep.removed > 0 {
                            NotificationCenter.default.post(name: SyncCenter.libraryDidChange, object: nil)
                        }
                    } else {
                        self.status = .failed(rep.summary)
                        if rep.downloaded > 0 || rep.removed > 0 {
                            NotificationCenter.default.post(name: SyncCenter.libraryDidChange, object: nil)
                        }
                    }
                case let .failure(e):
                    if case let .http(code, _) = e, code == 401 {
                        // token 失效（改了密码 / 后台清掉了）：直接退回未登录，界面提示重新登录
                        AccountStore.clear()
                        self.session = nil
                        self.status = .signedOut
                        self.lastExpired = true
                        return
                    }
                    self.status = .failed(e.localizedDescription)
                }
            }
        }
    }

    /// 云端顺序落回本地偏好。只取视频条目——网页壁纸本来就不参与拖动排序。
    private func applyOrder(_ report: SyncEngine.Report) {
        let order = report.order
        guard !order.isEmpty else { return }
        let names = order.compactMap { id -> String? in
            guard id.hasPrefix("v-") else { return nil }
            return String(id.dropFirst(2))
        }
        guard !names.isEmpty else { return }
        let ud = UserDefaults.standard
        if (ud.array(forKey: "VWTuning.libraryOrder") as? [String]) != names {
            ud.set(names, forKey: "VWTuning.libraryOrder")
            NotificationCenter.default.post(name: SyncCenter.libraryDidChange, object: nil)
        }
    }

    // MARK: 目录监听

    private func watchLibrary() {
        guard watcher == nil else { return }
        let dir = Source.libraryDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                           eventMask: [.write, .delete, .rename],
                                                           queue: .main)
        src.setEventHandler { [weak self] in
            guard let self, !self.suppressWatch else { return }
            self.scheduleSync()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }
}
