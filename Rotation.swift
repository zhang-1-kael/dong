import Foundation
import AppKit

/// 壁纸自动轮换：换下一张的规则（随机 / 顺序）+ 四种触发条件（启动、定时、解锁、唤醒）。
///
/// 存 UserDefaults，键前缀跟 `Tuning` 一样用 `VWTuning.`，改完广播 `changed`。
/// 具体"换哪张"不在这里决定 —— 由 App 侧回调 `onRotate` 处理，这里只负责"什么时候该换"。
enum Rotation {

    enum Mode: String {
        /// 随机挑一张（不会挑到当前这张）
        case random
        case sequential
    }

    enum Key {
        static let enabled = "rotateEnabled"
        static let mode = "rotateMode"
        static let onLaunch = "rotateOnLaunch"
        static let interval = "rotateInterval"
        static let onUnlock = "rotateOnUnlock"
        static let onWake = "rotateOnWake"
    }

    static let changed = Notification.Name("VWRotationChanged")
    private static let prefix = "VWTuning."
    private static var ud: UserDefaults { .standard }

    private static func flag(_ key: String, _ fallback: Bool) -> Bool {
        guard ud.object(forKey: prefix + key) != nil else { return fallback }
        return ud.bool(forKey: prefix + key)
    }

    private static func setFlag(_ v: Bool, _ key: String) {
        ud.set(v, forKey: prefix + key)
        notify(key)
    }

    private static func notify(_ key: String) {
        NotificationCenter.default.post(name: changed, object: nil, userInfo: ["key": key])
    }

    /// 总开关。默认关：不主动改变用户已经挑好的固定壁纸
    static var enabled: Bool {
        get { flag(Key.enabled, false) }
        set { setFlag(newValue, Key.enabled) }
    }

    /// 换下一张的规则
    static var mode: Mode {
        get { Mode(rawValue: ud.string(forKey: prefix + Key.mode) ?? "") ?? .random }
        set {
            ud.set(newValue.rawValue, forKey: prefix + Key.mode)
            notify(Key.mode)
        }
    }

    /// 每次启动 App（开机后首次登录也会启动）切一张。默认开：这是用户最常要的那条
    static var onLaunch: Bool {
        get { flag(Key.onLaunch, true) }
        set { setFlag(newValue, Key.onLaunch) }
    }

    /// 定时切换间隔（秒）。0 = 不定时
    static var interval: Double {
        get {
            guard ud.object(forKey: prefix + Key.interval) != nil else { return 0 }
            return max(0, ud.double(forKey: prefix + Key.interval))
        }
        set {
            ud.set(max(0, newValue), forKey: prefix + Key.interval)
            notify(Key.interval)
        }
    }

    /// 锁屏解锁时切一张
    static var onUnlock: Bool {
        get { flag(Key.onUnlock, false) }
        set { setFlag(newValue, Key.onUnlock) }
    }

    /// 从睡眠唤醒时切一张
    static var onWake: Bool {
        get { flag(Key.onWake, false) }
        set { setFlag(newValue, Key.onWake) }
    }

    /// 定时下拉的预设（标题, 秒）。UI 只用这几个，避免用户填出没意义的值
    static let intervalOptions: [(title: String, seconds: Double)] = [
        ("不定时", 0),
        ("每 15 分钟", 15 * 60),
        ("每 30 分钟", 30 * 60),
        ("每 1 小时", 60 * 60),
        ("每 3 小时", 3 * 60 * 60),
        ("每 6 小时", 6 * 60 * 60),
        ("每天", 24 * 60 * 60),
    ]

    static func intervalTitle(_ v: Double) -> String {
        intervalOptions.first { abs($0.seconds - v) < 1 }?.title ?? "每 1 小时"
    }

    /// 算出下一张的下标。抽成纯函数：调用方只拿结果去切，这里不碰任何视图，
    /// 也方便隔离测试。count <= 1 / 下标越界都返回 nil（没得换）。
    static func nextIndex(current: Int, count: Int, mode: Mode? = nil) -> Int? {
        guard count > 1, current >= 0, current < count else { return nil }
        switch mode ?? self.mode {
        case .random:
            // 从「不含当前这张」里挑，保证每次一定换掉
            return (0..<count).filter { $0 != current }.randomElement()
        case .sequential:
            return (current + 1) % count
        }
    }
}

/// 调度器：只管"什么时候该换"，换哪张交给 `onRotate`。
final class WallpaperRotator: NSObject {

    /// 参数是触发源（launch / timer / unlock / wake），只用于埋点
    var onRotate: ((String) -> Void)?

    private var timer: Timer?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged(_:)),
            name: Rotation.changed, object: nil)

        scheduleTimer()
    }

    /// 启动时那一次。App 侧的 videos 已经加载好再调
    func fireLaunchIfNeeded() {
        guard Rotation.enabled, Rotation.onLaunch else { return }
        onRotate?("launch")
    }

    @objc private func screenUnlocked(_ n: Notification) {
        guard Rotation.enabled, Rotation.onUnlock else { return }
        onRotate?("unlock")
    }

    @objc private func didWake(_ n: Notification) {
        guard Rotation.enabled, Rotation.onWake else { return }
        onRotate?("wake")
    }

    /// 设置一变就重建定时器（改间隔 / 开关总开关都要立刻生效）
    @objc private func settingsChanged(_ n: Notification) {
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard Rotation.enabled else { return }
        let iv = Rotation.interval
        // 小于 1 分钟当作关闭：既没意义，也免得误设成 1 秒把 CPU 拉满
        guard iv >= 60 else { return }
        let t = Timer(timeInterval: iv, repeats: true) { [weak self] _ in
            guard Rotation.enabled else { return }
            self?.onRotate?("timer")
        }
        t.tolerance = min(60, iv * 0.05)   // 允许系统合并唤醒，省电
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit {
        timer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
