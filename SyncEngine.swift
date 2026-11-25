import Foundation
import CryptoKit

/// 壁纸库 ↔ 云端 的合并逻辑。
///
/// 身份用文件名（App 本来就用文件名当壁纸的名字，排序、微调、菜单都按它走），
/// 因此重命名 = 删一条 + 加一条，v1 就这样，不搞 id 映射表。
///
/// 冲突用「谁更新谁赢」：视频看文件 mtime，网页壁纸看 addedAt。
/// 删除会留下墓碑，保留 30 天，免得另一台设备把刚删的又推回来。
enum SyncEngine {

    // MARK: 本地快照

    struct LocalItem {
        var id: String
        var name: String
        var kind: String          // video | web
        var bytes: Int64
        var sha256: String
        var updatedAt: Int64      // ms
        var file: URL?
        var webURL: String?
    }

    struct SyncState: Codable {
        var rev: Int = -1
        /// id -> sha256，用来判断「上次同步时有、现在没了」= 本地删除
        var items: [String: String] = [:]
        /// 校验和缓存：path -> (size, mtime, sha)，避免每次全量重算
        var hashes: [String: CachedHash] = [:]
        /// 已经成功上传、但清单还没写成功的条目（id -> sha）。
        /// 443MB 的首传一旦中途断掉，靠它续上，不用从第 1 张重来。
        /// 用可选类型：老的状态文件里没有这个键，合成解码不会因此报错。
        var synced: [String: String]?

        struct CachedHash: Codable {
            var size: Int64
            var mtime: Int64
            var sha: String
        }
    }

    // MARK: 动作

    enum Action {
        case upload(LocalItem)          // 本地有、云端没有或云端旧
        case download(RemoteItem)       // 云端有、本地没有或云端新
        case deleteLocalFile(String)    // 云端墓碑，本地该删
        case addWebStream(RemoteItem)
        case removeWebStream(String)
    }

    /// 一次同步的进度快照。UI 用它画进度条和「还剩几张」。
    struct Progress {
        var text: String = ""
        /// 0…1，按字节算；总字节未知时退回按动作数
        var fraction: Double = 0
        var done: Int = 0
        var total: Int = 0
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
    }

    struct Report {
        var uploaded = 0
        var downloaded = 0
        var removed = 0
        var skipped = 0
        var errors: [String] = []
        /// 合并后的顺序（v-xxx / w-xxx）
        var order: [String] = []
        var summary: String {
            if errors.isEmpty {
                return "同步完成：上传 \(uploaded) · 下载 \(downloaded) · 删除 \(removed)"
            }
            return "同步有 \(errors.count) 处没成：\(errors[0])"
        }
    }

    // MARK: 工具

    static func sha256(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? fh.read(upToCount: 4 * 1024 * 1024)) ?? nil
            guard let c = chunk, !c.isEmpty else { break }
            hasher.update(data: c)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 往 support/sync.log 追加一行。出问题时可以直接把这个文件发出去，
    /// 不用只靠 UI 上那一句话猜。
    static func log(_ support: URL, _ msg: String) {
        let f = support.appendingPathComponent("sync.log")
        let ts = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(ts) \(msg)\n".data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: f) {
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
            try? fh.close()
        } else {
            try? data.write(to: f)
        }
    }

    static func stateFile(_ support: URL) -> URL {
        support.appendingPathComponent("sync-state.json")
    }

    static func loadState(_ support: URL) -> SyncState {
        guard let d = try? Data(contentsOf: stateFile(support)),
              let s = try? JSONDecoder().decode(SyncState.self, from: d) else { return SyncState() }
        return s
    }

    static func saveState(_ support: URL, _ s: SyncState) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(s) {
            try? d.write(to: stateFile(support), options: .atomic)
        }
    }

    // MARK: 快照

    /// 扫描本地库。webStreams 传 [(id, name, url, addedAt)]，由调用方从 streams.json 读好。
    static func snapshot(libraryDir: URL,
                         webStreams: [(id: String, name: String, url: String, addedAt: Date)],
                         support: URL,
                         state: inout SyncState) -> [LocalItem] {
        var out: [LocalItem] = []
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: libraryDir, includingPropertiesForKeys: nil)) ?? []
        for f in files where ["mp4", "mov", "m4v"].contains(f.pathExtension.lowercased()) {
            guard let attr = try? fm.attributesOfItem(atPath: f.path) else { continue }
            let size = (attr[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = Int64((attr[.modificationDate] as? Date ?? Date()).timeIntervalSince1970 * 1000)
            let sha: String
            if let cached = state.hashes[f.path], cached.size == size, cached.mtime == mtime {
                sha = cached.sha
            } else if let h = sha256(of: f) {
                sha = h
                state.hashes[f.path] = .init(size: size, mtime: mtime, sha: h)
            } else {
                continue
            }
            out.append(LocalItem(id: "v-" + f.lastPathComponent,
                                 name: f.deletingPathExtension().lastPathComponent,
                                 kind: "video",
                                 bytes: size,
                                 sha256: sha,
                                 updatedAt: mtime,
                                 file: f,
                                 webURL: nil))
        }
        for w in webStreams {
            out.append(LocalItem(id: "w-" + w.id,
                                 name: w.name,
                                 kind: "web",
                                 bytes: 0,
                                 sha256: w.url,          // 网页壁纸用地址当「内容指纹」
                                 updatedAt: Int64(w.addedAt.timeIntervalSince1970 * 1000),
                                 file: nil,
                                 webURL: w.url))
        }
        return out
    }

    // MARK: 合并

    /// 纯函数：只决定该做什么，不动磁盘、不发网络。方便单独测。
    static func plan(local: [LocalItem], remote: RemoteManifest, state: SyncState)
        -> (actions: [Action], merged: [RemoteItem], order: [String]) {
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var merged: [RemoteItem] = []
        var actions: [Action] = []
        var handled = Set<String>()

        // 1) 云端已有的
        for r in remote.items {
            handled.insert(r.id)
            let l = byId[r.id]
            if r.isDeleted {
                if let l {
                    // 本地比墓碑新 → 说明删完又加回来了，复活它
                    if l.updatedAt > r.updatedAt {
                        merged.append(toRemote(l))
                        actions.append(.upload(l))
                    } else {
                        actions.append(l.kind == "web" ? .removeWebStream(streamId(l.id)) : .deleteLocalFile(nameOf(l)))
                        merged.append(r)
                    }
                } else {
                    merged.append(r)   // 墓碑保留，到期由服务端/客户端清理
                }
                continue
            }
            guard let l else {
                // 云端有、本地没有：要么是新设备首次同步，要么本地刚删（由第 2 步判断）
                if state.items[r.id] != nil {
                    // 上次同步时还在 → 是本地删掉的，补一条墓碑
                    var tomb = r
                    tomb.deleted = true
                    tomb.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
                    merged.append(tomb)
                } else {
                    actions.append(r.kind == "web" ? .addWebStream(r) : .download(r))
                    merged.append(r)
                }
                continue
            }
            if l.sha256 == r.sha256 {
                merged.append(toRemote(l))     // 内容一样，更新一下名字/时间
            } else if l.updatedAt >= r.updatedAt {
                merged.append(toRemote(l))
                actions.append(.upload(l))
            } else {
                actions.append(r.kind == "web" ? .addWebStream(r) : .download(r))
                merged.append(r)
            }
        }

        // 2) 本地多出来的：新加的，或者上次没同步过
        for l in local where !handled.contains(l.id) {
            // 上一轮传到一半断了：文件已经上传成功，只是清单没写上去
            if let done = state.synced?[l.id], done == l.sha256 {
                merged.append(toRemote(l))
                continue
            }
            if state.items[l.id] != nil {
                // 上次同步过、云端现在没有 → 云端被别的设备删了
                var tomb = toRemote(l)
                tomb.deleted = true
                tomb.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
                merged.append(tomb)
                actions.append(l.kind == "web" ? .removeWebStream(streamId(l.id)) : .deleteLocalFile(nameOf(l)))
            } else {
                merged.append(toRemote(l))
                actions.append(.upload(l))
            }
        }

        // 3) 顺序：云端改过就用云端的，否则把本地顺序推上去
        let localOrder = local.map { $0.id }
        let order = remote.rev > state.rev && !remote.order.isEmpty ? remote.order : localOrder
        return (actions, merged, order)
    }

    private static func nameOf(_ l: LocalItem) -> String {
        l.file?.lastPathComponent ?? l.name
    }

    private static func streamId(_ id: String) -> String {
        id.hasPrefix("w-") ? String(id.dropFirst(2)) : id
    }

    private static func toRemote(_ l: LocalItem) -> RemoteItem {
        RemoteItem(id: l.id, name: l.name, kind: l.kind, bytes: l.bytes,
                   sha256: l.sha256, updatedAt: l.updatedAt,
                   webURL: l.webURL, deleted: false)
    }

    // MARK: 执行

    /// 跑一次完整同步。lib 的回调都在调用方线程（内部用串行队列，外面自己切主线程）。
    static func run(session: AccountSession,
                    libraryDir: URL,
                    support: URL,
                    webStreams: [(id: String, name: String, url: String, addedAt: Date)],
                    addWebStream: (String, String, String) -> Void,
                    removeWebStream: (String) -> Void,
                    progress: ((Progress) -> Void)? = nil) -> Result<Report, AccountError> {
        var state = loadState(support)
        var report = Report()

        let knownBefore = Set(state.items.keys)
        let remoteResult = AccountAPI.manifest(token: session.token)
        guard case let .success(remote) = remoteResult else {
            if case let .failure(e) = remoteResult { return .failure(e) }
            return .failure(.decoding)
        }

        let local = snapshot(libraryDir: libraryDir, webStreams: webStreams, support: support, state: &state)
        let (actions, merged, order) = plan(local: local, remote: remote, state: state)

        // 上传失败要重试一次：清单里先不写它，免得下次以为已同步
        var failedIds = Set<String>()

        // 进度要按「整个库」显示：已经同步过的也算进去，
        // 否则用户看到「第 3/8 张」会以为库里只有 8 张（其实 21 张，13 张早传完了）。
        let pendingCount = actions.count
        let total = local.count
        let alreadyDone = max(0, total - pendingCount)
        var step = 0
        // 总字节：上传按文件大小，下载按清单里记的大小
        func sizeOf(_ a: Action) -> Int64 {
            switch a {
            case let .upload(i): return i.bytes
            case let .download(r): return r.bytes
            default: return 0
            }
        }
        let pendingBytes = actions.reduce(Int64(0)) { $0 + sizeOf($1) }
        let libraryBytes = local.reduce(Int64(0)) { $0 + $1.bytes }
        // 总数取「整库字节」，已传的部分算进进度；下载类动作不占库字节，退回待处理字节
        let bytesTotal = max(pendingBytes, libraryBytes)
        var bytesDone: Int64 = max(0, bytesTotal - pendingBytes)

        func emit(_ text: String, extra: Int64 = 0) {
            var p = Progress()
            p.text = text
            p.done = alreadyDone + step
            p.total = total
            p.bytesDone = bytesDone + extra
            p.bytesTotal = bytesTotal
            p.fraction = bytesTotal > 0
                ? min(1, Double(bytesDone + extra) / Double(bytesTotal))
                : (total > 0 ? Double(step) / Double(total) : 0)
            progress?(p)
        }

        log(support, "开始同步：本地 \(local.count) 张，已同步 \(alreadyDone) 张，待处理 \(pendingCount) 个，整库 \(bytesTotal / 1024 / 1024)MB，rev \(remote.rev)")
        emit("正在准备…")

        for a in actions {
            step += 1
            // 文案里不再带计数（计数在下面那行明细），避免和明细重复
            let label: String
            switch a {
            case let .upload(i): label = "正在上传 · \(i.name)"
            case let .download(r): label = "正在下载 · \(r.name)"
            case .deleteLocalFile: label = "正在清理本地已删除的壁纸…"
            case .addWebStream: label = "正在添加网页壁纸…"
            case .removeWebStream: label = "正在移除网页壁纸…"
            }
            emit(label)
            switch a {
            case let .upload(item):
                guard let file = item.file else { break }
                let emitLock = NSLock()
                var lastPercent = -1
                var uploadResult: Result<String, AccountError> = .failure(.network("未开始"))
                for attempt in 1...2 {
                uploadResult = AccountAPI.upload(token: session.token, id: item.id, file: file,
                                         onProgress: { sent, _ in
                    // 每涨 1% 才刷一次界面
                    emitLock.lock()
                    let pct = Int(Double(sent) / Double(max(item.bytes, 1)) * 100)
                    let should = pct > lastPercent
                    if should { lastPercent = pct }
                    emitLock.unlock()
                    if should { emit(label, extra: sent) }
                })
                if case .success = uploadResult { break }
                if attempt == 1 {
                    if case let .failure(e) = uploadResult {
                        log(support, "上传重试 \(item.id)：\(e.localizedDescription)")
                    }
                    emit(label + "（重试中）", extra: 0)
                }
                }
                switch uploadResult {
                case .success:
                    report.uploaded += 1
                    // 立刻记账：下一步如果断电/被杀，这张不用重传
                    if state.synced == nil { state.synced = [:] }
                    state.synced?[item.id] = item.sha256
                    saveState(support, state)
                case let .failure(e):
                    failedIds.insert(item.id)
                    report.errors.append("\(item.name)：\(e.localizedDescription)")
                    log(support, "上传失败 \(item.id)：\(e.localizedDescription)")
                }
            case let .download(item):
                let name = item.name.isEmpty ? item.id : item.name
                let ext = item.kind == "web" ? "" : ".mp4"
                let dest = libraryDir.appendingPathComponent(sanitize(name) + ext)
                switch AccountAPI.download(token: session.token, id: item.id, to: dest) {
                case .success:
                    report.downloaded += 1
                    // 下载后校正 mtime，否则下次比较会以为是本地新改的
                    try? FileManager.default.setAttributes(
                        [.modificationDate: Date(timeIntervalSince1970: Double(item.updatedAt) / 1000)],
                        ofItemAtPath: dest.path)
                case let .failure(e):
                    failedIds.insert(item.id)
                    report.errors.append("\(item.name)：\(e.localizedDescription)")
                    log(support, "上传失败 \(item.id)：\(e.localizedDescription)")
                }
            case let .deleteLocalFile(name):
                let url = libraryDir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    report.removed += 1
                }
            case let .addWebStream(item):
                if let u = item.webURL { addWebStream(String(item.id.dropFirst(2)), item.name, u) }
                report.downloaded += 1
            case let .removeWebStream(id):
                removeWebStream(id)
                report.removed += 1
            }
            bytesDone += sizeOf(a)
            emit(label)
        }

        // 失败的条目从清单里摘掉，下轮还会再试
        let finalItems = merged.filter { !failedIds.contains($0.id) }
        let finalOrder = order.filter { !failedIds.contains($0) }

        emit("正在更新云端清单…")
        switch AccountAPI.putManifest(token: session.token, ifMatch: remote.rev,
                                      items: finalItems, order: finalOrder) {
        case let .success((rev, _)):
            state.rev = rev
            state.items = Dictionary(uniqueKeysWithValues: finalItems.filter { !$0.isDeleted }.map { ($0.id, $0.sha256) })
            state.synced = [:]      // 清单已落地，待传记录作废
            saveState(support, state)
        case let .failure(e):
            report.errors.append("清单没写上去：\(e.localizedDescription)")
        }

        // 这一轮新产生的墓碑，云端文件直接回收（否则单设备删除会一直占配额）
        for item in finalItems where item.isDeleted && knownBefore.contains(item.id) {
            if item.kind != "web" { AccountAPI.deleteAsset(token: session.token, id: item.id) }
        }
        log(support, "同步结束：上传 \(report.uploaded) 下载 \(report.downloaded) 删除 \(report.removed) 失败 \(report.errors.count)")
        report.order = finalOrder
        report.skipped = local.count - report.uploaded
        return .success(report)
    }

    private static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
