import Foundation
import AVFoundation

/// 画面微调设置。
///
/// 分两层，别混在一起：
/// - 实时层（speed / loopStart / loopLength / brightness）：改完广播 `changed`，
///   AppDelegate 直接改正在播的 player 或桌面叠层，不需要重新转码。
/// - 生成层（outputFPS / fadeSeconds / maxDuration）：写进视频文件的参数，
///   只有下次导入、或点「重新生成这张壁纸」才生效。
///
/// 存取方式跟 `LibraryBackdrop` 一致：UserDefaults + 通知，不引第三方依赖。
enum Tuning {

    enum Key {
        static let speed = "speed"
        static let loopStart = "loopStart"
        static let loopLength = "loopLength"
        static let brightness = "brightness"
        static let outputFPS = "outputFPS"
        static let fade = "fade"
        static let maxDuration = "maxDuration"
    }

    static let changed = Notification.Name("VWTuningChanged")
    static let regenerateRequested = Notification.Name("VWTuningRegenerateRequested")

    private static let prefix = "VWTuning."

    private static func read(_ key: String, _ fallback: Double) -> Double {
        let ud = UserDefaults.standard
        guard ud.object(forKey: prefix + key) != nil else { return fallback }
        return ud.double(forKey: prefix + key)
    }

    private static func write(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: prefix + key)
        NotificationCenter.default.post(name: changed, object: nil, userInfo: ["key": key])
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    // MARK: 实时生效 · 播放层

    /// 播放速度 0.5×…2×，默认 1×。AVPlayer 在这个区间内不会变调（桌面播放本来就是静音）
    static var speed: Double {
        get { clamp(read(Key.speed, 1), 0.5, 2) }
        set { write(Key.speed, clamp(newValue, 0.5, 2)) }
    }

    /// 只循环视频里的哪一段：起点（秒），默认 0
    static var loopStart: Double {
        get { max(0, read(Key.loopStart, 0)) }
        set { write(Key.loopStart, max(0, newValue)) }
    }

    /// 循环片段长度（秒），0 = 从起点一直循环到片尾
    static var loopLength: Double {
        get { max(0, read(Key.loopLength, 0)) }
        set { write(Key.loopLength, max(0, newValue)) }
    }

    /// 明暗 −1…1，0 = 不动画面。用一层白/黑半透明叠层实现，零逐帧成本
    static var brightness: Double {
        get { clamp(read(Key.brightness, 0), -1, 1) }
        set { write(Key.brightness, clamp(newValue, -1, 1)) }
    }

    /// 交给 `AVPlayerLooper` 的循环区间；整段循环时返回 nil（用默认构造器，行为跟以前完全一样）
    static func loopRange(total: Double) -> CMTimeRange? {
        guard total > 0.6 else { return nil }
        let start = min(loopStart, max(0, total - 0.6))
        let remain = total - start
        let length = loopLength > 0 ? min(loopLength, remain) : remain
        guard length > 0.5, start > 0.01 || length < remain - 0.01 else { return nil }
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                           duration: CMTime(seconds: length, preferredTimescale: 600))
    }

    // MARK: 重新生成后生效 · 导入层

    /// 输出帧率：0 = 跟随源（上限 30），否则 24 / 30 / 60
    static var outputFPS: Int {
        get { Int(read(Key.outputFPS, 0)) }
        set { write(Key.outputFPS, Double(newValue)) }
    }

    /// 首尾交叉淡化秒数，0 = 关闭，默认 0.4
    static var fadeSeconds: Double {
        get { clamp(read(Key.fade, 0.4), 0, 0.8) }
        set { write(Key.fade, clamp(newValue, 0, 0.8)) }
    }

    /// 导入时最长保留多少秒，0 = 不限制
    static var maxDuration: Double {
        get { max(0, read(Key.maxDuration, 0)) }
        set { write(Key.maxDuration, max(0, newValue)) }
    }

    /// 转码用的实际帧率。默认沿袭老策略（跟随源、上限 30），选了档位才覆盖
    static func effectiveFPS(source: Double) -> Int {
        let chosen = outputFPS
        return chosen > 0 ? chosen : max(1, min(30, Int(source.rounded())))
    }

    /// 一键还原：删掉所有键，通知里带 reset 让播放层整体重建一次
    static func reset() {
        for k in [Key.speed, Key.loopStart, Key.loopLength, Key.brightness,
                  Key.outputFPS, Key.fade, Key.maxDuration] {
            UserDefaults.standard.removeObject(forKey: prefix + k)
        }
        NotificationCenter.default.post(name: changed, object: nil, userInfo: ["key": "reset"])
    }
}
