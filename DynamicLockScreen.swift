import AVFoundation
import Foundation

/// 「锁屏动态」。
///
/// 系统锁屏层只接受 wallpaper extension 提供的画面，普通 App 的窗口盖不上去；
/// 而 Dòng 的桌面是自绘窗口。两边能共存的唯一形态是：
///   桌面 → 主程序自绘（现有链路，不动）
///   锁屏 → 系统壁纸扩展播放（`alwaysPauseDesktop = true` 时桌面自动暂停）
///
/// 所以这里只做两件事：把当前视频复制进扩展的沙盒容器、把 prefs 写成「仅锁屏播放」。
/// 系统壁纸的选择必须由用户在「设置 → 墙纸」里点一次，代码不能代劳。
enum DynamicLockScreen {

    static let extBundleID = "com.zhanghangshuo.dong.lockscreen"
    static let defaultsKey = "dynamicLockScreen"

    /// 固定条目 id 和固定文件名。
    ///
    /// 系统壁纸的 Store 里记的是「provider + 条目 id + 文件路径」。
    /// 如果每次换壁纸都新建 UUID 目录，Store 里那条记录就指向了已经不存在的路径，
    /// 系统会退回播容器里剩下的唯一一段视频 —— 表现就是「锁屏和桌面不是同一个」。
    /// 所以这里永远复用同一个目录、同一个文件名，换壁纸只覆盖内容。
    private static let fixedEntryID = "D0D00000-0000-4000-8000-000000000001"
    private static let fixedFileName = "lock.mp4"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// 扩展是沙盒进程，读不到 `~/Library/Application Support`，只能读自己的容器。
    static var containerDocs: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(extBundleID)/Data/Documents")
    }

    /// 把视频部署进去。目录和文件名都是固定的，换壁纸只覆盖内容。
    @discardableResult
    static func deploy(video: URL) -> Bool {
        guard video.isFileURL else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: video.path) else { return false }

        let videosDir = containerDocs.appendingPathComponent("videos")
        let dir = videosDir.appendingPathComponent(fixedEntryID)
        let dest = dir.appendingPathComponent(fixedFileName)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 同一段视频（大小一致）就不重复复制，省一次 20MB+ 的写入
        let sameSize = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            == (try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        if !fm.fileExists(atPath: dest.path) || !sameSize {
            try? fm.removeItem(at: dest)
            do { try fm.copyItem(at: video, to: dest) } catch { return false }
        }

        // 缩略图复用锁屏抽帧，省一次解码
        if let frame = LockScreen.ensureFrame(for: video) {
            let thumb = dir.appendingPathComponent("thumbnail.jpg")
            try? fm.removeItem(at: thumb)
            try? fm.copyItem(at: frame, to: thumb)
        }

        let meta: [String: Any] = [
            "id": fixedEntryID,
            "name": video.deletingPathExtension().lastPathComponent,
            "filename": fixedFileName,
            "duration": 0.0,
            "fps": 0.0,
            "resolution": ["width": 0.0, "height": 0.0],
            "dateAdded": Date().timeIntervalSinceReferenceDate,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta) {
            try? data.write(to: dir.appendingPathComponent("metadata.json"))
        }

        // 容器里只留这一个条目，避免系统 fallback 到别的视频
        if let others = try? fm.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil) {
            for url in others where url.lastPathComponent != fixedEntryID {
                try? fm.removeItem(at: url)
            }
        }
        writePrefs()
        return true
    }

    /// 通知扩展库变了，让它立刻重扫（不用等下次打开设置）
    static func notifyLibraryChanged() {
        let name = "\(extBundleID).libraryChanged" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true
        )
    }

    private static func writePrefs() {
        let prefs: [String: Any] = [
            "userPaused": false,
            // 必须是 false。
            // 实测：锁屏瞬间系统会先发 mode=locked，随即又切回 mode=default，
            // 而 alwaysPauseDesktop=true 会在 default 下无条件暂停 ——
            // 表现就是「锁屏播一小会儿就静止」。
            "alwaysPauseDesktop": false,
            // 桌面被 Dòng 自己的全屏窗口盖住时暂停，省掉一份解码；
            // 锁屏没有遮挡，照常播放。
            "pauseWhenOccluded": true,
            "desktopOccluded": false,
            "occludedDisplays": [Int](),
        ]
        try? FileManager.default.createDirectory(at: containerDocs, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: prefs) {
            try? data.write(to: containerDocs.appendingPathComponent("phosphene-prefs.json"))
        }
    }

    /// 系统壁纸当前是否选中了 Dòng 的扩展。
    /// 用户换过壁纸后这里会变 false，UI 需要提示重新去设置里选一次。
    static var isSystemWallpaperSelected: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let displays = plist["Displays"] as? [String: Any],
              let display = displays.values.first as? [String: Any],
              let desktop = display["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let provider = choices.first?["Provider"] as? String
        else { return false }
        return provider == extBundleID
    }

    /// 关掉功能时清掉容器里的副本（系统壁纸的选中状态由用户自己换回去）
    static func clear() {
        let fm = FileManager.default
        let videosDir = containerDocs.appendingPathComponent("videos")
        try? fm.removeItem(at: videosDir.appendingPathComponent(fixedEntryID))
    }
}
