import Cocoa
import AVFoundation
import CoreImage

// MARK: - 桌面层窗口（不吃焦点、不响应鼠标）

final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // 关掉 AppKit 的边框约束，允许窗口铺满整块屏幕（外扩后不留缝）
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

final class WallpaperView: NSView {
    /// 前景：画面。默认铺满裁切；只有竖屏视频才按"完整显示"
    let playerLayer = AVPlayerLayer()
    /// 补边用的模糊底：一张事先算好的静图，不是活体视频。
    /// 以前这里是第二个 AVPlayerLayer 加 CIGaussianBlur(42)：竖屏素材每帧都要对
    /// 一块比屏幕还大 12% 的区域重算一遍高斯模糊，是全 App 最贵的一笔开销，
    /// 也是「自己做的手机竖屏视频最卡」的直接原因。
    private let backdrop = CALayer()
    private let dim = CALayer()
    /// true = 铺满裁切；false = 完整显示 + 模糊补边
    private(set) var isFilled = true
    /// 模糊底准备好了没有。没准备好就整块不显示，免得先闪一块纯色。
    private var hasBackdrop = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        guard let root = layer else { return }
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true

        // 普通图层放静图：零逐帧成本，靠 contentsGravity 铺满
        backdrop.contentsGravity = .resizeAspectFill
        backdrop.masksToBounds = true
        backdrop.isHidden = true
        root.addSublayer(backdrop)

        dim.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        dim.isHidden = true
        root.addSublayer(dim)

        playerLayer.videoGravity = .resizeAspectFill
        root.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 视频原始尺寸已知后调用（尺寸只影响 isFilled，图层位置由 layoutLayers 统一处理）
    func apply(videoSize: CGSize) {
        layoutLayers()
        _ = videoSize
    }

    /// 补上预先模糊好的静图（图层只吃 CGImage，转一道更稳）
    func applyBackdrop(_ image: NSImage) {
        var rect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        backdrop.contents = cg
        hasBackdrop = true
        layoutLayers()
    }

    /// 按这台机器的负载调整压暗程度（重负载压得深些，用对比度弥补没有动态模糊）
    func applyDim(_ alpha: CGFloat) {
        dim.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
    }

    /// true = 铺满（比例一致时用），false = 完整显示 + 模糊补边
    func setFilled(_ filled: Bool) {
        isFilled = filled
        layoutLayers()
    }

    var debugInfo: String {
        "filled=\(isFilled) backHidden=\(backdrop.isHidden) hasBack=\(hasBackdrop) front=\(playerLayer.frame.size)"
    }

    func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        if isFilled {
            playerLayer.frame = b
            backdrop.isHidden = true
            dim.isHidden = true
        } else {
            // 静图本身就铺满，不用再外扩躲边缘
            backdrop.frame = b
            dim.frame = b
            playerLayer.frame = b
            dim.isHidden = !hasBackdrop
            backdrop.isHidden = !hasBackdrop
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }
}

// MARK: - 每台机器的每帧预算

/// 不写死任何一台机器的参数。只看两个数字：屏幕物理像素、素材像素。
/// 屏幕越大、素材越小（本来就在放大），补边模糊就越省力。
/// 换 5K、外接屏、手机竖屏素材都不用改代码，这里自己算。
struct RenderPlan {
    enum Load: String { case light, normal, heavy }
    let load: Load
    /// 补边静图的模糊半径
    let backdropRadius: Double
    /// 补边压暗程度
    let dimAlpha: CGFloat

    static func make(screen: NSScreen, videoSize: CGSize, screenCount: Int) -> RenderPlan {
        let scale = max(screen.backingScaleFactor, 1)
        let devicePixels = screen.frame.width * scale * screen.frame.height * scale
        let sourcePixels = max(videoSize.width * videoSize.height, 1)
        let upscale = devicePixels / sourcePixels

        var load: Load = .normal
        if devicePixels > 14_000_000 || screenCount > 1 {
            load = .heavy          // 5K / 6K / 多屏：每帧合成量大
        } else if devicePixels < 5_000_000 {
            load = .light
        }
        if upscale > 3 { load = .heavy }   // 小素材铺大屏，再叠一层模糊只是白烧算力

        switch load {
        case .light:  return RenderPlan(load: .light,  backdropRadius: 34, dimAlpha: 0.40)
        case .normal: return RenderPlan(load: .normal, backdropRadius: 26, dimAlpha: 0.44)
        case .heavy:  return RenderPlan(load: .heavy,  backdropRadius: 16, dimAlpha: 0.52)
        }
    }

    var debugText: String { "load=\(load.rawValue) radius=\(backdropRadius) dim=\(dimAlpha)" }
}

// MARK: - 补边的模糊静图

/// 取一帧 → 缩到 320px → 在小图上做高斯模糊 → 交给系统放大。
/// 在小图上模糊和在全屏上模糊差着几百倍的像素数，而结果反正都要被拉成一片雾。
/// 生成一次，之后播放期间零成本。
enum BackdropBlur {
    static func make(from video: URL, radius: Double,
                     completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: video)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 320, height: 320)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 3, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 3, preferredTimescale: 600)
            let dur = CMTimeGetSeconds(asset.duration)
            let t = (dur.isFinite && dur > 1) ? dur * 0.33 : 0.5

            guard let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600),
                                                actualTime: nil) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let ci = CIImage(cgImage: cg)
            let blurred: CIImage
            if let f = CIFilter(name: "CIGaussianBlur",
                                parameters: [kCIInputImageKey: ci,
                                             kCIInputRadiusKey: radius]),
               let out = f.outputImage {
                blurred = out
            } else {
                blurred = ci
            }
            // 按原 extent 裁掉模糊外溢出来的透明边
            let ctx = CIContext(options: [.useSoftwareRenderer: false])
            let rect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            guard let out = ctx.createCGImage(blurred, from: rect) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let img = NSImage(cgImage: out, size: NSSize(width: cg.width, height: cg.height))
            DispatchQueue.main.async { completion(img) }
        }
    }
}

// MARK: - 壁纸素材来源

enum Source {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// 数据根目录。`VW_SUPPORT_DIR` 可以整体挪走——云服务联调时用它把壁纸库、
    /// 统计队列、install-id 全部关进临时目录，一点都碰不到真实用户在用的那份。
    static let support: URL = {
        if let p = ProcessInfo.processInfo.environment["VW_SUPPORT_DIR"] {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        return home.appendingPathComponent("Library/Application Support/VideoWallpaper")
    }()

    static var libraryDir: URL {
        support.appendingPathComponent("wallpapers")
    }

    static var singleFile: URL {
        support.appendingPathComponent("wallpaper.mp4")
    }

    static let videoExts: Set<String> = ["mp4", "mov", "m4v"]

    /// 优先读壁纸库（可放多个，按文件名排序轮播），库空时退回单个文件 / 内置素材
    static func load() -> [URL] {
        // 调试：临时指定单个素材（不影响壁纸库）
        if let p = ProcessInfo.processInfo.environment["VW_VIDEO"] {
            return [URL(fileURLWithPath: (p as NSString).expandingTildeInPath)]
        }
        var list: [URL] = []
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: libraryDir, includingPropertiesForKeys: nil) {
            list = items
                .filter { videoExts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        if list.isEmpty {
            if fm.fileExists(atPath: singleFile.path) {
                list = [singleFile]
            } else if let bundled = Bundle.main.url(forResource: "wallpaper", withExtension: "mp4") {
                list = [bundled]
            }
        }
        return list
    }
}

// MARK: - 缩略图（菜单里每条壁纸前面的小预览）

enum Thumbs {
    static var dir: URL {
        Source.home.appendingPathComponent("Library/Application Support/VideoWallpaper/thumbs")
    }

    static func file(for video: URL) -> URL {
        dir.appendingPathComponent(video.deletingPathExtension().lastPathComponent + ".png")
    }

    /// 有缓存就直接用；没有（或视频更新过）就现抽一帧存起来
    static func image(for video: URL) -> NSImage? {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = file(for: video)

        let thumbDate = (try? fm.attributesOfItem(atPath: out.path))?[.modificationDate] as? Date
        let videoDate = (try? fm.attributesOfItem(atPath: video.path))?[.modificationDate] as? Date
        let needMake = (thumbDate == nil) || (videoDate != nil && thumbDate! < videoDate!)
        if needMake { generate(from: video, to: out) }

        guard let img = NSImage(contentsOf: out), img.size.height > 0 else { return nil }
        // 高度固定，宽度按原比例（菜单里不会被拉变形）
        let h: CGFloat = 44
        let w = min(img.size.width * (h / img.size.height), 90)
        img.size = NSSize(width: w, height: h)
        img.isTemplate = false
        return img
    }

    /// 取时长的 1/3 处画面当封面（避开片头转场）
    private static func generate(from video: URL, to out: URL) {
        let asset = AVURLAsset(url: video)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 256, height: 256)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

        let dur = CMTimeGetSeconds(asset.duration)
        let t = (dur.isFinite && dur > 0.5) ? dur * 0.33 : 1.0
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: out)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var videos: [URL] = []
    /// 当前播放的是第几条；一变就记住名字，下次启动接着用
    private var index = 0 {
        didSet {
            guard index >= 0, index < videos.count else { return }
            UserDefaults.standard.set(videos[index].lastPathComponent,
                                      forKey: "currentWallpaperName")
        }
    }
    private var windows: [WallpaperWindow] = []
    /// 现在只有一路解码（多屏共用），留着数组是为了少改别处的遍历
    private var players: [AVQueuePlayer] = []
    private var loopers: [AVPlayerLooper] = []
    /// 素材原始尺寸缓存：主线程只查这里，永远不读文件
    private var sizeCache: [URL: CGSize] = [:]
    private var sizeLoading: Set<URL> = []
    /// App Nap 抑制令牌，必须全程持有
    private var activityToken: NSObjectProtocol?

    /// 监听壁纸目录，外部（访达拖入、命令行拷贝）加进来的文件也能立刻出现在库里
    private var libWatcher: DispatchSourceFileSystemObject?
    private var libRescanWork: DispatchWorkItem?

    private var statusItem: NSStatusItem?
    /// 桌面有没有被接管。**第一次装默认不接管**：下载完一打开就把别人的壁纸换掉太霸道，
    /// 得他自己点一张才算数（点过之后才记住这个开关）。
    private var isShowing: Bool = {
        let d = UserDefaults.standard
        return d.object(forKey: "wallpaperEnabled") == nil ? false : d.bool(forKey: "wallpaperEnabled")
    }()
    /// 还没有做过任何选择：装好第一次启动
    private var isFirstRun: Bool {
        UserDefaults.standard.object(forKey: "wallpaperEnabled") == nil
    }
    private var isPaused = false

    private var libraryWC: LibraryWindowController?
    /// 这条导入是从哪儿来的：只用来算埋点（来源站名 + 耗时），不进任何日志文本
    enum ImportOrigin {
        case local(started: Date)
        case link(provider: String, started: Date)

        var startedAt: Date {
            switch self {
            case .local(let d), .link(_, let d): return d
            }
        }
    }
    private var importQueue: [(url: URL, background: Bool, origin: ImportOrigin)] = []
    private var isImporting = false
    private var isDownloading = false
    private var menuPanel: MenuPanelController?
    private var playTimer: Timer?
    private var lastTick = Date()
    /// 有新版本时挂在图标的提示上（非阻断）
    private var updateHint = ""

    private var launchAgentURL: URL {
        Source.home.appendingPathComponent("Library/LaunchAgents/com.zhanghangshuo.videowallpaper.plist")
    }

    private var isAutostartEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// 锁屏是否跟随壁纸（默认开）
    private var syncLockScreen: Bool = {
        let d = UserDefaults.standard
        return d.object(forKey: "syncLockScreen") == nil ? true : d.bool(forKey: "syncLockScreen")
    }()

    private func pushLockScreen() {
        guard syncLockScreen, let video = currentVideo else { return }
        LockScreen.apply(video: video)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App Nap 会把「看不见的后台 App」的提交推迟到下一个合并唤醒点。
        // 纯菜单栏 + 桌面层窗口 + 从不成为活跃 App，正好踩中这一条：
        // 表现就是画面隔一两秒停住，然后一下跳到正确位置。必须全程持有，不能只在播放时拿。
        // 注意用 AllowingIdleSystemSleep：要的是「别把我当闲置 App 降权」，
        // 不是「别让 Mac 睡觉」—— 一个壁纸 App 拦住系统睡眠是不能接受的。
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled],
            reason: "Dòng 正在渲染动态壁纸"
        )

        // 调试用：VW_APPEARANCE=dark|light 强制外观，方便截图比对两种模式下的底色
        if let want = ProcessInfo.processInfo.environment["VW_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: want == "dark" ? .darkAqua : .aqua)
        }

        // 起来就开始记帧健康：只记数字，一分钟落一行，成本近似为零
        FrameHealth.shared.start()
        // 调试用：VW_PRESETS_TEST=/tmp/xxx 把包内默认壁纸导到指定目录看结果（验证用）
        if let testDir = ProcessInfo.processInfo.environment["VW_PRESETS_TEST"] {
            let dst = URL(fileURLWithPath: testDir)
            try? FileManager.default.removeItem(at: dst)
            let n = Presets.installIfNeeded(into: dst)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: testDir)) ?? [])
                .sorted().joined(separator: " | ")
            print("[presets] imported=\(n)\n\(names)")
            exit(0)
        }

        // 随包分发的默认壁纸：第一次启动搬进用户的库。搬过（有标记）就不再动，
        // 用户后来删掉的也就不会自己长回来。
        _ = Presets.installIfNeeded()
        videos = Source.load()
        // 恢复上次选中的那条（按文件名记，删了或改名就退回第一条）
        if let name = UserDefaults.standard.string(forKey: "currentWallpaperName"),
           let i = videos.firstIndex(where: { $0.lastPathComponent == name }) {
            index = i
        }

        // 预热素材尺寸：换壁纸时就不用再等读文件，主线程也不会被卡住
        let warmUp = videos
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for u in warmUp {
                let asset = AVURLAsset(url: u)
                var size = CGSize.zero
                if let t = asset.tracks(withMediaType: .video).first {
                    let s = t.naturalSize.applying(t.preferredTransform)
                    size = CGSize(width: abs(s.width), height: abs(s.height))
                }
                DispatchQueue.main.async { self?.sizeCache[u] = size }
            }
        }

        // 调试用：VW_DUMP_MENU=1 时把菜单结构打到标准输出后退出（无屏幕录制权限时验证菜单用）
        if ProcessInfo.processInfo.environment["VW_DUMP_MENU"] != nil {
            func dump(_ menu: NSMenu, _ indent: String) {
                for it in menu.items {
                    if it.isSeparatorItem {
                        print(indent + "————————————")
                        continue
                    }
                    let mark = it.state == .on ? "✓ " : "   "
                    let pic = it.image == nil ? "" : "[图] "
                    print(indent + "\(mark)\(pic)\(it.title)\(it.isEnabled ? "" : "   [灰]")")
                    if let s = it.submenu { dump(s, indent + "    ") }
                }
            }
            dump(buildMenu(), "")
            exit(0)
        }

        buildStatusItem()
        startPlayTimer()
        startLibraryWatcher()

        // 不弹任何欢迎窗：第一次启动也直接用，桌面该怎么显示就怎么显示。
        // 没有壁纸的话把库拉起来，那里能拖视频、贴链接。
        UserDefaults.standard.set(true, forKey: "onboarded")
        // 只有他自己挑过（或开过）才去接管桌面；第一次装就静静待在菜单栏，
        // 原来那张壁纸一点都不动。
        if isShowing {
            rebuild()
            pushLockScreen()
        }
        let firstPick = isFirstRun
        // 壁纸库是空的就直接把窗口拉起来，让人知道下一步该干嘛
        // --library：升级后重新拉起时顺手把库打开
        // VW_NO_UI=1：无人值守的联调，别往屏幕上弹窗
        let quietUI = ProcessInfo.processInfo.environment["VW_NO_UI"] != nil
        if !quietUI, videos.isEmpty || ProcessInfo.processInfo.arguments.contains("--library") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showLibrary() }
        } else if !quietUI, firstPick {
            // 第一次装：把小面板弹出来让他挑一张 —— 挑了才换，不挑就一直是他原来的壁纸
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard self.menuPanel?.isShown != true, let b = self.statusItem?.button else { return }
                self.togglePanel(b)
            }
        }

        // 调试用：VW_PANEL_SHOT=/tmp/panel.png 弹出面板并画成图片后退出
        if let path = ProcessInfo.processInfo.environment["VW_PANEL_SHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let button = self.statusItem?.button { self.togglePanel(button) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    if let v = ProcessInfo.processInfo.environment["VW_PANEL_STRIP"], let d = Double(v) {
                        self.menuPanel?.debugScroll(CGFloat(d))
                    }
                    // 调试用：VW_PANEL_HOVER=3 把某张缩略图钉成悬停态，核对描边
                    if let v = ProcessInfo.processInfo.environment["VW_PANEL_HOVER"], let i = Int(v) {
                        self.menuPanel?.body.debugHover(i)
                    }
                    // 调试用：VW_PANEL_PICK=2 模拟点一张壁纸，验证切换后面板还在
                    if let v = ProcessInfo.processInfo.environment["VW_PANEL_PICK"], let i = Int(v) {
                        self.selectWallpaper(index: i)
                        print("[panel] picked=\(i) visible=\(self.menuPanel?.isShown == true)")
                    }
                    // 调试用：VW_PANEL_LINK_TEST=xxx 把文字塞进右上角链接框并回车
                    if let v = ProcessInfo.processInfo.environment["VW_PANEL_LINK_TEST"] {
                        self.menuPanel?.body.debugSubmitLink(v)
                        print("[panel] link-test=\(v)")
                    }
                    // 调试用：VW_PANEL_BUSY=42 把链接框钉成 42% 的后台生成态，核对进度条
                    if let v = ProcessInfo.processInfo.environment["VW_PANEL_BUSY"],
                       let pct = Double(v) {
                        self.menuPanel?.showImportProgress(
                            "正在优化 wm.mp4（\(Int(pct))%）", progress: pct / 100)
                    }
                    // 调试用：VW_PANEL_FOCUS=1 聚焦链接框，确认键盘焦点落在输入框上
                    let focusTest = ProcessInfo.processInfo.environment["VW_PANEL_FOCUS"] != nil
                    if focusTest {
                        self.menuPanel?.body.debugFocusLink()
                    }
                    let finish = {
                        self.menuPanel?.snapshot(to: path)
                        exit(0)
                    }
                    // 聚焦是异步的，等激活落定再截图退出
                    if focusTest {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: finish)
                    } else {
                        finish()
                    }
                }
            }
        }

        // 调试用：VW_SWAY_DUMP=/tmp/sway 把菜单栏果冻的摇摆帧导成 PNG 后退出
        if let dir = ProcessInfo.processInfo.environment["VW_SWAY_DUMP"] {
            MenuBarSway.shared.dumpFrames(to: dir)
            exit(0)
        }

        // 调试用：VW_SWAY_TEST=1 跑 1.2 秒，回报果冻轮播了几帧
        if ProcessInfo.processInfo.environment["VW_SWAY_TEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let img = self.statusItem?.button?.image
                print("[sway] ticks=\(MenuBarSway.shared.tickCount) "
                      + "image=\(img?.size ?? .zero) alpha=\(self.statusItem?.button?.alphaValue ?? -1)")
                exit(0)
            }
        }

        // 调试用：VW_SHOW_LIBRARY=1 启动时直接打开设置窗口
        if ProcessInfo.processInfo.environment["VW_SHOW_LIBRARY"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showLibrary() }
        }

        // 调试用：VW_SETTINGS_SHOT=/tmp/settings.png 把设置弹层渲染成图片后退出
        if let path = ProcessInfo.processInfo.environment["VW_SETTINGS_SHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.libraryWC == nil { self.showLibrary() }
                self.libraryWC?.debugSnapshotSettings(to: path)
                exit(0)
            }
        }

        // 调试用：VW_IMPORT_TEST=/path/a.mp4 拿一个本地视频走一遍后台导入（不联网、不弹窗），
        // 核对"只入库、不换壁纸"这条逻辑
        if let p = ProcessInfo.processInfo.environment["VW_IMPORT_TEST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("[import-test] before name=\(self.currentName) showing=\(self.isShowing) "
                      + "windows=\(self.windows.count) videos=\(self.videos.count)")
                self.importFiles([URL(fileURLWithPath: p)], background: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                print("[import-test] after name=\(self.currentName) showing=\(self.isShowing) "
                      + "windows=\(self.windows.count) videos=\(self.videos.count)")
                exit(0)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 匿名使用统计：只记「装了多少台、用了什么功能」，不含文件名和链接内容
        Analytics.shared.wipeIfDisabled()
        Analytics.shared.start()

        // 自动更新：启动 10 秒后查一次，此后每 6 小时一次（文档 §1.2）
        Updater.shared.onState = { [weak self] st in self?.updateStateChanged(st) }
        Updater.shared.onMandatory = { [weak self] r in self?.promptMandatoryUpdate(r) }
        Updater.shared.start()
    }

    // MARK: 自动更新

    private func updateStateChanged(_ state: Updater.State) {
        // 有货就点亮菜单栏角标，并在壁纸库右上角那条胶囊里说进度
        updateStatusItem()
        switch state {
        case .downloading(_, let p):
            libraryWC?.setBusy(true, progress: p, text: "正在下载新版本（\(Int(p * 100))%）…")
        case .ready(let r, _):
            libraryWC?.setBusy(false, progress: 1,
                               text: "\(r.displayName) 已下载，把 Dòng 拖进「应用程序」")
        case .installing(let r):
            libraryWC?.setBusy(true, progress: 1,
                               text: "正在装 \(r.displayName)…装好会自动重开")
        case .failed(let msg):
            libraryWC?.setBusy(false, progress: 0, text: msg)
        case .available(let r):
            // 非强制：点角标 + 右键菜单里挂一条，另外弹一次窗口问要不要更新
            updateHint = "新版本 \(r.displayName) 可用（右键菜单 → 立即更新）"
            print("[update] available \(r.displayName) build=\(r.build)")
            presentUpdatePrompt(r)
            // 调试用：VW_UPDATE_DOWNLOAD=1 拿到版本就自动下，验证 SHA256 与重试
            if ProcessInfo.processInfo.environment["VW_UPDATE_DOWNLOAD"] != nil {
                Updater.shared.download(r)
            }
        default:
            break
        }
    }

    /// 普通更新：查出新版本后弹一次窗，问「现在装还是等下」
    /// 同一个版本只问一次（存在 UserDefaults 里），免得每 15 分钟轮询都糊一脸；
    /// 点过「稍后」的，隔 3 天再问一次，避免手滑点掉就再也收不到提醒。
    private static let keyPromptedUpdate = "promptedUpdateVersion"
    private static let keyPromptedAt = "promptedUpdateAt"
    private func presentUpdatePrompt(_ r: UpdateRelease) {
        if ProcessInfo.processInfo.environment["VW_NO_UI"] != nil { return }
        // 用户已经手动点过「立即更新」在下载了，别再插一嘴
        if case .downloading = Updater.shared.state { return }
        if case .ready = Updater.shared.state { return }
        if case .installing = Updater.shared.state { return }
        let asked = UserDefaults.standard.string(forKey: Self.keyPromptedUpdate) ?? ""
        if asked == r.version {
            let at = UserDefaults.standard.double(forKey: Self.keyPromptedAt)
            guard Date().timeIntervalSince1970 - at > 72 * 3600 else { return }
        }
        UserDefaults.standard.set(r.version, forKey: Self.keyPromptedUpdate)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.keyPromptedAt)

        let a = NSAlert()
        a.messageText = "Dòng \(r.displayName) 可以用啦"
        var body = r.notes.isEmpty ? "修了些问题、手感更顺。" : r.notes
        if !r.sizeText.isEmpty {
            body += "\n\n安装包 \(r.sizeText)，点「立即更新」会自动下载、装好并重开，不用自己拖。"
        }
        a.informativeText = body
        a.alertStyle = .informational
        a.addButton(withTitle: "立即更新")
        a.addButton(withTitle: "稍后")
        // 菜单栏小工具不是前台应用，不抬高窗口层级的话，弹窗可能藏在别的窗口后面，
        // 用户就会以为「它根本没提醒我」。
        a.window.level = .floating
        a.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        a.window.makeKeyAndOrderFront(nil)
        if ProcessInfo.processInfo.environment["VW_UPDATE_DEBUG"] != nil {
            print("[update] prompt \(r.version) 已显示：visible=\(a.window.isVisible) "
                  + "level=\(a.window.level.rawValue) key=\(a.window.isKeyWindow)")
        }
        let resp = a.runModal()
        if resp == .alertFirstButtonReturn {
            UserDefaults.standard.removeObject(forKey: Self.keyPromptedUpdate)
            UserDefaults.standard.removeObject(forKey: Self.keyPromptedAt)
            Updater.shared.download(r)
        }
    }

    /// 强制更新：只给一个「立即更新」按钮，更新完才继续
    private var mandatoryPrompted = Set<Int>()
    private func promptMandatoryUpdate(_ r: UpdateRelease) {
        guard !mandatoryPrompted.contains(r.build) else { return }
        mandatoryPrompted.insert(r.build)
        let a = NSAlert()
        a.messageText = "需要更新到 \(r.displayName)"
        a.informativeText = r.notes.isEmpty ? "这个版本包含必须装上的修复。" : r.notes
        a.alertStyle = .warning
        a.addButton(withTitle: "立即更新")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
        Updater.shared.download(r)
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickPlayTime()
        for p in players { p.pause() }
        if let t = activityToken { ProcessInfo.processInfo.endActivity(t) }
        Analytics.shared.finish()
    }

    // MARK: 播放

    private var currentVideo: URL? {
        guard index >= 0 && index < videos.count else { return nil }
        return videos[index]
    }

    private var currentName: String {
        currentVideo?.deletingPathExtension().lastPathComponent ?? "（没有素材）"
    }

    @objc private func screenChanged() {
        if isShowing { rebuild() }
    }

    /// 视频原始显示尺寸（考虑旋转），读不到就返回 .zero
    private func naturalSize(of url: URL) -> CGSize {
        // 同步读 media 属性会在主线程卡几百毫秒（4K 素材尤其明显），主线程一卡，
        // 视频图层就跟着停住再补跳 —— 这正是「卡卡的」的手感。所以这里只查缓存。
        if let s = sizeCache[url] { return s }
        if !sizeLoading.contains(url) {
            sizeLoading.insert(url)
            loadSize(of: url)
        }
        return .zero
    }

    /// 后台读尺寸写缓存；只有「竖屏判定会变」时才补一次 rebuild，避免来回重建
    private func loadSize(of url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: url)
            var size = CGSize.zero
            if let track = asset.tracks(withMediaType: .video).first {
                let s = track.naturalSize.applying(track.preferredTransform)
                size = CGSize(width: abs(s.width), height: abs(s.height))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.sizeLoading.remove(url)
                self.sizeCache[url] = size
                let portrait = size.height > 0 && (size.width / size.height) < 0.98
                if portrait, self.currentVideo == url, self.isShowing {
                    self.rebuild()
                }
            }
        }
    }

    private func rebuild() {
        FrameHealth.shared.measure("rebuild") { rebuildBody() }
    }

    private func rebuildBody() {
        let wasPaused = isPaused
        teardown()
        guard isShowing, let url = currentVideo else { return }

        let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        let vsize = naturalSize(of: url)

        // 一份解码投给所有屏幕。以前每块屏各建一个 AVQueuePlayer，
        // 外接显示器时同一条素材会被解码两遍 —— 那是接屏最容易崩的地方。
        let player = AVQueuePlayer()
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .advance

        // 模板 item。以前这里给 item 设过 preferredMaximumResolution 想把解码尺寸
        // 压到屏幕像素，实测在这条解码链路上不生效（交付尺寸仍是源尺寸），已撤掉。
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        loopers.append(looper)
        players.append(player)

        var portraitPlan: RenderPlan?
        var firstPlan: RenderPlan?

        for screen in NSScreen.screens {
            // 外扩 24pt，抵消 WindowServer 对边缘的缩放，确保四边不留缝
            let frame = screen.frame.insetBy(dx: -24, dy: -24)
            let window = WallpaperWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = desktopLevel
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = false

            // 外壳铺满（含外扩），画面视图只占"屏幕那一眼"的大小 —— 不再随着外扩一起放大 2%~3%
            let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.black.cgColor
            window.contentView = host
            let view = WallpaperView(frame: host.bounds.insetBy(dx: 24, dy: 24))
            host.addSubview(view)

            // 横屏视频一律铺满：16:9 的片子放到 16:10 的屏幕上只差 11%，
            // 按「完整显示」会留下上下两条模糊补边，像画面被裁了一刀、中间又缩了一圈，很丑；
            // 而且系统桌面的静帧是按「铺满裁切」摆的，两边不一致时中间和背景还会错位。
            // 竖屏视频（手机壁纸）例外：铺满会裁掉一大半画面，仍按完整显示 + 模糊补边。
            let screenAR = screen.frame.width / max(screen.frame.height, 1)
            let videoAR = vsize.height > 0 ? vsize.width / vsize.height : screenAR
            let portrait = videoAR < 0.98 && screenAR > 1.2
            let plan = RenderPlan.make(screen: screen, videoSize: vsize,
                                       screenCount: NSScreen.screens.count)
            if portrait { portraitPlan = plan }
            if firstPlan == nil { firstPlan = plan }

            view.playerLayer.videoGravity = portrait ? .resizeAspect : .resizeAspectFill
            view.applyDim(plan.dimAlpha)
            view.setFilled(!portrait)

            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            window.setFrame(frame, display: true)

            view.playerLayer.player = player
            view.apply(videoSize: vsize)

            windows.append(window)
        }

        player.play()

        // 挂上取证探针：记主线程卡顿和解码停顿，一分钟落一行日志
        if let p = firstPlan {
            FrameHealth.shared.bind(player: player, source: vsize, plan: p)
        }

        // 竖屏才需要补边：取一帧做一次模糊，之后播放期间零成本
        if let plan = portraitPlan {
            BackdropBlur.make(from: url, radius: plan.backdropRadius) { [weak self] img in
                guard let self, let img, self.currentVideo == url else { return }
                for w in self.windows {
                    (w.contentView?.subviews.first as? WallpaperView)?.applyBackdrop(img)
                }
            }
        }

        // 换壁纸时保持原来的暂停状态
        isPaused = wasPaused
        if isPaused { for p in players { p.pause() } }

        // 调试：打印每块屏幕、窗口、视图、图层、视频原始尺寸，核对缩放是否一致
        if ProcessInfo.processInfo.environment["VW_GEOM"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                for (i, w) in self.windows.enumerated() {
                    let host = w.contentView
                    let v = host?.subviews.first as? WallpaperView
                    let ps = self.players.first?.currentItem?.presentationSize ?? .zero
                    let vb = v?.bounds.size ?? .zero
                    let sc = v?.window?.backingScaleFactor ?? 0
                    let fillScale = (vb.width > 0 && ps.width > 0)
                        ? max(vb.width / ps.width, vb.height / ps.height) : 0
                    print("[geom] screen=\(NSScreen.screens[i].frame.size) backing=\(sc)")
                    print("[geom] window=\(w.frame.size) view=\(vb) origin=\(v?.frame.origin ?? .zero)")
                    print(String(format: "[geom] video=%@ aspectFillScale=%.4f %@ gravity=%@",
                                 "\(Int(ps.width))x\(Int(ps.height))", fillScale,
                                 v?.debugInfo ?? "",
                                 String(describing: v?.playerLayer.videoGravity ?? .resizeAspectFill)))
                }
                exit(0)
            }
        }
    }

    private func teardown() {
        FrameHealth.shared.unbind()
        for l in loopers { l.disableLooping() }
        for p in players { p.pause(); p.removeAllItems() }
        for w in windows { w.orderOut(nil); w.contentView = nil }
        loopers.removeAll()
        players.removeAll()
        windows.removeAll()
    }

    // MARK: 菜单栏

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusItem()
    }

    private func statusImage() -> NSImage? {
        // 菜单栏用彩色果冻（和 Dock、网站同一个 logo）；资源缺失才退回系统符号
        if let mark = BrandMark.menu { return mark }
        return NSImage(
            systemSymbolName: isShowing ? "photo.on.rectangle.fill" : "photo.on.rectangle",
            accessibilityDescription: "Dòng"
        )
    }

    private func updateStatusItem() {
        guard let item = statusItem else { return }
        if let button = item.button {
            button.alphaValue = (isShowing || isFirstRun) ? 1.0 : 0.4
            button.toolTip = isShowing
                ? "Dòng：\(currentName)"
                : (isFirstRun ? "Dòng：点一下挑一张动态壁纸"
                              : "Dòng 已关闭（点此可重新开启）")
            if !updateHint.isEmpty {
                button.toolTip = (button.toolTip ?? "") + "\n" + updateHint
            }
            // 有新版本：图标右边点一颗小圆点（非阻断提示，用户可忽略）
            if Updater.shared.pendingRelease != nil {
                button.attributedTitle = NSAttributedString(
                    string: " ●",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                        .foregroundColor: NSColor.systemOrange,
                        .baselineOffset: 5,
                    ])
            } else if !button.title.isEmpty {
                button.title = ""
            }
            // 果冻会左右晃：平时慢晃，后台生成壁纸时晃得更起劲，关掉壁纸就停下
            MenuBarSway.shared.update(on: button, image: statusImage(), mood: swayMood)
        }
        // 面板开着的时候顺手刷新数字
        if menuPanel?.isShown == true, let button = item.button {
            menuPanel?.refresh(makePanelData())
            _ = button
        }
    }

    /// 菜单栏果冻这会儿该多活泼：干活时晃得凶一点
    private var swayMood: MenuBarSway.Mood {
        if isDownloading || isImporting { return .busy }
        // 还没挑过壁纸的时候也让它在动：告诉人「我在这儿，等我被点」
        return (isShowing || isFirstRun) ? .calm : .off
    }

    /// 菜单里显示的名字：去掉扩展名
    private func displayName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    // MARK: 自绘面板

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        // 右键还是给系统菜单（快捷键、折叠列表都还在）
        if NSApp.currentEvent?.type == .rightMouseUp {
            showSystemMenu()
            return
        }
        togglePanel(sender)
    }

    private func togglePanel(_ button: NSStatusBarButton) {
        if menuPanel == nil {
            let panel = MenuPanelController()
            let body = panel.body
            body.onSelect = { [weak self] i in self?.selectWallpaper(index: i) }
            body.onOpenLibrary = { [weak self] in
                self?.menuPanel?.dismiss()
                self?.showLibrary()
            }
            // 面板里粘链接：下载 → 优化 → 入库 → 换壁纸，全程在后台做完。
            // 不要再去 showLibrary() 了 —— 这块小面板存在的意义就是不用把壁纸库翻出来。
            body.onPasteLink = { [weak self] link in
                guard let self else { return }
                self.importLink(link, background: true)
            }
            menuPanel = panel
        }
        guard let panel = menuPanel else { return }
        if panel.isShown {
            panel.dismiss()
            return
        }
        // 刚被面板外的这一下点掉的，不要再弹回来
        if Date().timeIntervalSince(panel.lastDismiss) < 0.25 { return }
        panel.show(relativeTo: button, data: makePanelData())
        Analytics.shared.track("panel_open")
        // 用户主动打开面板是个自然的时机，顺手确认一下有没有新版本
        Updater.shared.nudge()
    }

    private func makePanelData() -> PanelData {
        FrameHealth.shared.measure("panelData") { buildPanelData() }
    }

    private func buildPanelData() -> PanelData {
        var d = PanelData()
        d.isEnabled = isShowing
        d.wallpapers = videos.map { displayName(for: $0) }
        d.currentIndex = index

        d.thumbs = videos.map { GalleryThumb.cached(for: $0) }

        if videos.indices.contains(index) {
            let video = videos[index]
            let info = GalleryThumb.info(for: video)
            d.name = displayName(for: video)
            d.meta = info.descriptor
            d.duration = info.duration
            d.thumb = GalleryThumb.cached(for: video)
        }
        d.diskText = libraryDiskText()
        d.todayText = PlayTime.todayText()
        return d
    }

    /// 壁纸目录 + 封面缓存的实际占用
    private func libraryDiskText() -> String {
        let fm = FileManager.default
        var total = 0
        for dir in [Source.libraryDir, GalleryThumb.dir] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            for f in files {
                total += (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            }
        }
        let mb = Double(total) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    /// 每 20 秒记一次「今天播了多久」，关掉或暂停就不记
    private func startPlayTimer() {
        lastTick = Date()
        playTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.tickPlayTime()
        }
    }

    // MARK: 壁纸目录监听

    private func startLibraryWatcher() {
        let dir = Source.libraryDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleRescan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        libWatcher = src
    }

    /// 拷贝大文件会连续触发事件，等目录安静 1.5 秒再扫，免得读进写了一半的文件
    private func scheduleRescan() {
        libRescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescanLibrary() }
        libRescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// 重新扫一遍目录。只在文件列表真的变了时刷新，避免打断正在播的画面
    private func rescanLibrary() {
        let keep = currentVideo?.lastPathComponent
        let fresh = FrameHealth.shared.measure("libScan") { Source.load() }
        let oldNames = videos.map { $0.lastPathComponent }
        let newNames = fresh.map { $0.lastPathComponent }
        guard newNames != oldNames else { return }
        videos = fresh
        if let keep, let i = videos.firstIndex(where: { $0.lastPathComponent == keep }) {
            index = i
        } else if index >= videos.count {
            index = 0
        }
        updateStatusItem()
        libraryWC?.reload()
    }

    private func tickPlayTime() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        guard isShowing, !isPaused, !windows.isEmpty, delta > 0 else { return }
        FrameHealth.shared.measure("playTime") { PlayTime.add(min(delta, 60)) }
    }

    private func selectWallpaper(index i: Int, via: String = "menu") {
        guard i >= 0, i < videos.count else { return }
        let switched = i != index
        // 切完不收起面板：频繁对比不同壁纸时，不用每次都回去点一遍图标
        if i == index {
            if !isShowing { setEnabled(true, via: via) }
        } else {
            index = i
            if !isShowing {
                setEnabled(true, via: via)
            } else {
                rebuild()
                updateStatusItem()
                pushLockScreen()
                libraryWC?.reload()
            }
        }
        // 内容变了（封面 / "正在使用" / 底下那排缩略图）就地刷新，面板位置不动
        if menuPanel?.isShown == true {
            menuPanel?.refresh(makePanelData())
        }
        // 埋点：切到哪一张不重要，重要的是从哪儿切的、库里一共几张
        if switched {
            Analytics.shared.track("wallpaper_switch", ["via": via, "lib_n": videos.count])
        }
    }

    // MARK: 系统菜单（右键兜底）

    fileprivate func showSystemMenu() {
        let menu = buildMenu()
        menu.delegate = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // 有新版本就把它放第一条：非阻断的提示，不打扰但看得见
        if let r = Updater.shared.pendingRelease {
            let item = NSMenuItem(title: "新版本 \(r.displayName) 可用…",
                                  action: #selector(menuUpdateNow), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }
        let check = NSMenuItem(title: "检查更新…", action: #selector(menuCheckUpdate),
                               keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        menu.addItem(.separator())
        // 反馈「卡」的时候，让人一键把数字拿走，不用教任何人去翻日志
        let diag = NSMenuItem(title: "复制诊断信息（反馈卡顿时用）",
                              action: #selector(menuCopyDiag), keyEquivalent: "")
        diag.target = self
        menu.addItem(diag)
        menu.addItem(.separator())
        // 右键只留一个出口：切壁纸、壁纸库都在左键面板里了
        let quit = NSMenuItem(title: "退出 Dòng", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func menuCheckUpdate() {
        Updater.shared.check(manual: true)
    }

    /// 把这一段时间的帧健康数字放到剪贴板：主线程卡顿次数/最久、解码停顿次数、现场参数
    @objc private func menuCopyDiag() {
        FrameHealth.shared.copySummary()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "诊断信息已复制"
        a.informativeText = "把剪贴板里的内容发给我们即可。\n"
            + "里面只有数字：屏幕与素材尺寸、卡顿次数与时长，不含任何壁纸文件名或路径。"
        a.addButton(withTitle: "好")
        a.addButton(withTitle: "显示日志")
        if a.runModal() == .alertSecondButtonReturn {
            FrameHealth.shared.revealLog()
        }
    }

    @objc private func menuUpdateNow() {
        guard let r = Updater.shared.pendingRelease else { return }
        Updater.shared.download(r)
    }

    // MARK: 动作

    // MARK: 管理窗口

    @objc func showLibrary() {
        // 谁把它叫出来的，日志里留一笔：粘链接生成壁纸不该出现在这里
        print("[library] showLibrary")
        if libraryWC == nil {
            libraryWC = FrameHealth.shared.measure("libBuild") {
                LibraryWindowController(delegate: self)
            }
        }
        // 每次开窗都按磁盘实际内容重扫，别拿启动时的旧清单给人看
        FrameHealth.shared.measure("libRescan") { rescanLibrary() }
        FrameHealth.shared.measure("libReload") { libraryWC?.reload() }
        NSApp.activate(ignoringOtherApps: true)
        libraryWC?.showWindow(nil)
        libraryWC?.window?.makeKeyAndOrderFront(nil)
        // 打开壁纸库也算「用户打开」，顺手确认一下有没有新版本（1 分钟内不重复）
        Updater.shared.nudge()
    }

    /// 开机自启开关（设置窗口调用）
    private func setAutostart(_ on: Bool) {
        let fm = FileManager.default
        if on {
            try? fm.createDirectory(at: launchAgentURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            let exe = Bundle.main.executablePath ?? ""
            let plist: [String: Any] = [
                "Label": "com.zhanghangshuo.videowallpaper",
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive",
            ]
            if let d = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? d.write(to: launchAgentURL)
            }
        } else {
            try? fm.removeItem(at: launchAgentURL)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["bootout", "gui/\(getuid())/com.zhanghangshuo.videowallpaper"]
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
        libraryWC?.reload()
        Analytics.shared.track("autostart_toggle", ["on": on])
    }

    /// 让用户贴一条链接（剪贴板里已经有链接就直接填好）
    @objc func promptLink() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = "https://…（B 站、YouTube 等）"
        field.font = .systemFont(ofSize: 12.5)
        if let clip = NSPasteboard.general.string(forType: .string),
           Downloader.looksLikeLink(clip) {
            // 剪贴板里可能是「标题 + 链接」一整段，只填链接本身
            field.stringValue = Downloader.extractLink(clip)
        }

        let alert = NSAlert()
        alert.messageText = "粘贴视频链接"
        alert.informativeText = "下载后会自动去跳帧、按屏幕比例裁切、做成无缝循环，"
            + "完成后存进壁纸库，由你自己挑什么时候换上。"
        alert.accessoryView = field
        alert.addButton(withTitle: "开始处理")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Downloader.looksLikeLink(text) else {
            NSSound.beep()
            showError("这看起来不像是一条视频链接。")
            return
        }
        importLink(text)
    }

    /// 全自动：下载 → 优化 → 入库 → 设成壁纸
    /// - Parameter background: true 表示从面板里发起的，全程不出窗口，
    ///   进度写回面板那条链接框；壁纸库窗口只在用户自己点的时候才开。
    func importLink(_ link: String, background: Bool = false) {
        guard !isDownloading else { NSSound.beep(); return }
        // 埋点只记站名和耗时，链接原文不上报
        let origin = ImportOrigin.link(provider: Analytics.provider(for: link), started: Date())
        guard let tool = Downloader.ytdlpURL else {
            if background {
                menuPanel?.showImportDone("这个版本没带视频解析组件（yt-dlp）", isError: true)
            } else {
                showError("这个版本没带视频解析组件（yt-dlp），只能手动把下载好的视频拖进来。")
            }
            trackImport(origin, ok: false, error: NSError(domain: "Transcoder", code: 2))
            return
        }
        guard let ffmpeg = Transcoder.ffmpegURL else {
            if background {
                menuPanel?.showImportDone("找不到视频处理组件（ffmpeg）", isError: true)
            } else {
                showError("找不到视频处理组件（ffmpeg）。")
            }
            trackImport(origin, ok: false, error: NSError(domain: "Transcoder", code: 2))
            return
        }

        isDownloading = true
        updateStatusItem()   // 果冻切到"忙"的晃法
        if background {
            menuPanel?.showImportProgress("正在解析链接…")
        } else {
            showLibrary()
            libraryWC?.setBusy(true, progress: 0, text: "正在解析链接…")
        }

        let dl = Downloader(tool: tool)
        dl.onStage = { [weak self] s in
            guard let self else { return }
            if background {
                self.menuPanel?.showImportProgress(s)
            } else {
                self.libraryWC?.setBusy(true, progress: 0, text: s)
            }
        }
        dl.onProgress = { [weak self] p in
            guard let self else { return }
            let text = "正在下载（\(Int(p * 100))%）…"
            if background {
                self.menuPanel?.showImportProgress(text, progress: p)
            } else {
                self.libraryWC?.setBusy(true, progress: p, text: text)
            }
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vw-dl-\(UUID().uuidString)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let file = try dl.fetch(link, into: tmp, ffmpeg: ffmpeg)
                DispatchQueue.main.async {
                    self.isDownloading = false
                    if !background { self.libraryWC?.setBusy(false, progress: 0, text: "") }
                    // 剩下的交给同一条优化流水线，同样不许弹窗
                    self.enqueueImport(file, background: background, origin: origin)
                    self.updateStatusItem()
                }
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.updateStatusItem()
                    self.trackImport(origin, ok: false, error: error)
                    if !background { self.libraryWC?.setBusy(false, progress: 0, text: "") }
                    let text = "没下载下来：\(error.localizedDescription)"
                    if background, self.menuPanel?.isShown == true {
                        self.menuPanel?.showImportDone(text, isError: true)
                    } else {
                        self.showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func showError(_ text: String) {
        let a = NSAlert()
        a.messageText = "没能完成"
        a.informativeText = text
        a.alertStyle = .warning
        a.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: 导入

    func importFiles(_ urls: [URL], background: Bool = false) {
        guard !urls.isEmpty else { return }
        let now = Date()
        for u in urls {
            importQueue.append((url: u, background: background, origin: .local(started: now)))
        }
        // 后台（面板里贴链接）进来的不翻窗，用户点了壁纸库才翻
        if !background { showLibrary() }
        pumpImport()
    }

    /// 已经拿到本地文件的（链接下载完成）也走同一条队列，只是来源不同
    private func enqueueImport(_ url: URL, background: Bool, origin: ImportOrigin) {
        importQueue.append((url: url, background: background, origin: origin))
        if !background { showLibrary() }
        pumpImport()
    }

    /// 导入结果埋点：ok / ms / err / 分档，**不含文件名与链接**
    private func trackImport(_ origin: ImportOrigin, ok: Bool, error: Error? = nil, out: URL? = nil) {
        let ms = max(0, Int(Date().timeIntervalSince(origin.startedAt) * 1000))
        switch origin {
        case .link(let provider, _):
            var p: [String: Any] = ["provider": provider, "ok": ok, "ms": ms]
            if !ok {
                p["err"] = Analytics.errCode(error
                    ?? NSError(domain: "Transcoder", code: 0))
            }
            Analytics.shared.track("import_link", p)
        case .local:
            var p: [String: Any] = ["ok": ok, "ms": ms]
            if !ok {
                p["err"] = Analytics.errCode(error
                    ?? NSError(domain: "Transcoder", code: 0))
            } else if let out {
                let dur = GalleryThumb.info(for: out).duration
                let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                p["dur_bucket"] = Analytics.durBucket(dur)
                p["size_bucket"] = Analytics.sizeBucket(size)
            }
            Analytics.shared.track("import_local", p)
        }
    }

    private func pumpImport() {
        guard !isImporting, !importQueue.isEmpty else { return }
        guard let ffmpeg = Transcoder.ffmpegURL else {
            libraryWC?.setBusy(false, progress: 0, text: "找不到视频处理组件（ffmpeg），无法优化视频")
            menuPanel?.showImportDone("找不到视频处理组件（ffmpeg）", isError: true)
            importQueue.removeAll()
            updateStatusItem()
            return
        }
        isImporting = true
        updateStatusItem()
        let item = importQueue.removeFirst()
        let src = item.url
        // 这一条是不是后台来的：是就不许开窗，进度只写面板
        let quiet = item.background
        let origin = item.origin
        let tc = Transcoder(ffmpeg: ffmpeg)
        let label = src.lastPathComponent
        // 进度只说给"正在看的那一扇"：面板开着就说面板，否则说库窗口那条胶囊。
        // Transcoder 的回调可能在后台线程，面板是 AppKit 视图，必须回主线程再动。
        let report: (String, Double) -> Void = { [weak self] text, p in
            let apply = {
                guard let self else { return }
                if quiet {
                    self.menuPanel?.showImportProgress(text, progress: p)
                } else {
                    self.libraryWC?.setBusy(true, progress: p, text: text)
                }
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
        report("正在优化 \(label)…", 0)
        tc.onProgress = { p in report("正在优化 \(label)（\(Int(p * 100))%）", p) }
        tc.onStage = { s in report("\(label)：\(s)", 0) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let out = try tc.importVideo(source: src, into: Source.libraryDir)
                DispatchQueue.main.async {
                    self.isImporting = false
                    // 链接下载来的临时目录，入库后就删掉，别占地方
                    if src.path.contains("/vw-dl-") {
                        try? FileManager.default.removeItem(at: src.deletingLastPathComponent())
                    }
                    // 下载归下载，换壁纸归换壁纸：新素材只入库，绝不替用户把桌面换掉，
                    // 他点了缩略图（面板）或右键「设为壁纸」（库）才换。
                    // 唯一例外：库里原本一张都没有，这时候不换就是一片黑。
                    let playing = self.currentVideo?.lastPathComponent
                    self.videos = Source.load()
                    if let playing,
                       let i = self.videos.firstIndex(where: { $0.lastPathComponent == playing }) {
                        self.index = i
                    } else if self.index >= self.videos.count {
                        self.index = 0
                    }
                    let newIndex = self.videos.firstIndex {
                        $0.lastPathComponent == out.lastPathComponent
                    }
                    var applied = false
                    if playing == nil, let i = newIndex {
                        self.index = i
                        if !self.isShowing {
                            self.setEnabled(true, via: "onboarding")
                        } else {
                            self.rebuild()
                            self.pushLockScreen()
                        }
                        applied = true
                    }
                    self.updateStatusItem()
                    self.libraryWC?.reload()
                    // 导入成功埋点：只有成败、耗时、档位，没有文件名
                    self.trackImport(origin, ok: true, out: out)
                    // 面板开着：把刚存好的那张滚进可见范围，省得在一排缩略图里找
                    if self.menuPanel?.isShown == true {
                        if let i = newIndex, !applied {
                            self.menuPanel?.revealThumb(i, data: self.makePanelData())
                        } else {
                            self.menuPanel?.refresh(self.makePanelData())
                        }
                    }
                    if quiet {
                        // 后台生成：工作已经做完了，只在面板那一条框里报个结论
                        let name = out.deletingPathExtension().lastPathComponent
                        print("[import] saved=\(out.lastPathComponent) applied=\(applied) "
                              + "playing=\(playing ?? "nil") index=\(self.index) videos=\(self.videos.count)")
                        self.menuPanel?.showImportDone(
                            applied ? "已换成「\(name)」" : "已存好「\(name)」，点一下才换")
                    } else {
                        let note = applied
                            ? "已设为壁纸：\(out.lastPathComponent)"
                            : "已加入壁纸库：\(out.lastPathComponent)（右键「设为壁纸」才换）"
                        self.libraryWC?.setBusy(false, progress: 1, text: note)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                            guard let self, !self.isImporting else { return }
                            self.libraryWC?.setBusy(false, progress: 0, text: "")
                        }
                    }
                    self.pumpImport()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.trackImport(origin, ok: false, error: error)
                    let text = "「\(label)」处理失败：\(error.localizedDescription)"
                    if quiet {
                        self.menuPanel?.showImportDone(text, isError: true)
                    } else {
                        self.libraryWC?.setBusy(false, progress: 0, text: text)
                    }
                    self.updateStatusItem()
                    self.pumpImport()
                }
            }
        }
    }

    @objc private func toggleShow() {
        setEnabled(!isShowing, via: "menu")
    }

    /// 统一的启用 / 关闭入口：面板、设置窗口、切换壁纸都走这里
    /// - Parameter via: 埋点口径，只允许 onboarding / menu / settings
    private func setEnabled(_ on: Bool, via: String = "menu") {
        let changed = isShowing != on
        isShowing = on
        UserDefaults.standard.set(on, forKey: "wallpaperEnabled")
        isPaused = false
        if on {
            rebuild()
            pushLockScreen()
        } else {
            teardown()
        }
        updateStatusItem()
        libraryWC?.reload()
        if changed {
            Analytics.shared.track(on ? "wallpaper_enable" : "wallpaper_disable", ["via": via])
        }
    }

    /// 锁屏跟随开关（设置窗口调用）
    private func setLockSync(_ on: Bool) {
        syncLockScreen = on
        UserDefaults.standard.set(on, forKey: "syncLockScreen")
        if on { pushLockScreen() }
        libraryWC?.reload()
        Analytics.shared.track("lock_screen_toggle", ["on": on])
    }

    @objc private func openLibrary() {
        let dir = Source.libraryDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func reloadSources() {
        let keep = currentVideo?.lastPathComponent
        videos = Source.load()
        if let keep, let i = videos.firstIndex(where: { $0.lastPathComponent == keep }) {
            index = i
        } else if index >= videos.count {
            index = 0
        }
        if isShowing { rebuild() }
        updateStatusItem()
        pushLockScreen()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 右键系统菜单

extension AppDelegate: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }
}

// MARK: - 管理窗口的数据源

extension AppDelegate: WallpaperLibraryDelegate {

    func libraryVideos() -> [URL] { videos }

    func libraryCurrentIndex() -> Int { index }

    func libraryApply(index i: Int) {
        guard i >= 0, i < videos.count else { return }
        let switched = i != index
        index = i
        setEnabled(true, via: "settings")
        // 库里点「设为壁纸」：via=library，跟面板里点缩略图区分开
        if switched {
            Analytics.shared.track("wallpaper_switch", ["via": "library", "lib_n": videos.count])
        }
    }

    func libraryDelete(index i: Int) {
        guard i >= 0, i < videos.count else { return }
        let url = videos[i]
        NSWorkspace.shared.recycle([url]) { _, _ in }
        videos.remove(at: i)
        if index > i { index -= 1 }
        if videos.isEmpty {
            index = 0
            setEnabled(false, via: "settings")
        } else {
            index = min(index, videos.count - 1)
            if isShowing {
                rebuild()
                pushLockScreen()
            }
        }
        updateStatusItem()
        libraryWC?.reload()
        // 埋点只记删完还剩几张
        Analytics.shared.track("wallpaper_delete", ["lib_n": videos.count])
    }

    func libraryAdd(urls: [URL]) { importFiles(urls) }

    func libraryAddLink() { promptLink() }

    func libraryImportLink(_ link: String) { importLink(link) }

    func libraryRevealFolder() { openLibrary() }

    func libraryIsEnabled() -> Bool { isShowing }
    func librarySetEnabled(_ on: Bool) { setEnabled(on, via: "settings") }
    func libraryIsLockSync() -> Bool { syncLockScreen }
    func librarySetLockSync(_ on: Bool) { setLockSync(on) }
    func libraryIsAutostart() -> Bool { isAutostartEnabled }
    func librarySetAutostart(_ on: Bool) { setAutostart(on) }
}

// MARK: - 命令行：VideoWallpaper --import 视频1 [视频2 …]

func runImportCLI(_ paths: [String]) -> Int32 {
    setvbuf(stdout, nil, _IOLBF, 0)
    _ = NSApplication.shared
    guard let ffmpeg = Transcoder.ffmpegURL else {
        FileHandle.standardError.write("找不到视频处理组件\n".data(using: .utf8)!)
        return 1
    }
    guard !paths.isEmpty else {
        print("用法: VideoWallpaper --import <视频>…")
        return 1
    }
    try? FileManager.default.createDirectory(at: Source.libraryDir, withIntermediateDirectories: true)
    let tc = Transcoder(ffmpeg: ffmpeg)
    var failed = 0
    for p in paths {
        let src = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: src.path) else {
            print("跳过（找不到）\(p)")
            failed += 1
            continue
        }
        let info = Transcoder.probe(src)
        let size = info.map { Transcoder.targetSize(for: $0) }
        print("处理 \(src.lastPathComponent)\(info.map { " — \(Int($0.duration))s \($0.width)×\($0.height)" } ?? "")"
              + (size.map { " → \($0.w)×\($0.h)" } ?? ""))
        do {
            let out = try tc.importVideo(source: src, into: Source.libraryDir)
            var notes: [String] = []
            if tc.lastHeadTrimmed > 0 { notes.append(String(format: "剪掉片头 %.1f 秒", tc.lastHeadTrimmed)) }
            if tc.lastTrimmed > 0 { notes.append(String(format: "截掉片尾 %.1f 秒", tc.lastTrimmed)) }
            if let wm = tc.lastWatermark { notes.append("抹掉\(wm.corner)角标") }
            print("  完成 \(out.lastPathComponent)"
                  + (notes.isEmpty ? "" : "（" + notes.joined(separator: "、") + "）"))
        } catch {
            print("  失败：\(error.localizedDescription)")
            failed += 1
        }
    }
    return failed == 0 ? 0 : 2
}

// MARK: - 命令行：VideoWallpaper --link 链接1 [链接2 …]

func runLinkCLI(_ links: [String]) -> Int32 {
    setvbuf(stdout, nil, _IOLBF, 0)
    _ = NSApplication.shared
    guard let tool = Downloader.ytdlpURL else {
        FileHandle.standardError.write("找不到 yt-dlp\n".data(using: .utf8)!)
        return 1
    }
    guard let ffmpeg = Transcoder.ffmpegURL else {
        FileHandle.standardError.write("找不到 ffmpeg\n".data(using: .utf8)!)
        return 1
    }
    guard !links.isEmpty else {
        print("用法: VideoWallpaper --link <视频链接>…")
        return 1
    }
    try? FileManager.default.createDirectory(at: Source.libraryDir, withIntermediateDirectories: true)

    let dl = Downloader(tool: tool)
    var failed = 0
    for link in links {
        print("链接 \(link)")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vw-dl-cli-\(UUID().uuidString)")
        do {
            let file = try dl.fetch(link, into: tmp, ffmpeg: ffmpeg)
            print("  已下载 \(file.lastPathComponent)（\(sizeText(file))）")
            let tc = Transcoder(ffmpeg: ffmpeg)
            tc.callbackQueue = DispatchQueue(label: "vw.cli.progress")
            tc.onStage = { print("  · \($0)") }
            var lastPct = -1
            tc.onProgress = { p in
                let pct = Int(p * 100)
                // 每 10% 打一行，防止刷屏
                if pct / 10 != lastPct / 10 {
                    lastPct = pct
                    print("  · 进度 \(pct)%")
                }
            }
            let out = try tc.importVideo(source: file, into: Source.libraryDir)
            print("  已入库 \(out.lastPathComponent)（\(sizeText(out))）")
            try? FileManager.default.removeItem(at: tmp)
        } catch {
            print("  失败：\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tmp)
            failed += 1
        }
    }
    return failed == 0 ? 0 : 2
}

func sizeText(_ url: URL) -> String {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    return String(format: "%.1f MB", Double(size) / 1_048_576)
}

// MARK: - 命令行：VideoWallpaper --detect 视频…（只看片尾水印检测结果，不转码）

func runDetectCLI(_ paths: [String]) -> Int32 {
    setvbuf(stdout, nil, _IOLBF, 0)
    _ = NSApplication.shared
    guard let ffmpeg = Transcoder.ffmpegURL else {
        FileHandle.standardError.write("找不到 ffmpeg\n".data(using: .utf8)!)
        return 1
    }
    let tc = Transcoder(ffmpeg: ffmpeg)
    for p in paths {
        let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        guard let info = Transcoder.probe(url) else {
            print("跳过 \(p)")
            continue
        }
        let t0 = Date()
        let tailInfo = tc.detectEndCard(url: url, duration: info.duration)
        let tail = tailInfo?.end ?? info.duration
        let head = tc.detectHead(url: url, duration: tail)
        let size = Transcoder.targetSize(for: info)
        let wm = tc.detectWatermark(url: url, from: head ?? 0, to: tail, target: size)
        let cost = Date().timeIntervalSince(t0)

        var parts: [String] = []
        parts.append(head.map { String(format: "片头剪到 %.2fs", $0) } ?? "片头不动")
        parts.append(tailInfo.map { String(format: "片尾截到 %.2fs（-%.2fs）", $0.end, $0.removed) } ?? "片尾不动")
        parts.append(wm.map { "角标 \($0.corner) \($0.w)×\($0.h) @(\($0.x),\($0.y))" } ?? "无角标")
        print(String(format: "%@  dur=%.1fs  用时%.2fs\n    → %@",
                     url.lastPathComponent, info.duration, cost,
                     parts.joined(separator: " · ")))
    }
    return 0
}

// MARK: - 命令行：VideoWallpaper --try 视频 输出（跑一遍完整裁剪+模糊，输出到指定文件）

func runTryCLI(input: String, output: String) -> Int32 {
    setvbuf(stdout, nil, _IOLBF, 0)
    _ = NSApplication.shared
    guard let ffmpeg = Transcoder.ffmpegURL else {
        FileHandle.standardError.write("找不到 ffmpeg\n".data(using: .utf8)!)
        return 1
    }
    let src = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
    guard let info = Transcoder.probe(src) else { print("读不出视频信息"); return 1 }
    let tc = Transcoder(ffmpeg: ffmpeg)
    tc.callbackQueue = DispatchQueue(label: "vw.try")
    tc.onStage = { print("  · \($0)") }
    let size = Transcoder.targetSize(for: info)

    var tail = info.duration
    if let t = tc.detectEndCard(url: src, duration: info.duration) { tail = t.end }
    var head = 0.0
    if let h = tc.detectHead(url: src, duration: tail) { head = h }
    if tail - head < 3.0 { head = 0 }
    let wm = tc.detectWatermark(url: src, from: head, to: tail, target: size)

    print(String(format: "head=%.2f tail=%.2f 水印=%@", head, tail,
                 wm.map { "\($0.corner) \($0.x),\($0.y) \($0.w)×\($0.h)" } ?? "无"))
    do {
        try tc.transcode(input: src, output: URL(fileURLWithPath: (output as NSString).expandingTildeInPath),
                         info: info, size: size, start: head, end: tail, watermark: wm)
    } catch {
        print("转码失败：\(error.localizedDescription)")
        return 2
    }
    print("完成 \(output)")
    return 0
}

// MARK: - 入口

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--try"), arguments.count > i + 2 {
    exit(runTryCLI(input: arguments[i + 1], output: arguments[i + 2]))
}
if let i = arguments.firstIndex(of: "--detect") {
    exit(runDetectCLI(Array(arguments[(i + 1)...])))
}
if let i = arguments.firstIndex(of: "--import") {
    exit(runImportCLI(Array(arguments[(i + 1)...])))
}
if let i = arguments.firstIndex(of: "--link") {
    exit(runLinkCLI(Array(arguments[(i + 1)...])))
}

/// 后台程序（无菜单栏）也要挂一份「编辑」菜单，
/// 否则文本框里的 ⌘C / ⌘V / ⌘A 没有 responder 处理，等于失灵。
func installEditMenu() {
    let main = NSMenu()
    let editItem = NSMenuItem()
    main.addItem(editItem)

    let edit = NSMenu(title: "编辑")
    edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    for item in edit.items { item.target = nil }

    editItem.submenu = edit
    NSApp.mainMenu = main
}

let app = NSApplication.shared
// stdout 重定向到文件时默认是块缓冲，被 kill 掉的联调实例会丢掉全部日志。
// 改成按行刷新，日志才追得上进程。
setvbuf(stdout, nil, _IOLBF, 0)
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
installEditMenu()
app.run()
