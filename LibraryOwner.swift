import Foundation

/// 壁纸库归属：一台机器上，活动壁纸库永远只属于「当前这个身份」。
///
/// 两条规则（用户 2026-11-25 明确要求）：
///   1. 登录后只显示该账号里的壁纸；账号是空的，就把本地现有壁纸并进这个账号。
///   2. 退出登录后，这台机器上不能再显示该账号的壁纸。
///      （别人登你账号、退出后还能看到你的壁纸，这不能接受。）
///
/// 实现方式是最小代价的**目录切换**，不是复制：
///   - `wallpapers/`        活动库，界面只读这里
///   - `library-cache/<id>/` 非活动库（匿名 or 上一次的账号）
///   - `library-owner.json`  记录活动库属于谁
///
/// 退出登录时账号的壁纸**直接删掉**（云端有副本，登录会重新拉），不留缓存——
/// 这是隐私要求：文件不该以任何形式留在本机。只有「登录前的匿名库」会被收进 cache 并还原。
enum LibraryOwner {

    static let anonymous = "anonymous"

    private static var stateFile: URL {
        Source.support.appendingPathComponent("library-owner.json")
    }

    private static var cacheRoot: URL {
        Source.support.appendingPathComponent("library-cache")
    }

    private static func cacheDir(_ owner: String) -> URL {
        cacheRoot.appendingPathComponent(owner, isDirectory: true)
    }

    /// 当前活动库属于谁（"anonymous" 或 userId）
    static var current: String {
        guard let d = try? Data(contentsOf: stateFile),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let v = o["owner"] as? String, !v.isEmpty else { return anonymous }
        return v
    }

    private static func setCurrent(_ owner: String) {
        let data = try? JSONSerialization.data(withJSONObject: ["owner": owner])
        try? data?.write(to: stateFile, options: .atomic)
    }

    // MARK: 切换

    /// 登录成功后调用。`remoteIsEmpty` = 云端清单里没有有效条目。
    /// - 账号为空：把当前本地库并进账号（随后同步会上传）
    /// - 账号非空：把当前本地库收进 cache，换出这个账号自己的库
    @discardableResult
    static func activate(accountId: String, remoteIsEmpty: Bool) -> String {
        let prev = current
        guard prev != accountId else { return "已在用这个账号的库" }

        if remoteIsEmpty {
            // 并进去：不动文件，只改归属
            setCurrent(accountId)
            return "账号为空，已把本地 \(count()) 张并入这个账号"
        }

        let moved = move(Source.libraryDir, to: cacheDir(prev))
        let restored = move(cacheDir(accountId), to: Source.libraryDir)
        setCurrent(accountId)
        return "已切换：收起 \(moved) 张，换出这个账号的 \(restored) 张"
    }

    /// 退出登录：把账号的壁纸移出活动库（删除），再还原登录前的匿名库
    @discardableResult
    static func restoreAnonymous() -> String {
        let prev = current
        guard prev != anonymous else { return "当前就是本地库" }

        let removed = deleteContents(Source.libraryDir)
        let restored = move(cacheDir(anonymous), to: Source.libraryDir)
        setCurrent(anonymous)
        return "已退出：移除 \(removed) 张，还原本地 \(restored) 张"
    }

    // MARK: 文件操作

    private static func count() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: Source.libraryDir.path).count) ?? 0
    }

    /// 同一卷内是 rename，几百 MB 也是毫秒级
    @discardableResult
    private static func move(_ from: URL, to: URL) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { return 0 }
        try? fm.createDirectory(at: to, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? []
        var n = 0
        for item in items {
            let dst = to.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: dst)          // 同名旧文件直接替换
            if (try? fm.moveItem(at: item, to: dst)) != nil { n += 1 }
        }
        return n
    }

    @discardableResult
    private static func deleteContents(_ dir: URL) -> Int {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var n = 0
        for item in items {
            if (try? fm.removeItem(at: item)) != nil { n += 1 }
        }
        return n
    }

    /// 调试用：把归属和目录内容打出来
    static func debugSummary() -> String {
        let cache = (try? FileManager.default.contentsOfDirectory(atPath: cacheRoot.path)) ?? []
        return "owner=\(current) active=\(count()) cache=\(cache.sorted())"
    }
}
