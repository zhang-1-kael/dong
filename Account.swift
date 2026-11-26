import Foundation
import Security

/// 账号与云端同步的底层：接口调用 + 令牌保管。
///
/// 只依赖 Foundation，不碰 AppKit —— 这样命令行 harness 能单独编译它，
/// 用 `VW_SUPPORT_DIR` 指到临时目录就能整条链路跑一遍，不碰真实用户数据。
///
/// 地址规则和 `Api`（Analytics.swift）一致：
///   1. 环境变量 `VW_API_BASE`（本地联调）
///   2. Info.plist 的 `ApiBaseURL`（打包时注入）
///   3. 都没有 → 视为未配置，一条请求都不发
enum SyncConfig {
    static let base: URL = {
        if let s = ProcessInfo.processInfo.environment["VW_API_BASE"], let u = URL(string: s) {
            return u
        }
        // 独立键：同步服务和统计服务将来可以分开部署，没填就退回统计域名
        for key in ["SyncBaseURL", "ApiBaseURL"] {
            if let s = Bundle.main.infoDictionary?[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !t.contains("REPLACE-ME"), let u = URL(string: t) { return u }
            }
        }
        return URL(string: "https://REPLACE-ME.invalid")!
    }()

    static var isConfigured: Bool {
        !(base.host ?? "").lowercased().contains("replace-me")
    }

    static func url(_ path: String) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: true) ?? URLComponents()
        c.path = path.hasPrefix("/") ? path : "/" + path
        return c.url ?? base
    }
}

/// 登录态。token 存钥匙串，不落 UserDefaults（偏好文件是明文备份的）
struct AccountSession: Codable {
    var email: String
    var userId: String
    var token: String
    var quotaBytes: Int64
}

enum AccountError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没配置同步服务器"
        case let .http(code, msg): return "\(msg)（\(code)）"
        case let .network(msg): return "网络不通：\(msg)"
        case .decoding: return "服务器返回的格式看不懂"
        }
    }
}

/// 云端清单里的一条。`id` 规则见 SyncEngine。
struct RemoteItem: Codable, Equatable {
    var id: String
    var name: String
    /// "video" | "web"
    var kind: String
    var bytes: Int64
    var sha256: String
    /// 毫秒时间戳，冲突时比大小
    var updatedAt: Int64
    /// 网页壁纸的地址
    var webURL: String?
    /// 墓碑：删掉的条目留 30 天，别让另一台设备又把它推回来
    var deleted: Bool?

    var isDeleted: Bool { deleted ?? false }
}

struct RemoteManifest: Codable {
    var rev: Int
    var items: [RemoteItem]
    var order: [String]
    var updatedAt: Int64

    static let empty = RemoteManifest(rev: 0, items: [], order: [], updatedAt: 0)
}

enum AccountAPI {

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 600
        return URLSession(configuration: c)
    }()

    /// 这台电脑叫什么。设备列表里显示的就是它，登录时随请求头一起报给服务端。
    static let deviceName: String = {
        if let n = Host.current().localizedName, !n.isEmpty { return n }
        return "Mac"
    }()

    /// 设备名的百分号编码版（只保留 ASCII 安全字符，其余转义）
    static let encodedDeviceName: String = {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return deviceName.addingPercentEncoding(withAllowedCharacters: allowed) ?? "Mac"
    }()

    private static func request(_ path: String,
                                method: String = "GET",
                                token: String? = nil,
                                headers: [String: String] = [:],
                                body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: SyncConfig.url(path))
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "accept")
        // 电脑名可能是中文：HTTP 头只保证 ISO-8859-1，先做百分号编码，
        // 服务端再解回来，穿反代也不会花。
        r.setValue(Self.encodedDeviceName, forHTTPHeaderField: "x-device-name")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        if let body {
            r.httpBody = body
            if r.value(forHTTPHeaderField: "content-type") == nil {
                r.setValue("application/json", forHTTPHeaderField: "content-type")
            }
        }
        return r
    }

    @discardableResult
    private static func send(_ req: URLRequest) -> Result<(Data, Int), AccountError> {
        guard SyncConfig.isConfigured else { return .failure(.notConfigured) }
        let sem = DispatchSemaphore(value: 0)
        var result: Result<(Data, Int), AccountError> = .failure(.network("未开始"))
        session.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err {
                result = .failure(.network(err.localizedDescription))
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            result = .success((data ?? Data(), code))
        }.resume()
        sem.wait()
        return result
    }

    private static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func errorMessage(_ data: Data, _ code: Int) -> AccountError {
        let msg = json(data)["error"] as? String
        return .http(code, msg ?? "请求失败")
    }

    // MARK: 账号

    static func register(email: String, password: String) -> Result<AccountSession, AccountError> {
        let body = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let res = send(request("/api/auth/register", method: "POST", body: body))
        return decodeSession(res)
    }

    static func login(email: String, password: String) -> Result<AccountSession, AccountError> {
        let body = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let res = send(request("/api/auth/login", method: "POST", body: body))
        return decodeSession(res)
    }

    private static func decodeSession(_ res: Result<(Data, Int), AccountError>) -> Result<AccountSession, AccountError> {
        switch res {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            let o = json(data)
            guard let token = o["token"] as? String,
                  let email = o["email"] as? String,
                  let uid = o["userId"] as? String else { return .failure(.decoding) }
            let quota = (o["quotaBytes"] as? NSNumber)?.int64Value ?? 0
            return .success(AccountSession(email: email, userId: uid, token: token, quotaBytes: quota))
        }
    }

    /// 改密码：需要旧密码。成功后服务端会作废其它设备的令牌，当前这台保留
    static func changePassword(token: String, old: String, new: String) -> Result<Void, AccountError> {
        let body = try? JSONSerialization.data(withJSONObject: [
            "oldPassword": old, "newPassword": new,
        ])
        switch send(request("/api/auth/password", method: "POST", token: token, body: body)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            return .success(())
        }
    }

    // MARK: 个人资料

    struct Profile {
        var email: String
        var displayName: String
        var hasAvatar: Bool
    }

    static func profile(token: String) -> Result<Profile, AccountError> {
        switch send(request("/api/auth/profile", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            let o = json(data)
            return .success(Profile(email: o["email"] as? String ?? "",
                                    displayName: o["displayName"] as? String ?? "",
                                    hasAvatar: o["hasAvatar"] as? Bool ?? false))
        }
    }

    static func updateDisplayName(token: String, name: String) -> Result<Void, AccountError> {
        let body = try? JSONSerialization.data(withJSONObject: ["displayName": name])
        switch send(request("/api/auth/profile", method: "PUT", token: token, body: body)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            return .success(())
        }
    }

    static func uploadAvatar(token: String, png: Data) -> Result<Void, AccountError> {
        let req = request("/api/auth/avatar", method: "PUT", token: token,
                          headers: ["content-type": "image/png"], body: png)
        switch send(req) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            return .success(())
        }
    }

    static func deleteAvatar(token: String) -> Result<Void, AccountError> {
        switch send(request("/api/auth/avatar", method: "DELETE", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            return .success(())
        }
    }

    /// 拉头像字节（服务端会 302 到对象存储，URLSession 默认自动跟随）
    static func avatarData(token: String) -> Result<Data, AccountError> {
        switch send(request("/api/auth/avatar", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            return .success(data)
        }
    }

    // MARK: 登录设备

    struct SessionInfo {
        var id: String
        var device: String
        var createdAt: Int64
        var lastSeen: Int64
        var current: Bool
    }

    static func sessions(token: String) -> Result<[SessionInfo], AccountError> {
        switch send(request("/api/auth/sessions", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            guard let arr = json(data)["sessions"] as? [[String: Any]] else { return .success([]) }
            let list = arr.map { o in
                SessionInfo(id: o["id"] as? String ?? "",
                            device: o["device"] as? String ?? "未知设备",
                            createdAt: (o["createdAt"] as? NSNumber)?.int64Value ?? 0,
                            lastSeen: (o["lastSeen"] as? NSNumber)?.int64Value ?? 0,
                            current: o["current"] as? Bool ?? false)
            }
            return .success(list)
        }
    }

    /// id 传具体设备，或 "others" 表示除了当前这台全踢。返回踢掉几台。
    static func revokeSession(token: String, id: String) -> Result<Int, AccountError> {
        let q = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        switch send(request("/api/auth/sessions?id=\(q)", method: "DELETE", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            let n = (json(data)["removed"] as? NSNumber)?.intValue
            return .success(n ?? 1)
        }
    }

    // MARK: 恢复码

    struct RecoveryState {
        var hasRecovery: Bool
        var createdAt: Int64
    }

    static func recoveryStatus(token: String) -> Result<RecoveryState, AccountError> {
        switch send(request("/api/auth/recovery", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            let o = json(data)
            return .success(RecoveryState(hasRecovery: o["hasRecovery"] as? Bool ?? false,
                                          createdAt: (o["createdAt"] as? NSNumber)?.int64Value ?? 0))
        }
    }

    /// 生成恢复码。明文只在这里返回一次，服务端只存哈希。
    static func createRecovery(token: String) -> Result<String, AccountError> {
        switch send(request("/api/auth/recovery", method: "POST", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            guard let c = json(data)["code"] as? String, !c.isEmpty else { return .failure(.decoding) }
            return .success(c)
        }
    }

    static func removeRecovery(token: String) -> Result<Void, AccountError> {
        switch send(request("/api/auth/recovery", method: "DELETE", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            return .success(())
        }
    }

    /// 忘了密码时用：邮箱 + 恢复码换新密码。不需要登录。
    static func resetPassword(email: String, code: String, newPassword: String) -> Result<Void, AccountError> {
        let body = try? JSONSerialization.data(withJSONObject: [
            "email": email, "code": code, "newPassword": newPassword,
        ])
        switch send(request("/api/auth/recovery/reset", method: "POST", body: body)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            return .success(())
        }
    }

    static func logout(token: String) {
        _ = send(request("/api/auth/logout", method: "POST", token: token))
    }

    struct Me { var email: String; var quotaBytes: Int64; var usedBytes: Int64 }

    static func me(token: String) -> Result<Me, AccountError> {
        switch send(request("/api/me", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            let o = json(data)
            return .success(Me(email: o["email"] as? String ?? "",
                               quotaBytes: (o["quotaBytes"] as? NSNumber)?.int64Value ?? 0,
                               usedBytes: (o["usedBytes"] as? NSNumber)?.int64Value ?? 0))
        }
    }

    // MARK: 清单

    static func manifest(token: String) -> Result<RemoteManifest, AccountError> {
        switch send(request("/api/sync/manifest", token: token)) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            let dec = JSONDecoder()
            guard let m = try? dec.decode(RemoteManifest.self, from: data) else { return .failure(.decoding) }
            return .success(m)
        }
    }

    /// ifMatch 传上一次拿到的 rev；服务器发现对不上会返回 409，不覆盖别人的改动
    static func putManifest(token: String, ifMatch: Int, items: [RemoteItem], order: [String])
        -> Result<(Int, RemoteManifest?), AccountError> {
        let enc = JSONEncoder()
        let payload: [String: Any] = [
            "items": (try? JSONSerialization.jsonObject(with: enc.encode(items))) ?? [],
            "order": order,
        ]
        let body = try? JSONSerialization.data(withJSONObject: payload)
        let req = request("/api/sync/manifest", method: "PUT", token: token,
                          headers: ["if-match": String(ifMatch)], body: body)
        switch send(req) {
        case let .failure(e):
            return .failure(e)
        case let .success((data, code)):
            if code == 409 {
                // 409 只表示「别人先写了」，调用方重新拉一次清单再合并，不算错误
                return .failure(.http(409, "云端有新改动"))
            }
            guard (200..<300).contains(code) else { return .failure(errorMessage(data, code)) }
            let rev = (json(data)["rev"] as? NSNumber)?.intValue ?? ifMatch + 1
            return .success((rev, nil))
        }
    }

    // MARK: 文件

    /// 上传进度回调：(已发送字节, 总字节)
    typealias UploadProgress = (Int64, Int64) -> Void

    static func upload(token: String, id: String, file: URL,
                       onProgress: UploadProgress? = nil) -> Result<String, AccountError> {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int64 else {
            return .failure(.network("读不到文件"))
        }
        var req = request("/api/sync/asset/\(id)", method: "PUT", token: token,
                          headers: ["content-type": "application/octet-stream",
                                    "x-content-length": String(size)])
        req.timeoutInterval = 3600

        // 用带 delegate 的会话才能拿到「已发送多少字节」——不然一张 300MB 的壁纸
        // 传十分钟，界面上一直是 0%，用户会以为卡死。
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 3600
        let sink = UploadSink(expected: size, onProgress: onProgress)
        let session = URLSession(configuration: cfg, delegate: sink, delegateQueue: nil)
        let task = session.uploadTask(with: req, fromFile: file)
        sink.bind(task)
        task.resume()

        if !sink.wait() {
            session.invalidateAndCancel()
            return .failure(.network("上传超时，网络好像卡住了"))
        }
        session.finishTasksAndInvalidate()

        if let err = sink.error {
            return .failure(.network(err.localizedDescription))
        }
        let code = sink.status
        let data = sink.payload
        guard (200..<300).contains(code) else {
            return .failure(.http(code, (json(data)["error"] as? String) ?? "上传失败"))
        }
        return .success((json(data)["sha256"] as? String) ?? "")
    }

    static func download(token: String, id: String, to: URL) -> Result<Void, AccountError> {
        var req = request("/api/sync/asset/\(id)", token: token)
        req.timeoutInterval = 3600
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Void, AccountError> = .failure(.network("未开始"))
        session.downloadTask(with: req) { tmp, resp, err in
            defer { sem.signal() }
            if let err {
                result = .failure(.network(err.localizedDescription))
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code), let tmp else {
                result = .failure(.http(code, "下载失败"))
                return
            }
            do {
                try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.moveItem(at: tmp, to: to)
                result = .success(())
            } catch {
                result = .failure(.network(error.localizedDescription))
            }
        }.resume()
        sem.wait()
        return result
    }

    static func deleteAsset(token: String, id: String) {
        _ = send(request("/api/sync/asset/\(id)", method: "DELETE", token: token))
    }
}

/// 上传用的 URLSession delegate：报进度 + 长时间没动静就掐掉。
/// 平台侧偶尔会把连接挂住，如果不管，界面上就是「一直 0%」，等一小时也不会自己好。
private final class UploadSink: NSObject, URLSessionDataDelegate {
    private let expected: Int64
    private let onProgress: AccountAPI.UploadProgress?
    private let sem = DispatchSemaphore(value: 0)
    private var task: URLSessionUploadTask?
    private var lastActive = Date()
    private var watchdog: DispatchSourceTimer?
    private let lock = NSLock()

    private(set) var payload = Data()
    private(set) var status = 0
    private(set) var error: Error?

    /// 多少秒没有任何字节推进就判定卡住
    // 慢链路 + 平台代理缓冲时，进度回调之间可能出现较长空档；
    // 120 秒太激进（实测把正常上传掐了两次），放宽到 5 分钟。
    private let stallSeconds: TimeInterval = 300

    init(expected: Int64, onProgress: AccountAPI.UploadProgress?) {
        self.expected = expected
        self.onProgress = onProgress
        super.init()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + stallSeconds, repeating: 10)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let idle = Date().timeIntervalSince(self.lastActive)
            self.lock.unlock()
            if idle >= self.stallSeconds {
                self.error = NSError(domain: "Dong", code: -1001,
                                     userInfo: [NSLocalizedDescriptionKey: "上传卡住了，已中断并会重试"])
                self.task?.cancel()
            }
        }
        t.resume()
        watchdog = t
    }

    func bind(_ t: URLSessionUploadTask) {
        lock.lock(); task = t; lock.unlock()
    }

    func wait() -> Bool {
        let r = sem.wait(timeout: .now() + 3600)
        watchdog?.cancel()
        watchdog = nil
        return r == .success
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        lock.lock(); lastActive = Date(); lock.unlock()
        let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : expected
        onProgress?(totalBytesSent, total)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); payload.append(data); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if self.error == nil { self.error = error }
        status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        sem.signal()
    }
}

/// 令牌保管：会话 JSON 存在 support 目录下，权限 0600。
///
/// 为什么不用钥匙串：这个 App 是 ad-hoc 签名的，**每次重新编译签名都会变**，
/// 钥匙串条目的 ACL 认的是签名，换签名后旧条目就读不出来（或被系统弹框拦住）。
/// 实测就是：打完包一装，用户就从「已登录」变回「未登录」，同步再也跑不起来。
/// 文件方案没有这个问题，代价是安全性略低于钥匙串（同用户可读）。
/// 旧版本存在钥匙串里的会话会尝试迁移一次，读到了就搬到文件里。
enum AccountStore {
    private static let service = "com.zhanghangshuo.dong.sync"
    private static let account = "session"

    /// 不依赖 main.swift 里的 Source，命令行 harness 也能单独编译
    private static var support: URL {
        if let p = ProcessInfo.processInfo.environment["VW_SUPPORT_DIR"] {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VideoWallpaper")
    }

    private static var file: URL { support.appendingPathComponent("session.json") }

    static func load() -> AccountSession? {
        if let d = try? Data(contentsOf: file),
           let s = try? JSONDecoder().decode(AccountSession.self, from: d) {
            return s
        }
        // 迁移：老版本存在钥匙串里
        if let s = loadFromKeychain() {
            save(s)
            deleteKeychain()
            return s
        }
        return nil
    }

    static func save(_ s: AccountSession) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
        deleteKeychain()
    }

    // MARK: 旧钥匙串（只用于迁移）

    private static func loadFromKeychain() -> AccountSession? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }

    private static func deleteKeychain() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
