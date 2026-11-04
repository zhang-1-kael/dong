import Foundation

/// 内置默认壁纸。
///
/// 随 App 分发的素材放在 `Contents/Resources/presets/`，第一次启动时复制进
/// 用户自己的壁纸库。搬完就跟自己加的壁纸一样——能删、能换、能改名。
/// 删掉的不会被重新塞回来（认标记文件）。
enum Presets {

    /// 预置批次。以后想给老用户补新素材，把这个数字加 1 就行，
    /// 已装过 v1 的人会重新走一次导入，把新一批补上。
    static let batch = 1

    private static var sourceDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("presets")
    }

    private static var markerURL: URL {
        LockScreen.base.appendingPathComponent("presets-v\(batch).installed")
    }

    private static let videoExts: Set<String> = ["mp4", "mov", "m4v"]

    /// 有预置素材时才做事；搬过就记一笔。返回这次复制了几个文件。
    /// 包里没带 presets（开发构建）时直接返回，也不写标记——以后带上还能补。
    @discardableResult
    static func installIfNeeded(into library: URL = Source.libraryDir) -> Int {
        let fm = FileManager.default
        if fm.fileExists(atPath: markerURL.path) { return 0 }
        guard let src = sourceDir, fm.fileExists(atPath: src.path) else { return 0 }

        try? fm.createDirectory(at: LockScreen.base, withIntermediateDirectories: true)
        try? fm.createDirectory(at: library, withIntermediateDirectories: true)

        let files = (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? []
        var copied = 0
        for file in files where videoExts.contains(file.pathExtension.lowercased()) {
            let dst = library.appendingPathComponent(file.lastPathComponent)
            // 同名文件已在库里就跳过：可能是用户自己放过一份，别覆盖
            if fm.fileExists(atPath: dst.path) { continue }
            if (try? fm.copyItem(at: file, to: dst)) != nil { copied += 1 }
        }

        try? Data("\(copied)".utf8).write(to: markerURL)
        return copied
    }
}
