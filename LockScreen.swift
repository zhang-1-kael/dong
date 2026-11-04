import Foundation
import AVFoundation
import Cocoa

/// 锁屏同步。
///
/// macOS 的锁屏画面 = 当前**桌面壁纸**。桌面本身由覆盖窗口放视频，所以做法是：
/// 把桌面壁纸设成当前视频里的一帧——锁屏看到同一张画，桌面看到视频在动。
/// （不写系统航拍库，因此不需要管理员权限，也不会被系统回退。）
enum LockScreen {

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var base: URL { home.appendingPathComponent("Library/Application Support/VideoWallpaper") }
    static var framesDir: URL { base.appendingPathComponent("locks") }

    static func frameURL(for video: URL) -> URL {
        framesDir.appendingPathComponent(video.deletingPathExtension().lastPathComponent + ".jpg")
    }

    /// 从视频里抽一帧存成图片（同一段视频只抽一次）
    static func ensureFrame(for video: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: framesDir, withIntermediateDirectories: true)
        let out = frameURL(for: video)

        let vDate = (try? fm.attributesOfItem(atPath: video.path))?[.modificationDate] as? Date ?? .distantPast
        let fDate = (try? fm.attributesOfItem(atPath: out.path))?[.modificationDate] as? Date ?? .distantPast
        if fm.fileExists(atPath: out.path), fDate >= vDate { return out }

        let asset = AVURLAsset(url: video)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let dur = CMTimeGetSeconds(asset.duration)
        let t = (dur.isFinite && dur > 1) ? dur * 0.35 : 0.5

        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1600, height: 1000)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        gen.maximumSize = CGSize(width: screen.width * scale, height: screen.height * scale)

        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        else { return nil }
        try? data.write(to: out)
        return out
    }

    /// 把图片设为桌面壁纸（每块屏幕都设），锁屏随之同步
    /// 抽帧时已按屏幕比例裁过，用默认缩放即可铺满
    static func setDesktopPicture(_ image: URL) {
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [:])
        }
    }

    /// 对外入口：把锁屏换成这段视频的画面
    static func apply(video: URL, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            guard let frame = ensureFrame(for: video) else {
                DispatchQueue.main.async { completion?() }
                return
            }
            DispatchQueue.main.async {
                setDesktopPicture(frame)
                completion?()
            }
        }
    }
}
