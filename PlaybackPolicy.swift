import Foundation
import AppKit
import CoreGraphics

/// 动态壁纸自动暂停策略。
///
/// 借鉴 Lively Wallpaper 的 `Suspend/Playback.cs`：壁纸是背景，前景该独占资源时主动让路。
/// 这里只做「暂停 / 续播 AVPlayer」，**不 teardown 窗口、不重建 looper** ——
/// 条件解除后画面原地接上，不闪黑、不重新解码第一帧。
///
/// 信号汇总：1 秒定时器 + 系统通知（锁屏/息屏、开关变更）。
/// 每秒成本只有一次 CGWindowList 查询，且只在壁纸接管桌面时才做。
final class PlaybackPolicy: NSObject {

    /// 暂停原因。同时命中多条时取第一条（锁屏最该停）。
    enum Reason: String {
        case locked
        case fullscreen
        case lowBattery

        /// 给用户看的短文案（菜单栏提示用）
        var label: String {
            switch self {
            case .locked:     return "锁屏"
            case .fullscreen: return "前台全屏"
            case .lowBattery: return "低电量模式"
            }
        }
    }

    /// 壁纸当前是否接管桌面。关掉了就不该做任何暂停动作。
    var isActive: () -> Bool = { true }
    /// 需要暂停（主线程回调）
    var onPause: (Reason) -> Void = { _ in }
    /// 条件解除、需要续播（主线程回调）
    var onResume: () -> Void = {}

    private var timer: Timer?
    private var screenAsleep = false
    private var current: Reason?

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked(_:)),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked(_:)),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(self, selector: #selector(screensDidSleep(_:)),
                        name: NSWorkspace.screensDidSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(screensDidWake(_:)),
                        name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tuningChanged(_:)),
                                               name: Tuning.changed, object: nil)

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    /// 壁纸被重新启用 / 关闭后强制重判：否则内部还记着旧原因，
    /// 条件没变时 `tick()` 会认为状态没变化，不再回调一次暂停。
    func invalidate() {
        current = nil
        tick()
    }

    // MARK: 信号源

    @objc private func screenLocked(_ n: Notification) { screenAsleep = true; tick() }
    @objc private func screenUnlocked(_ n: Notification) { screenAsleep = false; tick() }
    @objc private func screensDidSleep(_ n: Notification) { screenAsleep = true; tick() }
    @objc private func screensDidWake(_ n: Notification) { screenAsleep = false; tick() }

    @objc private func tuningChanged(_ n: Notification) {
        guard let key = n.userInfo?["key"] as? String else { return }
        guard key == Tuning.Key.pauseOnFullscreen || key == Tuning.Key.pauseOnLock
                || key == Tuning.Key.pauseOnLowBattery else { return }
        // 刚关掉某个开关时，若当前正因它暂停，立刻续播，不必等下一秒
        tick()
    }

    /// 低电量模式（macOS 12+）。不是「用电池就停」——那样笔记本用户永远看不到壁纸。
    private var lowPowerMode: Bool {
        if #available(macOS 12.0, *) { return ProcessInfo.processInfo.isLowPowerModeEnabled }
        return false
    }

    /// 前台 App 是否有窗口铺满某一块屏（全屏应用 / 全屏游戏）。
    ///
    /// 用 CGWindowList 轮询而不是 NSWorkspace 的 activation 通知：后者只在切换 App 时来一次，
    /// 同一个 App 进出全屏不会通知，必须看窗口几何。
    private var hasFullscreenForegroundApp: Bool {
        guard Tuning.pauseOnFullscreen else { return false }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        // 壁纸库 / 菜单面板是我们自己的窗口，不算「前景独占」
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let display = CGDisplayBounds(CGDirectDisplayID(num.uint32Value))
            for win in list {
                guard let owner = (win[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
                      owner == Int(pid) else { continue }
                guard let b = win[kCGWindowBounds as String] as? [String: Any] else { continue }
                let x = (b["X"] as? NSNumber)?.doubleValue ?? 0
                let y = (b["Y"] as? NSNumber)?.doubleValue ?? 0
                let w = (b["Width"] as? NSNumber)?.doubleValue ?? 0
                let h = (b["Height"] as? NSNumber)?.doubleValue ?? 0
                let r = CGRect(x: x, y: y, width: w, height: h)
                // 12pt 容差：全屏窗口有时比 display 小一两像素，或带菜单栏留白
                let pad: CGFloat = 12
                if r.minX <= display.minX + pad, r.minY <= display.minY + pad,
                   r.maxX >= display.maxX - pad, r.maxY >= display.maxY - pad {
                    return true
                }
            }
        }
        return false
    }

    private func resolved() -> Reason? {
        guard isActive() else { return nil }
        if screenAsleep && Tuning.pauseOnLock { return .locked }
        if hasFullscreenForegroundApp { return .fullscreen }
        if Tuning.pauseOnLowBattery && lowPowerMode { return .lowBattery }
        return nil
    }

    // MARK: 判定

    @objc private func tick() {
        let next = resolved()
        guard next != current else { return }
        if let r = next {
            current = r
            onPause(r)
        } else {
            current = nil
            onResume()
        }
    }
}
