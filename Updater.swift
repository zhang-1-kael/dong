import Foundation
import AppKit
import CryptoKit

/// 自动更新（文档模块一）。
///
/// 流程：`GET /api/update/check` → 有新版本就提示 → `GET /api/download`（302 跳到对象存储，
/// URLSession 自己跟随）→ 校验 SHA256 → 打开 dmg 让人拖进「应用程序」。
///
/// 不做静默替换安装：那需要更高的权限，也容易把用户的 App 换坏。
struct UpdateRelease {
    let version: String
    let build: Int
    let notes: String
    let mandatory: Bool
    let fileSize: Int
    let sha256: String
    let downloadURL: URL?

    var displayName: String { version.isEmpty ? "新版本" : version }
    var sizeText: String {
        guard fileSize > 0 else { return "" }
        let mb = Double(fileSize) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

final class Updater: NSObject {

    static let shared = Updater()

    enum State {
        case idle
        case checking
        case upToDate
        /// 有新版本，等着用户点「立即更新」
        case available(UpdateRelease)
        case downloading(UpdateRelease, Double)
        case ready(UpdateRelease, URL)
        /// 正在把新版本替换进「应用程序」，成功后 App 自己退出并重开
        case installing(UpdateRelease)
        case failed(String)
    }

    /// 状态一变就回调（主线程）
    var onState: ((State) -> Void)?
    /// 强制更新：需要来一发阻断式模态（主线程）
    var onMandatory: ((UpdateRelease) -> Void)?

    private(set) var state: State = .idle {
        didSet {
            let s = state
            if Thread.isMainThread { onState?(s) }
            else { DispatchQueue.main.async { [weak self] in self?.onState?(s) } }
        }
    }

    /// 菜单栏角标 / 菜单项用：当前拿到的新版本（下载中、已下好都算）
    var pendingRelease: UpdateRelease? {
        switch state {
        case .available(let r), .ready(let r, _), .installing(let r): return r
        case .downloading(let r, _): return r
        default: return nil
        }
    }

    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var progressTimer: Timer?
    private var timer: Timer?
    private var checkTask: URLSessionDataTask?
    private var downloadStartedAt = Date()
    /// 上次真正发出检查请求的时间（用于 nudge 节流）
    private var lastCheckAt = Date.distantPast

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        session = URLSession(configuration: cfg)
    }

    // MARK: 定时

    /// 常驻菜单栏的进程可能几天不重启，所以「多久查一次」直接决定了用户多久才知道有新版本。
    ///
    /// 触发点：
    ///   • 启动 10 秒后（`VW_UPDATE_NOW=1` 调试时缩到 1 秒）
    ///   • 启动 70 秒再补一次——首次经常撞上网络没就绪 / 平台冷启动，不能让人白等一轮
    ///   • 每 5 分钟一次（原来 60 分钟：发布新版后，常驻的 App 最多要等一小时才弹提示，
    ///     用户以为「它根本不自动弹」。改成 5 分钟，发布后最多 5 分钟必弹；
    ///     代价只是每小时 12 次极轻的 GET，服务端毫无压力）
    ///   • 合盖睡眠唤醒后 15 秒（Timer 在睡眠期间是停摆的，不加这条，早上开机也看不到）
    ///   • 每次打开面板时顺手查一下（`nudge()`，1 分钟内查过就跳过）
    func start() {
        // 调试用：VW_UPDATE_NOW=1 把首次检查从 10 秒缩到 1 秒
        let delay: TimeInterval =
            ProcessInfo.processInfo.environment["VW_UPDATE_NOW"] != nil ? 1 : 10

        // 首次启动会自动弹面板，别让「打开面板顺手查」抢在 10 秒那次前面，白跑一次请求
        lastCheckAt = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.check(manual: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 60) { [weak self] in
            guard let self else { return }
            // 已经拿到待装版本就别再打一次，省得把「已提示」的记录搅乱
            if case .available = self.state { return }
            self.check(manual: false)
        }

        let t = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // 睡眠会让上面的 Timer 停止走动：醒来后补一次，否则「睡一觉就错过更新」
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func didWake() {
        if ProcessInfo.processInfo.environment["VW_UPDATE_DEBUG"] != nil {
            print("[update] 唤醒 → 15 秒后补查")
        }
        // 刚唤醒时网络常常还没连上，等 15 秒再问
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.check(manual: false)
        }
    }

    /// 每次打开面板 / 壁纸库都顺手查一次。1 分钟内查过就跳过，连点也不会打出一串请求。
    func nudge() {
        let gap = Date().timeIntervalSince(lastCheckAt)
        guard gap > 60 else { return }
        if case .available = state { return }   // 已经在等用户点「立即更新」了
        if ProcessInfo.processInfo.environment["VW_UPDATE_DEBUG"] != nil {
            print("[update] 面板打开 → 顺手检查（距上次 \(Int(gap))s）")
        }
        check(manual: false)
    }

    // MARK: 检查

    func check(manual: Bool) {
        if case .downloading = state { return }
        if case .checking = state { return }
        if case .installing = state { return }
        guard Api.isConfigured else {
            // 还没填正式域名：手动点的时候说清楚，自动轮询就安静待着
            if manual { state = .failed("还没配置更新服务器地址（Info.plist 的 ApiBaseURL）") }
            return
        }

        let info = Bundle.main.infoDictionary
        let build = Int(info?["CFBundleVersion"] as? String ?? "0") ?? 0
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        var comps = URLComponents(url: Api.path("/api/update/check"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "build", value: "\(build)"),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "channel", value: "stable"),
            URLQueryItem(name: "arch", value: Self.arch),
        ]
        guard let url = comps?.url else { return }

        lastCheckAt = Date()
        state = .checking
        var req = URLRequest(url: url)
        req.timeoutInterval = 15

        checkTask?.cancel()
        checkTask = session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard err == nil, (200..<300).contains(code), let data else {
                // 服务端错误静默重试，下次轮询再说；手动点的时候要让人知道没查成
                if manual { self.state = .failed("检查更新失败，稍后再试") }
                else { self.state = .idle }
                return
            }
            guard let parsed = try? JSONDecoder().decode(CheckResponse.self, from: data) else {
                if manual { self.state = .failed("服务端返回的内容看不懂") } else { self.state = .idle }
                return
            }
            guard parsed.updateAvailable, let latest = parsed.latest else {
                self.state = manual ? .upToDate : .idle
                return
            }
            // 服务端已经比过版本，这里只做自保：别把用户「更新」到更旧的版本。
            // 注意服务端的 build 恒为 0，只能按版本号比，不能拿 build 判断。
            guard Self.isNewer(latest.version, than: version) else {
                self.state = manual ? .upToDate : .idle
                return
            }
            let release = latest.toRelease()
            self.state = .available(release)
            if release.mandatory {
                DispatchQueue.main.async { self.onMandatory?(release) }
            }
        }
        checkTask?.resume()

        if ProcessInfo.processInfo.environment["VW_UPDATE_DEBUG"] != nil {
            print("[update] check \(url.absoluteString)")
        }
    }

    // MARK: 下载

    /// 用户点「立即更新」
    func download(_ release: UpdateRelease, attempt: Int = 0) {
        guard let url = release.downloadURL else {
            state = .failed("服务端没给出下载地址")
            return
        }
        downloadStartedAt = Date()
        state = .downloading(release, 0)

        let task = session.downloadTask(with: url) { [weak self] loc, resp, err in
            guard let self else { return }
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

            // 签名有效期 1 小时：下载拖太久（>50 分钟）或直接 403，就重新查一次拿新地址
            let stale = Date().timeIntervalSince(self.downloadStartedAt) > 50 * 60
            if stale || code == 403 || code == 401 {
                self.redownload(release, attempt: attempt, reason: "链接过期")
                return
            }
            guard err == nil, let loc else {
                self.state = .failed("下载没成功：\(err?.localizedDescription ?? "网络错误")")
                return
            }
            guard let data = try? Data(contentsOf: loc) else {
                self.state = .failed("下载的文件读不出来")
                return
            }
            // 校验 SHA256：不匹配就删掉重试一次，还不行就静默放弃（下次轮询再试）
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let want = release.sha256.lowercased()
            if !want.isEmpty, digest != want {
                try? FileManager.default.removeItem(at: loc)
                if attempt < 1 {
                    self.redownload(release, attempt: attempt + 1, reason: "校验不通过")
                } else {
                    self.state = .idle
                    if ProcessInfo.processInfo.environment["VW_UPDATE_DEBUG"] != nil {
                        print("[update] sha256 mismatch, giving up")
                    }
                }
                return
            }

            let name = "Dòng-\(release.version).dmg"
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dst)
            do {
                try FileManager.default.moveItem(at: loc, to: dst)
            } catch {
                self.state = .failed("下载好了但存不下来")
                return
            }
            self.state = .ready(release, dst)
            DispatchQueue.main.async {
                // 能写自己所在的目录就当场装好再重开；装不了才退回「打开 dmg 让人自己拖」
                self.install(release, dmg: dst)
            }
        }
        downloadTask = task
        task.resume()

        // 进度：直接读 task.progress，免得为这点小事去挂 delegate
        progressTimer?.invalidate()
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self, let task = self.downloadTask else { return }
            if case .downloading(let r, _) = self.state {
                self.state = .downloading(r, min(max(task.progress.fractionCompleted, 0), 1))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        progressTimer = t
    }

    private func redownload(_ release: UpdateRelease, attempt: Int, reason: String) {
        if ProcessInfo.processInfo.environment["VW_UPDATE_DEBUG"] != nil {
            print("[update] re-check for fresh url (\(reason)) attempt=\(attempt)")
        }
        downloadTask?.cancel()
        downloadTask = nil
        // 重新查一次，拿新的 download_url 再下
        var comps = URLComponents(url: Api.path("/api/update/check"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "version", value: Self.currentVersion)]
        guard let url = comps?.url else { state = .idle; return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let parsed = try? JSONDecoder().decode(CheckResponse.self, from: data),
                  let latest = parsed.latest,
                  Self.isNewer(latest.version, than: Self.currentVersion) else {
                self.state = .idle
                return
            }
            self.download(latest.toRelease(), attempt: attempt)
        }.resume()
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// a 是否比 b 新。按「点分段、段内取数字」逐段比，缺位补 0。
    /// 服务端返回的 build 恒为 0（只按版本号比较），所以不能拿 build 做判断。
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = versionParts(a), y = versionParts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func versionParts(_ v: String) -> [Int] {
        v.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
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

    // MARK: 安装

    /// 下好之后直接就地替换：挂载 dmg → 拷到临时名 → 删旧的 → 改名 → 重启自己。
    /// 装不了（没写权限 / 挂载失败 / 包里版本不对）就退回老办法：打开 dmg 让人自己拖。
    private func install(_ release: UpdateRelease, dmg: URL) {
        let target = Bundle.main.bundlePath
        let parent = (target as NSString).deletingLastPathComponent
        let debug = ProcessInfo.processInfo.environment["VW_UPDATE_DEBUG"] != nil

        guard FileManager.default.isWritableFile(atPath: parent) else {
            if debug { print("[update] install: \(parent) 不可写，退回手动安装") }
            state = .ready(release, dmg)
            NSWorkspace.shared.open(dmg)
            return
        }

        state = .installing(release)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let mnt = fm.temporaryDirectory.appendingPathComponent("dong-update-mnt").path
            try? fm.removeItem(atPath: mnt)
            try? fm.createDirectory(atPath: mnt, withIntermediateDirectories: true)

            let mounted = Self.run("/usr/bin/hdiutil",
                                   ["attach", dmg.path, "-nobrowse", "-readonly",
                                    "-noautoopen", "-mountpoint", mnt]) == 0
            let names = mounted ? ((try? fm.contentsOfDirectory(atPath: mnt)) ?? []) : []
            guard let appName = names.first(where: { $0.hasSuffix(".app") }) else {
                if debug { print("[update] install: 挂载失败或卷里没有 .app") }
                Self.run("/usr/bin/hdiutil", ["detach", mnt, "-quiet"])
                DispatchQueue.main.async {
                    self.state = .failed("安装包读不出来，改成手动安装")
                    NSWorkspace.shared.open(dmg)
                }
                return
            }

            let src = mnt + "/" + appName
            let inside = NSDictionary(contentsOfFile: src + "/Contents/Info.plist")
            let newVer = inside?["CFBundleShortVersionString"] as? String ?? ""
            // 包里必须真的是更新的版本：防止服务端把下载地址指错，把人换成旧版
            guard Self.isNewer(newVer, than: Self.currentVersion) else {
                if debug { print("[update] install: 包内版本 \(newVer) 不比当前的 \(Self.currentVersion) 新") }
                Self.run("/usr/bin/hdiutil", ["detach", mnt, "-quiet"])
                DispatchQueue.main.async {
                    self.state = .failed("安装包里的版本不对（\(newVer)），已放弃安装")
                }
                return
            }

            // 换 App 必须在它退出后才能做，所以交给一个脚本：等我们死了再动手
            let script = """
            #!/bin/sh
            OLD_PID="$1"; SRC="$2"; DST="$3"; VOL="$4"; DMG="$5"
            i=0
            while kill -0 "$OLD_PID" 2>/dev/null && [ "$i" -lt 150 ]; do sleep 0.2; i=$((i+1)); done
            sleep 0.4
            PARENT=$(dirname "$DST")
            TMP="$PARENT/.dong-new-$$.app"
            rm -rf "$TMP"
            if /usr/bin/ditto "$SRC" "$TMP"; then
              /usr/bin/xattr -dr com.apple.quarantine "$TMP" 2>/dev/null
              rm -rf "$DST"
              if mv "$TMP" "$DST"; then
                [ -n "$VOL" ] && /usr/bin/hdiutil detach "$VOL" -quiet 2>/dev/null
                rm -f "$DMG"
                /usr/bin/open -n "$DST"
              fi
            fi
            rm -f "$0"
            """
            let helper = fm.temporaryDirectory.appendingPathComponent("dong-install.sh")
            do {
                try script.write(to: helper, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
            } catch {
                if debug { print("[update] install: 写安装脚本失败 \(error)") }
                Self.run("/usr/bin/hdiutil", ["detach", mnt, "-quiet"])
                DispatchQueue.main.async {
                    self.state = .failed("安装脚本写不下来，改成手动安装")
                    NSWorkspace.shared.open(dmg)
                }
                return
            }

            if debug {
                print("[update] install: \(src) → \(target)，等进程退出后替换")
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [helper.path, "\(ProcessInfo.processInfo.processIdentifier)",
                           src, target, mnt, dmg.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do {
                try p.run()
            } catch {
                DispatchQueue.main.async {
                    self.state = .failed("启动安装脚本失败，改成手动安装")
                    NSWorkspace.shared.open(dmg)
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.terminate(nil)
            }
        }
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    // MARK: 解码

    private struct CheckResponse: Decodable {
        let updateAvailable: Bool
        let latest: Latest?

        enum CodingKeys: String, CodingKey {
            case updateAvailable = "update_available"
            case latest
        }

        struct Latest: Decodable {
            let version: String
            let build: Int
            let notes: String?
            let mandatory: Bool?
            let fileSize: Int?
            let sha256: String?
            let downloadURL: String?

            enum CodingKeys: String, CodingKey {
                case version, build, notes, mandatory, sha256
                case fileSize = "file_size"
                case downloadURL = "download_url"
            }

            func toRelease() -> UpdateRelease {
                UpdateRelease(
                    version: version,
                    build: build,
                    notes: notes ?? "",
                    mandatory: mandatory ?? false,
                    fileSize: fileSize ?? 0,
                    sha256: sha256 ?? "",
                    downloadURL: downloadURL.flatMap { URL(string: $0) })
            }
        }
    }
}

// MARK: - 说明
//
// 进度不走 URLSessionDownloadDelegate：这里用 completionHandler 版本，
// 每 0.4 秒读一次 task.progress 就够用了，也免得两套回调互相打架。
