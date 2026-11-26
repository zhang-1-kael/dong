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
    /// 登录后「正在判断云端是否为空 → 切库」这一小段。界面据此显示「正在准备同步…」，
    /// 否则用户会看到「已登录」却什么都没发生。
    private(set) var isPreparing = false
    /// 调试：只摆拍不联网（截「同步中」的界面时用）
    private var previewOnly = false
    /// 切换壁纸库归属期间不跑同步，否则会把「不该属于这个账号的本地壁纸」传上去
    private var isSwitchingLibrary = false
    /// 上一次是不是因为登录过期被打断（设置里据此提示「重新登录」）
    private(set) var lastExpired = false

    /// 代次：每次登录 / 退出都 +1。后台任务带着自己那一代回来时，
    /// 只要代次对不上就直接丢弃——否则「退出登录后旧任务又来写状态」会把新状态冲掉。
    private var generation = 0
    /// 正在跑的那一轮同步的取消票
    private var runToken: CancelToken?
    /// 登录后「判断云端是否为空」这一段的取消票，与 runToken 分开
    private var prepToken: CancelToken?
    /// 本会话的壁纸库是否已经确定归属。没确定之前不许同步，
    /// 否则会把「其实属于这个账号的云端壁纸」下载进匿名库（退出后就露出来了）。
    private var libraryReady = true

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
            if parts.count > 2 {
                previewOnly = true
                // 摆拍用：给资料页一点内容
                profile = AccountAPI.Profile(email: parts[0], displayName: "Kael", hasAvatar: false)
                if let pct = Double(parts[2]) {
                    var p = SyncEngine.Progress()
                    p.text = "正在上传 · 🌬️"
                    p.fraction = pct
                    p.done = 7
                    p.total = 22
                    p.bytesDone = Int64(pct * 443 * 1024 * 1024)
                    p.bytesTotal = 443 * 1024 * 1024
                    progress = p
                    status = .syncing(p.text)
                } else if parts[2] == "idle" {
                    status = .done("已同步")
                }
            }
        }
        // 摆拍模式下面已经在上面设成 .syncing 了，别再覆盖回 idle
        if !previewOnly {
            status = session == nil ? .signedOut : .idle
        }
        if let s = session, !previewOnly {
            loadCachedProfile(s.userId)
        }
    }

    // MARK: 账号

    func signIn(_ s: AccountSession) {
        // 上一轮（可能是退出前那轮卡住的上传）先掐掉，否则它占着队列，这次登录要排队等它超时
        generation += 1
        let gen = generation
        runToken?.cancel(); runToken = nil
        prepToken?.cancel(); prepToken = nil

        session = s
        AccountStore.save(s)
        status = .idle
        isPreparing = true       // 界面从第一帧就能看到「正在准备同步…」
        libraryReady = false
        // 先把手里的资料摆上（上次登录时缓存的昵称头像），网络回来再刷新，
        // 否则重新登录后会先显示成「邮箱 / 首字母」再跳变（用户 2026-11-26 遇到的）
        loadCachedProfile(s.userId)
        NotificationCenter.default.post(name: SyncCenter.changed, object: nil)
        watchLibrary()

        let token = s.token
        let userId = s.userId
        refreshProfile(gen: gen)

        // 兜底：万一这条链路被什么卡住，25 秒后也要把「正在准备同步…」收掉，
        // 不能让界面一直显示一句自己做不到的话
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.generation == gen, self.isPreparing else { return }
            self.isPreparing = false
            if case .idle = self.status { self.status = .failed("准备超时，点「立即同步」重试") }
        }

        prepareLibrary(gen: gen, token: token, userId: userId)
    }

    /// 登录后的「读云端清单 → 定壁纸库归属」这一段。失败时不动归属、不同步，
    /// 等用户点「立即同步」会再走一遍这个函数（而不是傻等）。
    private func prepareLibrary(gen: Int, token: String, userId: String) {
        guard prepToken == nil else { return }
        let prep = CancelToken()
        prepToken = prep
        isPreparing = true
        libraryReady = false

        // 规则（用户 2026-11-25）：登录后只显示这个账号的壁纸；账号是空的才把本地并进去。
        // 必须先切库再同步，否则会把本地壁纸误传进别人的账号。
        queue.async { [weak self] in
            guard let self else { return }
            // 读云端清单。读不到就重试一次——千万不能把「读不到」当成「云端是空的」，
            // 那会把本地壁纸误并进一个其实有内容的账号。
            var empty: Bool?
            for attempt in 1...2 {
                if prep.isCancelled { return }
                // 探针用短超时：网络不好时要尽快给用户一句准话，不能让人对着「正在准备」干等
                if case let .success(m) = AccountAPI.manifest(token: token, cancel: prep, timeout: 10) {
                    empty = m.items.filter { !$0.isDeleted }.isEmpty
                    break
                }
                if attempt < 2 { Thread.sleep(forTimeInterval: 2) }
            }

            DispatchQueue.main.async {
                guard self.generation == gen, self.prepToken === prep else { return }
                self.prepToken = nil
                self.isPreparing = false

                guard let empty else {
                    // 清单读不到：归属不动，这一轮也不许同步，等用户点「立即同步」重试
                    SyncEngine.log(Source.support, "登录准备失败：读不到云端清单，暂不切库")
                    self.status = .failed("读不到云端清单，点「立即同步」重试")
                    return
                }
                let msg: String
                self.isSwitchingLibrary = true
                msg = LibraryOwner.activate(accountId: userId, remoteIsEmpty: empty)
                self.isSwitchingLibrary = false
                SyncEngine.log(Source.support, "切换壁纸库：\(msg)（cloudEmpty=\(empty)）")
                self.libraryReady = true
                // 库换了，界面和桌面都要重读
                NotificationCenter.default.post(name: SyncCenter.libraryDidChange, object: nil)
                self.syncNow()
            }
        }
    }

    /// 退出登录。返回一句给用户看的话（有未传完的会提示）。
    @discardableResult
    func signOut() -> String {
        // 先掐掉正在跑的同步：它可能正卡在一个 300 秒看门狗的上传里，
        // 不掐的话，重新登录要排在它后面等好几分钟（用户 2026-11-26 遇到的就是这个）
        generation += 1
        runToken?.cancel(); runToken = nil
        prepToken?.cancel(); prepToken = nil
        pending?.cancel(); pending = nil
        isPreparing = false
        libraryReady = true

        // 通知服务端作废这枚令牌——扔后台，别让「退出登录」按钮卡在网络上（最长 20 秒）
        if let s = session {
            DispatchQueue.global(qos: .utility).async { AccountAPI.logout(token: s.token) }
        }

        // 规则（用户 2026-11-25）：退出后这台机器不能再显示该账号的壁纸，
        // 但**绝不能删文件**——没传完的也要留着，下次登录继续。
        let owner = LibraryOwner.current
        let localCount = (try? FileManager.default.contentsOfDirectory(
            at: Source.libraryDir, includingPropertiesForKeys: nil))?.count ?? 0
        let synced = SyncEngine.loadState(Source.support, key: owner).items.count
        let unsent = max(0, localCount - synced)

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

        if unsent > 0 {
            return msg + "\n还有 \(unsent) 张没传完，已保存在本机，下次登录会接着传。"
        }
        return msg
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
    func refreshProfile(gen: Int? = nil, done: (() -> Void)? = nil) {
        guard let s = session else { done?(); return }
        let want = gen ?? generation
        queue.async { [weak self] in
            guard let self else { return }
            var p: AccountAPI.Profile?
            if case let .success(v) = AccountAPI.profile(token: s.token) { p = v }
            var avatar: Data?
            if let p, p.hasAvatar, case let .success(d) = AccountAPI.avatarData(token: s.token) {
                avatar = d
            }
            DispatchQueue.main.async {
                guard self.generation == want else { return }
                // 拉失败就保住手里那份（缓存的），别把已经显示出来的名字头像抹成空
                if let p { self.profile = p }
                if let avatar { self.avatarData = avatar }
                if let p { self.saveCachedProfile(p, avatar: avatar, uid: s.userId) }
                NotificationCenter.default.post(name: SyncCenter.changed, object: nil)
                done?()
            }
        }
    }

    // MARK: 资料缓存
    //
    // 重新登录时，昵称头像不能等网络回来才出来（否则会先显示成邮箱 + 首字母，
    // 用户看到的是「我改过的名字头像没了」）。退出登录不清这份缓存：
    // 它只在这台机器上、只在登录后展示，不含壁纸内容。

    private static func profileFile(_ uid: String) -> URL {
        Source.support.appendingPathComponent("profile-\(uid).json")
    }

    private static func avatarFile(_ uid: String) -> URL {
        Source.support.appendingPathComponent("profile-\(uid).png")
    }

    private func loadCachedProfile(_ uid: String) {
        guard let d = try? Data(contentsOf: Self.profileFile(uid)),
              let p = try? JSONDecoder().decode(AccountAPI.CachedProfile.self, from: d) else { return }
        profile = AccountAPI.Profile(email: p.email, displayName: p.displayName, hasAvatar: p.hasAvatar)
        if p.hasAvatar, let img = try? Data(contentsOf: Self.avatarFile(uid)) {
            avatarData = img
        } else {
            avatarData = nil
        }
    }

    private func saveCachedProfile(_ p: AccountAPI.Profile, avatar: Data?, uid: String) {
        let cached = AccountAPI.CachedProfile(email: p.email, displayName: p.displayName,
                                              hasAvatar: p.hasAvatar)
        if let d = try? JSONEncoder().encode(cached) {
            try? d.write(to: Self.profileFile(uid), options: .atomic)
        }
        if let avatar {
            try? avatar.write(to: Self.avatarFile(uid), options: .atomic)
        } else if !p.hasAvatar {
            try? FileManager.default.removeItem(at: Self.avatarFile(uid))
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
        // 库归属还没定（上次准备失败）：点「立即同步」＝再准备一次，而不是什么都不做
        guard libraryReady else {
            prepareLibrary(gen: generation, token: s.token, userId: s.userId)
            return
        }
        guard !status.isBusy else { return }
        status = .syncing("正在同步…")

        let gen = generation
        let token = CancelToken()
        runToken?.cancel()
        runToken = token
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
                stateKey: LibraryOwner.current,
                webStreams: streams,
                cancel: token,
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
                        guard self.generation == gen else { return }
                        self.progress = p
                        self.status = .syncing(p.text)
                    }
                })
            self.suppressWatch = false

            DispatchQueue.main.async {
                // 这一轮已经被作废（退出登录 / 换了账号）：结果一律丢弃，
                // 否则旧任务会把新登录的状态改回「同步出错」
                guard self.generation == gen else { return }
                if self.runToken === token { self.runToken = nil }
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
                    if case .cancelled = e {
                        // 取消是主动行为（退出登录），不弹错
                        if case .syncing = self.status { self.status = .idle }
                        return
                    }
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
