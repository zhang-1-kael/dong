import Cocoa
import AVFoundation

// MARK: - 今日播放时长

/// 只在本机记一个「今天播了多少秒」的计数，键按天分开，不联网、不外传。
enum PlayTime {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func key(_ date: Date) -> String {
        "playSeconds." + formatter.string(from: date)
    }

    static func todaySeconds() -> Double {
        UserDefaults.standard.double(forKey: key(Date()))
    }

    static func add(_ seconds: Double) {
        guard seconds > 0 else { return }
        let k = key(Date())
        UserDefaults.standard.set(UserDefaults.standard.double(forKey: k) + seconds, forKey: k)
        // 顺手清掉 40 天前的记录，别让偏好文件一直长
        if let all = UserDefaults.standard.dictionaryRepresentation().keys.filter({ $0.hasPrefix("playSeconds.") })
            .sorted().dropLast(40) as [String]? {
            for old in all { UserDefaults.standard.removeObject(forKey: old) }
        }
    }

    static func todayText() -> String {
        let minutes = Int(todaySeconds() / 60)
        if minutes <= 0 { return "0 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }
}

// MARK: - 面板数据

struct PanelData {
    var isEnabled = true
    var name = ""
    var meta = ""
    var duration: Double = 0
    var thumb: NSImage?
    var wallpapers: [String] = []
    var thumbs: [NSImage?] = []
    var currentIndex = 0
    var diskText = "—"
    var todayText = "—"
}

// MARK: - 配色

/// 浅色纸面 + 一点点透明：压在视频壁纸上像一张实心卡片，又不会显得死板。
/// 深色模式下自动翻成暗面，不用两边各维护一套。
enum Ink {
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// 面板底色：下面垫着一层系统毛玻璃（NSVisualEffectView），这里只压一层极淡的白。
    /// 目标：既要看得出背后有东西（形状、颜色透上来），又不能让背后的字「印」出来——
    /// 糊住字的是系统材质的模糊，不是这层白；白只负责在最亮/最暗的壁纸上兜一下字色。
    static let surfaceTop = dyn(NSColor(srgbRed: 0.985, green: 0.985, blue: 1.0, alpha: 0.055),
                                NSColor(srgbRed: 0.155, green: 0.155, blue: 0.175, alpha: 0.11))
    static let surfaceBottom = dyn(NSColor(srgbRed: 0.975, green: 0.975, blue: 0.995, alpha: 0.02),
                                   NSColor(srgbRed: 0.100, green: 0.100, blue: 0.115, alpha: 0.07))
    /// 缩略图条两端渐隐用，取中间值
    static let surface = dyn(NSColor(srgbRed: 0.98, green: 0.98, blue: 1.0, alpha: 0.04),
                             NSColor(srgbRed: 0.105, green: 0.105, blue: 0.118, alpha: 0.12))
    /// 玻璃白膜撤很薄以后，卡片轮廓全靠这条边——太淡会「散」在壁纸里，看不出是块玻璃
    static let edge = dyn(NSColor.black.withAlphaComponent(0.10),
                          NSColor.white.withAlphaComponent(0.16))
    static let hair = dyn(NSColor.black.withAlphaComponent(0.07),
                          NSColor.white.withAlphaComponent(0.085))

    static let primary = dyn(NSColor(srgbRed: 0.075, green: 0.075, blue: 0.095, alpha: 1),
                             NSColor(srgbRed: 0.965, green: 0.965, blue: 0.975, alpha: 1))
    static let secondary = dyn(NSColor(srgbRed: 0.40, green: 0.40, blue: 0.45, alpha: 1),
                               NSColor(srgbRed: 0.68, green: 0.68, blue: 0.72, alpha: 1))
    static let tertiary = dyn(NSColor(srgbRed: 0.565, green: 0.565, blue: 0.615, alpha: 1),
                              NSColor(srgbRed: 0.52, green: 0.52, blue: 0.57, alpha: 1))
    /// 面板里的「托底灰」，用在缩略图占位、按压态
    static let fill = dyn(NSColor.black.withAlphaComponent(0.055),
                          NSColor.white.withAlphaComponent(0.075))
    /// 链接输入框：比卡片更亮一档的白，配一条看得见的细边
    /// （原来用 fill 那层 5.5% 黑压在白卡片上，几乎没有边界，看着像禁用）
    static let inputFill = dyn(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.50),
                               NSColor(white: 1, alpha: 0.10))
    static let inputEdge = dyn(NSColor.black.withAlphaComponent(0.10),
                               NSColor.white.withAlphaComponent(0.14))
}

/// 品牌色：只出现在图标、当前项描边、强调数字上，其余一律黑白灰
/// 2026-11 换标：果冻橙 #F0873C，深浅两档做渐变
enum Brand {
    static let accent = NSColor(srgbRed: 0.941, green: 0.529, blue: 0.235, alpha: 1)
    static let gradTop = NSColor(srgbRed: 0.961, green: 0.631, blue: 0.353, alpha: 1)
    static let gradBottom = NSColor(srgbRed: 0.898, green: 0.416, blue: 0.149, alpha: 1)
}

/// 应用里的 logo（BrandMark.png / BrandMarkTemplate.png 由 build.sh 拷进 Resources）
/// 资源缺失时全部返回 nil，调用方自动退回旧的渐变图标，不会白屏
enum BrandMark {
    static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()

    /// 面板左上角：带米白圆角底的徽章（跟网站下载卡同一个观感）
    static let badge: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMarkBadge", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()

    /// 菜单栏：18pt 彩色果冻。眼睛在 brand/app_assets.py 里放大到 1.4 倍，
    /// 否则缩到 18pt 只剩 0.6px，远看就是个橘子瓣
    static let menu: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMarkMenu", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false
        return img
    }()

    /// 单色模板（备用：深色菜单栏要跟系统一致时切到这张）
    static let template: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMarkTemplate", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 17, height: 17)
        return img
    }()

    /// 摇摆动画帧：icons/JellyMenu-00..29.png / JellyBadge-00..29.png
    /// 由 jelly-anim/export_icons.py 从 still-1024.png 的轮廓逐帧重绘（透明底，无投影），
    /// 30 帧正好是一个完整的左右来回，首尾能无缝接上。
    /// 资源不在时返回空数组，调用方自动退回「整张图转角度」的老办法。
    static let menuFrames: [NSImage] = loadFrames("JellyMenu", artWidth: 23)

    /// 徽章里的果冻：白底方块的 53% 宽（跟原来的静态徽章同一比例）
    static let badgeFrames: [NSImage] = loadFrames("JellyBadge", artWidth: 29)

    private static func loadFrames(_ prefix: String, artWidth: CGFloat) -> [NSImage] {
        var out: [NSImage] = []
        for i in 0..<64 {
            let name = "\(prefix)-\(String(format: "%02d", i))"
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let img = NSImage(contentsOf: url), img.size.width > 1 else { break }
            // 按 3x 像素出的图，这里换算成绘制用的点尺寸；长宽比保持原样，绝不拉伸
            let h = artWidth * img.size.height / img.size.width
            img.size = NSSize(width: artWidth, height: h)
            out.append(img)
        }
        return out
    }
}

// MARK: - 菜单栏那颗果冻：左右晃

/// 状态栏图标的动效。做法是预生成一圈「转过一点角度」的帧，用定时器轮播。
/// 直接给 NSStatusBarButton 的 layer 加 CA 动画会被菜单栏自己的布局和裁剪吃掉，
/// 换 image 最稳：不动点击区域，不动选中高亮，也不和 variableLength 的宽度打架。
final class MenuBarSway {
    enum Mood {
        /// 不晃（壁纸关着、或系统开了「减弱动态效果」）
        case off
        /// 平时：慢慢地晃，幅度小
        case calm
        /// 后台生成壁纸时：快一点、幅度大一点，顺便当"还在干活"的提示
        case busy
    }

    static let shared = MenuBarSway()

    /// 画布比图案大一圈：摆动到两端时外框最宽，画布太小会把角削掉，
    /// 也太小的话菜单栏里整颗果冻会比以前的静态图标小一号。所有帧统一 24pt，
    /// 换成定时器轮播也不会让菜单栏宽度来回跳。
    private static let canvas: CGFloat = 24
    private static let art: CGFloat = 23

    private weak var button: NSStatusBarButton?
    private var baseImage: NSImage?
    private var timer: Timer?
    private var frames: [NSImage] = []
    private var frameIndex = 0
    private var mood: Mood = .off
    private var cache: [String: [NSImage]] = [:]
    /// 调试用：一共轮播了多少帧
    private(set) var tickCount = 0

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 每次刷新状态栏都走这里。同一档情绪重复调用是空操作，不会重启动画。
    func update(on button: NSStatusBarButton, image: NSImage?, mood want: Mood) {
        self.button = button
        baseImage = image
        let target: Mood = reduceMotion ? .off : want
        if target == .off {
            stop()
            // 停下来也用同一套 21pt 画布的 0° 帧，菜单栏宽度才不会跟着状态跳一下
            button.image = frames(for: .calm).first ?? image
            return
        }
        if timer != nil, mood == target { return }
        start(target)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        frames = []
        mood = .off
    }

    // MARK: 轮播

    private func start(_ m: Mood) {
        guard let button else { return }
        stop()
        mood = m
        frames = frames(for: m)
        guard !frames.isEmpty else {
            mood = .off
            button.image = baseImage
            return
        }
        frameIndex = 0
        tickCount = 0
        button.image = frames[0]
        // 30 帧正好一个来回：平时 2 秒晃一次，后台干活时加快到 1.25 秒，幅度不变
        let interval: TimeInterval = (m == .busy) ? 1.0 / 24 : 1.0 / 15
        // .common 模式：光标在别处拖拽 / 菜单跟踪时也别僵住
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let button, !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        button.image = frames[frameIndex]
        tickCount += 1
    }

    /// 一整个来回的帧。优先用真果冻动画帧（JellyMenu-*，每一帧都是弯曲形变过的），
    /// 资源缺失时才退回老的「整张图转角度」——刚体旋转在小尺寸下看着像歪贴纸。
    private func frames(for m: Mood) -> [NSImage] {
        let key = (m == .busy) ? "busy" : "calm"
        if let hit = cache[key] { return hit }
        var out: [NSImage] = []
        if !Self.composed.isEmpty {
            out = Self.composed
        } else {
            let amp: CGFloat = (m == .busy) ? 9 : 7
            let count = (m == .busy) ? 24 : 30
            for i in 0..<count {
                let angle = amp * sin(2 * CGFloat.pi * CGFloat(i) / CGFloat(count))
                if let f = Self.frame(angle: angle) { out.append(f) }
            }
        }
        cache[key] = out
        return out
    }

    /// 调试：把两档情绪的所有帧写成 PNG，肉眼核对旋转有没有被画布裁掉
    func dumpFrames(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for m in [Mood.calm, .busy] {
            let list = frames(for: m)
            let tag = (m == .busy) ? "busy" : "calm"
            print("[sway] \(tag) frames=\(list.count) size=\(list.first?.size ?? .zero)")
            for (i, img) in list.enumerated() {
                guard let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                let name = "\(dir)/\(tag)-\(String(format: "%02d", i)).png"
                try? png.write(to: URL(fileURLWithPath: name))
            }
        }
    }

    /// 动画帧合成为固定画布的图。两档情绪用的是同一套姿态，只差播放速度，
    /// 所以合成一次就够，别每次切情绪都重画 30 张。
    private static let composed: [NSImage] = BrandMark.menuFrames.compactMap { compose($0) }

    /// 老办法：把图案按角度转一下（没有动画帧时的兜底）
    private static func frame(angle: CGFloat) -> NSImage? {
        guard let base = BrandMark.menu else { return nil }
        return compose(base, angle: angle)
    }

    /// 把图案画进 2× 位图。不用 lockFocus——那玩意儿容易把堆踩坏。
    /// 长宽比按原样等比缩放后居中：动画帧是 1.2:1 的（左右晃的空间更大），
    /// 硬塞进正方形会被拉扁，看着像被人按了一下。
    private static func compose(_ base: NSImage, angle: CGFloat = 0) -> NSImage? {
        let scale: CGFloat = 2
        let px = Int(canvas * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        // 先定"点"尺寸再建上下文：上下文按 rep.size 算 CTM，
        // 反过来的话画布会被当成 42pt，图案缩到四成还贴在左下角
        rep.size = NSSize(width: canvas, height: canvas)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.interpolationQuality = .high
        // 绕画布中心转
        ctx.cgContext.translateBy(x: canvas / 2, y: canvas / 2)
        ctx.cgContext.rotate(by: angle * CGFloat.pi / 180)
        ctx.cgContext.translateBy(x: -canvas / 2, y: -canvas / 2)
        let bw = max(1, base.size.width), bh = max(1, base.size.height)
        let s = min(art / bw, art / bh)
        let w = bw * s, h = bh * s
        base.draw(in: NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h),
                  from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: NSSize(width: canvas, height: canvas))
        img.addRepresentation(rep)
        img.isTemplate = false
        return img
    }
}

// MARK: - 面板右上角：粘贴链接的小框

/// 壁纸库那个链接框的缩小版。面板整块是自绘的，这里挂一个子视图专门接键盘：
/// 点一下聚焦，⌘V 或者手敲都行，回车把链接交出去。
/// 现在是标题下面那条通栏：空着的时候只显示居中的「链接图标 + 粘贴视频链接」，
/// 点进去才亮出真正的输入框，左对齐打字。
final class PanelLinkField: NSView, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?

    /// 高度跟着原来那条通栏按钮走
    static let height: CGFloat = 30

    private let field = NSTextField()
    /// 空态那行「链接图标 + 粘贴视频链接」用控件画，不用 draw() 里画文字：
    /// 在图层渲染期间直接 draw NSString 会把堆踩坏，偶发 SIGTRAP。
    /// 输入框左边那颗小链接图标，用图片视图画，不在 draw 里画字画图
    private let linkIcon = NSImageView()

    private var hovered = false { didSet { restyleIcon(); needsDisplay = true } }
    private var focused = false { didSet { restyleIcon(); needsDisplay = true } }
    /// 回车但不像链接：描边闪一下红，字还留着让人改
    private var warning = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    /// 光写「粘贴视频链接」看不出这条是干嘛的，得说清楚粘进来会变成动态壁纸
    private let idlePlaceholder = "粘贴视频链接，转成动态壁纸"
    /// 空态占位色：比 secondary 再淡一档
    private var idleColor: NSColor { Ink.secondary.withAlphaComponent(0.58) }
    private var noticeWork: DispatchWorkItem?

    /// 后台生成壁纸时的忙碌态：文字借用占位行，进度画在框底那条细线上。
    /// 这一切都留在这块小面板里，绝不再把壁纸库窗口拉到前面来。
    private var busy = false {
        didSet {
            field.isEditable = !busy
            field.isSelectable = !busy
        }
    }
    private var busyProgress: Double = 0

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.height))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = Ink.primary
        // 比 secondary 再淡一档：白底 + 细边已经把「能打字」说清楚了，字不必压那么重
        setPlaceholder(idlePlaceholder, color: idleColor)
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        linkIcon.imageScaling = .scaleNone
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(linkIcon)
        NSLayoutConstraint.activate([
            linkIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            linkIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        restyleIcon()
    }

    /// 占位文字（含「这不像一条视频链接」的提示态）
    private func setPlaceholder(_ s: String, color: NSColor) {
        field.placeholderAttributedString = NSAttributedString(
            string: s,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isEditing: Bool { focused }

    func focus() {
        guard let win = window else { return }
        focused = true
        win.makeFirstResponder(field)
        // 后台程序点状态栏不会激活自己，键盘事件就进不来；要打字得先抢一下焦点。
        // activate 是异步的，激活完再 makeKey 一次，不然这一步会白做。
        if NSApp.isActive {
            win.makeKey()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            w.makeKey()
            w.makeFirstResponder(self.field)
        }
    }

    func blur() {
        if window?.firstResponder === field.currentEditor() || window?.firstResponder === field {
            window?.makeFirstResponder(superview)
        }
        focused = false
    }

    func clear() {
        guard !busy else { return }
        field.stringValue = ""
        blur()
    }

    /// 输入不像链接时就地提示一句，不弹窗
    func notice(_ msg: String) {
        noticeWork?.cancel()
        setPlaceholder(msg, color: NSColor.systemRed.withAlphaComponent(0.85))
        warning = true
        NSSound.beep()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.warning = false
            self.setPlaceholder(self.idlePlaceholder, color: self.idleColor)
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    /// 后台生成壁纸：进度写在框里（文字走占位行、进度走底边细线），
    /// 顺带把输入锁住，避免下载途中又贴一条。
    func showBusy(_ text: String, progress: Double = 0) {
        noticeWork?.cancel()
        noticeWork = nil
        warning = false
        blur()
        field.stringValue = ""
        busy = true
        busyProgress = max(0, min(1, progress))
        setPlaceholder(text, color: Ink.secondary.withAlphaComponent(0.72))
        needsDisplay = true
    }

    /// 收尾一句：成功也说、失败也说，过几秒自己退回默认占位
    func showDone(_ text: String, isError: Bool = false) {
        noticeWork?.cancel()
        busy = false
        busyProgress = 0
        warning = isError
        setPlaceholder(text, color: isError
                       ? NSColor.systemRed.withAlphaComponent(0.85)
                       : Ink.secondary.withAlphaComponent(0.62))
        needsDisplay = true
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.busy else { return }
            self.warning = false
            self.setPlaceholder(self.idlePlaceholder, color: self.idleColor)
            self.needsDisplay = true
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 6.0 : 4.0), execute: work)
    }

    // MARK: 画底

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
        // 白底 + 一条实边：像真正的输入框，而不是贴在卡片上的一层灰
        Ink.inputFill.setFill()
        path.fill()
        if warning {
            NSColor.systemRed.withAlphaComponent(0.60).setStroke()
        } else if focused {
            Brand.accent.withAlphaComponent(0.55).setStroke()
        } else if hovered {
            Ink.secondary.withAlphaComponent(0.38).setStroke()
        } else {
            Ink.inputEdge.setStroke()
        }
        path.lineWidth = 1
        path.stroke()

        // 后台生成时，框底走一条细进度：不弹窗也能看见它在动
        if busy, busyProgress > 0 {
            let w = (r.width - 12) * CGFloat(min(max(busyProgress, 0), 1))
            if w > 1 {
                let bar = NSRect(x: r.minX + 6, y: r.minY + 3, width: w, height: 2)
                Brand.accent.withAlphaComponent(0.72).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    private func restyleIcon() {
        let a: CGFloat = (hovered || focused) ? 0.95 : 0.78
        guard let base = NSImage(systemSymbolName: "link", accessibilityDescription: nil) else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(
                paletteColors: [Ink.secondary.withAlphaComponent(a)]))
        linkIcon.image = base.withSymbolConfiguration(cfg) ?? base
    }

    // MARK: 悬停 / 点击

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {
        guard !busy else { return }
        focus()
    }

    /// 悬上去给个输入光标，暗示这里能打字
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    // MARK: 粘贴

    /// 后台程序没有菜单栏，⌘V 没人接，所以自己接住
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 后台生成期间输入是锁着的，⌘V 也不该往里塞新链接
        guard !busy else { return super.performKeyEquivalent(with: event) }
        guard flags == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "v":
            focus()
            pasteLink()
            return true
        case "a":
            focus()
            (field.currentEditor() as? NSTextView)?.selectAll(nil)
            return true
        case "c":
            if let ed = field.currentEditor() as? NSTextView { ed.copy(nil); return true }
        case "x":
            if let ed = field.currentEditor() as? NSTextView { ed.cut(nil); return true }
        default:
            break
        }
        return super.performKeyEquivalent(with: event)
    }

    func pasteLink() {
        guard !busy else { return }
        let board = NSPasteboard.general
        var raw = board.string(forType: .string)
        if raw == nil || raw?.isEmpty == true { raw = board.string(forType: .URL) }
        guard let letters = raw, !letters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice("剪贴板里没有链接")
            return
        }
        let text = LinkField.extractLink(letters)
        if let ed = field.currentEditor() as? NSTextView {
            let full = NSRange(location: 0, length: (ed.string as NSString).length)
            ed.insertText(text, replacementRange: full)
        } else {
            field.stringValue = text
        }
    }

    // MARK: 回车

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { NSSound.beep(); return true }
            onSubmit?(text)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            blur()
            return true
        }
        return false
    }

    /// 只是防止贴进超长文本，真假判定交给回车
    func controlTextDidChange(_ obj: Notification) {
        let v = field.stringValue
        if v.count > 400 { field.stringValue = String(v.prefix(400)) }
        needsDisplay = true
    }

    /// 调试用：直接灌文字，验证截断与占位提示
    func debugSetText(_ text: String) {
        field.stringValue = text
    }
}

private enum PanelHit: Equatable {
    case none, library, thumb(Int)
}

// MARK: - 面板左上角的动态徽章

/// 白色圆角底 + 果冻摇摆帧（跟菜单栏同一套动画）。
/// 单独做成子视图：20fps 只重绘这 38pt 一小块，面板别的内容（缩略图、文字）
/// 不用跟着抖，也就不会整块闪。
final class JellyBadgeView: NSView {
    /// 30 帧一轮 = 1.5 秒一个来回，和视频里一个摇摆周期的节奏一致
    private static let fps: Double = 20
    /// 视图比徽章大一圈，给投影留位置：贴着视图边画会被裁出一条硬边
    static let shadowPad: CGFloat = 6

    private var frames: [NSImage] = []
    private var timer: Timer?
    private var index = 0
    /// 调试用：VW_BADGE_FREEZE=7 锁在第 7 帧不动，方便截图比对姿态
    private static let freezeIndex = ProcessInfo.processInfo
        .environment["VW_BADGE_FREEZE"].flatMap { Int($0) }
    /// 调试用：VW_BADGE_DEBUG=1 时打印帧号，确认动画真的在走
    private static let verbose = ProcessInfo.processInfo.environment["VW_BADGE_DEBUG"] != nil

    override var isFlipped: Bool { true }
    /// 图标不吃点击：面板上的鼠标事件该给谁还给谁
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        frames = BrandMark.badgeFrames
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func startAnimating() {
        guard timer == nil, !frames.isEmpty else { return }
        // 锁帧调试：停在指定姿态，用来截图核对上下方向对不对
        if let f = Self.freezeIndex {
            index = min(max(f, 0), frames.count - 1)
            needsDisplay = true
            return
        }
        // 系统开了「减弱动态效果」就停在第一帧（静止姿态）
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let t = Timer(timeInterval: 1.0 / Self.fps, repeats: true) { [weak self] _ in
            guard let self, !self.frames.isEmpty else { return }
            self.index = (self.index + 1) % self.frames.count
            self.needsDisplay = true
            if Self.verbose { print("[badge] frame \(self.index)") }
        }
        t.tolerance = 0.004
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: Self.shadowPad, dy: Self.shadowPad)
        guard box.width > 1 else { return }
        let radius = box.width * 0.185          // 跟品牌徽章同一个圆角比例
        let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowBlurRadius = 5
        sh.shadowOffset = NSSize(width: 0, height: -1.5)
        sh.shadowColor = NSColor.black.withAlphaComponent(0.20)
        sh.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        guard !frames.isEmpty else {
            drawUpright(BrandMark.badge, in: box)
            return
        }
        let img = frames[min(index, frames.count - 1)]
        let w = img.size.width, h = img.size.height
        if Self.verbose, index % 15 == 0 { print("[badge] bounds=\(bounds.size) box=\(box) img=\(img.size)") }
        drawUpright(img, in: NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
    }

    /// 这个视图是 flipped（y 向下），NSImage 直接在翻过的上下文里画会上下颠倒，
    /// 果冻就变成「头朝下抖」——所以统一取 CGImage、手动把 y 翻回来。
    private func drawUpright(_ img: NSImage?, in rect: NSRect) {
        guard let img,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}

final class PanelBody: NSView {
    static let width: CGFloat = 344
    /// 卡片本身的高度（不含上面那个指向图标的小尖角）
    static let contentHeight: CGFloat = 265
    /// 尖角高度
    static let tail: CGFloat = 11
    static var height: CGFloat { contentHeight + tail }

    /// 毛玻璃的遮罩：圆角卡片 + 顶上那个小尖角，和 draw() 用的是同一套坐标。
    /// 走 CGContext 直接出图，不用 lockFocus（那玩意儿在图层渲染期间容易把堆踩坏）。
    static func glassMask(size: CGSize, tailCenter: CGFloat) -> NSImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let scale: CGFloat = 2
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)
                                      ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        // CG 原点在左下，翻成左上，后面就能照抄绘制代码的坐标
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: tail,
                                               width: size.width, height: size.height - tail),
                           cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.fillPath()

        let cx = min(max(tailCenter, 34), size.width - 34)
        let half: CGFloat = 8.5
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx - half, y: tail + 3))
        ctx.addLine(to: CGPoint(x: cx - 1.7, y: 2.7))
        ctx.addQuadCurve(to: CGPoint(x: cx + 1.7, y: 2.7), control: CGPoint(x: cx, y: 1.1))
        ctx.addLine(to: CGPoint(x: cx + half, y: tail + 3))
        ctx.closePath()
        ctx.fillPath()

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: size)
    }

    /// 尖角中心相对面板左边的位置（跟着状态栏按钮走）
    var tailCenter: CGFloat = PanelBody.width / 2

    var data = PanelData() {
        didSet {
            stripOffset = min(stripOffset, maxOffset)
            // 切完壁纸这一条里被点中的缩略图会被换掉，残留的高亮要清掉
            hover = .none
            needsDisplay = true
        }
    }

    var onSelect: ((Int) -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onCancel: (() -> Void)?
    /// 右上角链接框回车后把链接交给外面去下载
    var onPasteLink: ((String) -> Void)?

    private let linkField = PanelLinkField()
    /// 左上角会晃的果冻徽章（子视图，自己管自己的动画）
    private let badgeView = JellyBadgeView(frame: .zero)
    private var hover: PanelHit = .none
    private var tracking: NSTrackingArea?
    private var stripOffset: CGFloat = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        linkField.onSubmit = { [weak self] text in self?.submitLink(text) }
        addSubview(linkField)
        linkField.frame = linkFieldFrame
        addSubview(badgeView)
        badgeView.frame = badgeFrame
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        linkField.frame = linkFieldFrame
        badgeView.frame = badgeFrame
    }

    /// 徽章视图的落点：跟 iconRect 同心，但四周多留 shadowPad 给投影
    private var badgeFrame: NSRect {
        iconRect.insetBy(dx: -JellyBadgeView.shadowPad, dy: -JellyBadgeView.shadowPad)
            .offsetBy(dx: 0, dy: PanelBody.tail)
    }

    func startBadge() { badgeView.startAnimating() }
    func stopBadge() { badgeView.stopAnimating() }

    /// draw() 里整块内容往下平移了 tail（把顶部尖角让出来），但那只是绘制坐标系；
    /// 子视图不在这条平移里，必须自己补上，否则链接框会比分隔线高出一个尖角的高度。
    private var linkFieldFrame: NSRect {
        linkRect.offsetBy(dx: 0, dy: PanelBody.tail)
    }

    /// 回车：像链接才往下走，不像就原地提示一句
    private func submitLink(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Downloader.looksLikeLink(text) else {
            linkField.notice("这不像一条视频链接")
            return
        }
        onPasteLink?(text)
    }

    var isEditingLink: Bool { linkField.isEditing }
    func endLinkEditing() { linkField.blur() }
    func clearLink() { linkField.clear() }
    func noticeLink(_ msg: String) { linkField.notice(msg) }

    /// 后台生成壁纸的进度：全写在这块面板的链接框里，不另开窗口
    func showImportProgress(_ text: String, progress: Double = 0) {
        linkField.showBusy(text, progress: progress)
    }
    func showImportDone(_ text: String, isError: Bool = false) {
        linkField.showDone(text, isError: isError)
    }

    /// 新素材入库后把那一颗缩略图滚进可见范围：它只是出现在这一排里，
    /// 用不用还是用户自己点 —— 下载不该动桌面。
    func revealThumb(_ i: Int, data: PanelData) {
        self.data = data
        guard let item = stripItems.first(where: { $0.index == i }) else { return }
        let vp = stripViewport
        if item.rect.minX < vp.minX {
            stripOffset = min(max(stripOffset - (vp.minX - item.rect.minX), 0), maxOffset)
        } else if item.rect.maxX > vp.maxX {
            stripOffset = min(max(stripOffset + (item.rect.maxX - vp.maxX), 0), maxOffset)
        }
        needsDisplay = true
    }

    /// 调试用：把文字填进链接框再走一遍回车校验（不联网，只看提示）
    func debugSubmitLink(_ text: String) {
        linkField.debugSetText(text)
        submitLink(text)
    }

    /// 调试用：聚焦链接框并回报第一响应者，验证键盘能不能进来
    func debugFocusLink() {
        print("[panel] before appActive=\(NSApp.isActive) key=\(window?.isKeyWindow == true)")
        linkField.focus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let fr = self?.window?.firstResponder
            print("[panel] after appActive=\(NSApp.isActive) key=\(self?.window?.isKeyWindow == true) "
                  + "isFieldEditor=\(fr is NSTextView) editing=\(self?.isEditingLink == true)")
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    // MARK: 布局（坐标都是「卡片内部」的，不含尖角）

    private let pad: CGFloat = 16

    // 头部：图标 + 标题（右上角原来那个「退出」已经去掉，退出走右键菜单）
    private var iconRect: NSRect { NSRect(x: pad, y: 16, width: 38, height: 38) }
    private var titleRect: NSRect { NSRect(x: 66, y: 16, width: 142, height: 20) }
    /// 视频链接：原来是右上角那颗小胶囊，现在挪到通栏那一行的位置。
    /// 宽度跟面板内容区一致，点一下就能粘，空着的时候文字居中，像一颗按钮。
    /// 竖向节奏统一成 16：图标底 54 → 输入框 70 → 输入框底 100
    /// → 分隔线 116 → 分隔线底 117 → 预览图 133 → 预览图底 193 → 缩略图条 209
    private var linkRect: NSRect {
        NSRect(x: pad, y: 70, width: bounds.width - pad * 2, height: 30)
    }
    /// 静态信息：原来在底部的三列，现在缩成标题下面一行小字
    private var statsRect: NSRect { NSRect(x: 66, y: 40, width: bounds.width - 66 - pad, height: 14) }

    /// 壁纸库入口：「壁纸库 ›」纯文字 + 一个放大过的箭头，热区贴着文字收
    /// （不然右边空一片也能点）。位置压在参数下面、缩略图条上面那一线。
    private var libraryRect: NSRect {
        let w = libraryLabel(Ink.tertiary).size().width
            + libraryArrowGap + libraryArrow(Ink.tertiary).size().width
        // 高 20、底边压到缩略图条上沿（209）为止，热区不跟缩略图抢 1pt
        return NSRect(x: bounds.width - pad - w - 4, y: 189, width: w + 8, height: 20)
    }

    /// 文字与箭头之间的空隙、箭头的竖向微调（按墨迹中线对齐，不是按基线）
    private let libraryArrowGap: CGFloat = 5
    private let libraryArrowDrop: CGFloat = -4.5

    // 正在使用：封面在左，右边两行——标题 / 参数
    // 这两行要跟左边封面竖向居中（封面 124…184，中心 154；文字墨迹大约占 38 高）
    private var thumbRect: NSRect { NSRect(x: pad, y: 133, width: 96, height: 60) }
    private var nameRect: NSRect { NSRect(x: 124, y: 144, width: bounds.width - 124 - pad, height: 19) }
    private var metaRect: NSRect { NSRect(x: 124, y: 167, width: bounds.width - 124 - pad, height: 15) }

    // 缩略图条
    private let itemW: CGFloat = 62
    private let itemH: CGFloat = 40
    private let itemGap: CGFloat = 8
    private var stripY: CGFloat { 209 }
    private var stripViewport: NSRect {
        NSRect(x: pad, y: stripY - 3, width: bounds.width - pad * 2, height: itemH + 6)
    }

    /// 除当前这张以外的所有壁纸，横向排开（可左右滑）
    private var stripItems: [(index: Int, rect: NSRect)] {
        guard data.thumbs.count > 1 else { return [] }
        var out: [(Int, NSRect)] = []
        var x = pad - stripOffset
        for i in data.thumbs.indices where i != data.currentIndex {
            out.append((i, NSRect(x: x, y: stripY, width: itemW, height: itemH)))
            x += itemW + itemGap
        }
        return out
    }

    private var stripContentWidth: CGFloat {
        let n = max(0, data.thumbs.count - 1)
        return CGFloat(n) * itemW + CGFloat(max(0, n - 1)) * itemGap
    }

    private var maxOffset: CGFloat {
        max(0, stripContentWidth - (bounds.width - pad * 2))
    }

    // MARK: 卡片外形（圆角 + 顶部小尖角）

    private func cardPath() -> NSBezierPath {
        let card = NSRect(x: 0.5, y: PanelBody.tail + 0.5,
                          width: bounds.width - 1, height: bounds.height - PanelBody.tail - 1)
        return NSBezierPath(roundedRect: card, xRadius: 20, yRadius: 20)
    }

    /// 尖角单独成一条路径：不能 append 到圆角矩形上，
    /// 两个子路径绕向相反时非零填充规则会把重叠处挖空（接缝透出一条横线）。
    /// 斜边用直线（曲线会鼓成圆包），只在最尖端做个小圆角。
    private func tailPath() -> NSBezierPath {
        let t = PanelBody.tail
        let cx = min(max(tailCenter, 34), bounds.width - 34)
        let half: CGFloat = 8.5
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx - half, y: t + 3))
        p.line(to: NSPoint(x: cx - 1.7, y: 2.7))
        p.curve(to: NSPoint(x: cx + 1.7, y: 2.7),
                controlPoint1: NSPoint(x: cx - 0.55, y: 1.1),
                controlPoint2: NSPoint(x: cx + 0.55, y: 1.1))
        p.line(to: NSPoint(x: cx + half, y: t + 3))
        p.close()
        return p
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 先描边再填色：填色盖掉内侧半个描边，只剩一条极淡的外轮廓；
        // 尖角最后单独填，把卡片顶边经过它的那一段盖住，接缝不会留横线。
        let card = cardPath()
        let tail = tailPath()
        Ink.edge.setStroke()
        card.lineWidth = 1
        card.stroke()
        tail.lineWidth = 1
        tail.stroke()
        let grad = NSGradient(starting: Ink.surfaceBottom, ending: Ink.surfaceTop)
        if let grad {
            grad.draw(in: card, angle: 90)
            grad.draw(in: tail, angle: 90)
        } else {
            Ink.surface.setFill()
            card.fill()
            tail.fill()
        }

        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(
            roundedRect: NSRect(x: 0, y: PanelBody.tail, width: bounds.width,
                                height: bounds.height - PanelBody.tail),
            xRadius: 20, yRadius: 20)
        clip.addClip()
        // 之后所有内容都按「卡片内部坐标」画，不用每条都 +tail
        NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: PanelBody.tail)

        drawHeader()
        drawLibraryButton()
        divider(at: 116)

        drawCurrent()
        drawStrip()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHeader() {
        // 徽章是子视图自己在画（带动画），这里只在视图缺位时兜底
        if badgeView.superview == nil { drawIcon() }
        text("Dòng", titleRect, size: 15.5, weight: .semibold, color: Ink.primary)
        // 原来这下面是「● 正在播放」，跟下面的「正在使用」重复，去掉了；
        // 换成三五个字的静态信息，做小做淡，不抢照片。
        drawStatsLine()
    }

    /// 张数 / 磁盘 / 在线：一行小字，数字稍重、标签更淡
    private func drawStatsLine() {
        // 统一成「标签 + 数值」：标签淡灰在前，数值 semibold 近黑在后
        // （原来三段的语序各写各的：24 张壁纸 / 948 MB 磁盘 / 在线时长 6 小时 57 分）
        let items: [(String, String)] = [
            ("壁纸 ", "\(data.wallpapers.count) 张"),
            ("磁盘 ", data.diskText),
            ("在线 ", data.todayText),
        ]
        var x = statsRect.minX
        let y = statsRect.minY
        let valueFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: 10.5)

        for (i, item) in items.enumerated() {
            if i > 0 {
                // 6 而不是 7：给「在线 23 小时 59 分」这种最长组合留出不截断的余量
                let gap: CGFloat = 6
                let dw = ("·" as NSString).size(withAttributes: [.font: labelFont]).width
                text("·", NSRect(x: x + gap, y: y, width: dw + 1, height: 14),
                     size: 10.5, color: Ink.tertiary.withAlphaComponent(0.55))
                x += gap + dw + gap
            }
            let w = (item.0 as NSString).size(withAttributes: [.font: labelFont]).width
            text(item.0, NSRect(x: x, y: y, width: w + 1, height: 14),
                 size: 10.5, color: Ink.tertiary)
            x += w

            let vw = (item.1 as NSString).size(withAttributes: [.font: valueFont]).width
            text(item.1, NSRect(x: x, y: y, width: vw + 1, height: 14),
                 size: 10.5, weight: .semibold, color: Ink.primary)
            x += vw
        }
    }

    /// 壁纸库入口：纯文字 + 一个箭头，没有底色也没有图标，悬停只变色。
    /// 箭头以前用 SF Symbol 画，图标自带留白、跟文字基线对不齐（看着偏高）。
    /// 现在整串当成一段文字画，箭头是「›」字符，两段共基线，天然居中。
    private func libraryLabel(_ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: "壁纸库",
                           attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                                        .foregroundColor: color])
    }

    /// 箭头字号单独放大：10.5pt 的「›」墨迹只有 5pt 高，存在感几乎没有
    private func libraryArrow(_ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: "›",
                           attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium),
                                        .foregroundColor: color.withAlphaComponent(0.85)])
    }

    private func drawLibraryButton() {
        let r = libraryRect
        // 平时再淡一档（tertiary 已经比正文灰，再乘 0.72），悬停才回到能看清的程度
        let tint = hover == .library ? Ink.secondary.withAlphaComponent(0.92)
                                     : Ink.tertiary.withAlphaComponent(0.62)
        let label = libraryLabel(tint)
        let arrow = libraryArrow(tint)
        let lw = label.size().width
        let x0 = r.minX + 5
        label.draw(in: NSRect(x: x0, y: r.midY - 8, width: lw + 1, height: 16))
        // 箭头单独摆：字号更大，基线跟文字一起会偏上，按墨迹中线补一个 drop
        arrow.draw(in: NSRect(x: x0 + lw + libraryArrowGap,
                              y: r.midY - 8 + libraryArrowDrop,
                              width: arrow.size().width + 1, height: 16))
    }

    private func drawCurrent() {
        drawCoverThumb(data.thumb, in: thumbRect)
        text(data.name.isEmpty ? "还没有壁纸" : data.name, nameRect,
             size: 14.5, weight: .semibold, color: Ink.primary)
        text(metaLine(), metaRect, size: 11.5, color: Ink.tertiary)
    }

    /// 其他壁纸：横向一条，超出就左右滑（滚轮 / 触控板 / 直接拖）
    private func drawStrip() {
        let items = stripItems
        guard !items.isEmpty else { return }
        let viewport = stripViewport

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: viewport).addClip()

        for item in items {
            guard item.rect.maxX > viewport.minX - 4, item.rect.minX < viewport.maxX + 4 else { continue }
            drawCoverThumb(data.thumbs.indices.contains(item.index) ? data.thumbs[item.index] : nil,
                           in: item.rect)
        }

        // 两端渐隐，暗示还能继续滑
        let fadeW: CGFloat = 22
        if stripOffset > 0.5 {
            let left = NSRect(x: viewport.minX, y: viewport.minY, width: fadeW, height: viewport.height)
            NSGradient(starting: Ink.surface.withAlphaComponent(0.95),
                       ending: Ink.surface.withAlphaComponent(0))?.draw(in: left, angle: 0)
        }
        if stripOffset < maxOffset - 0.5 {
            let right = NSRect(x: viewport.maxX - fadeW, y: viewport.minY, width: fadeW, height: viewport.height)
            NSGradient(starting: Ink.surface.withAlphaComponent(0),
                       ending: Ink.surface.withAlphaComponent(0.95))?.draw(in: right, angle: 0)
        }

        NSGraphicsContext.restoreGraphicsState()

        // 悬停描边单独画：它比图框大 1pt，跟着内容区裁会把最左/最右那一条边切掉，
        // 看着就像框「跑」到卡片外面去了。所以换一个左右各外扩 2pt 的裁切框单独画这一圈。
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: viewport.insetBy(dx: -2, dy: 0)).addClip()
        for item in items where hover == .thumb(item.index) {
            guard item.rect.maxX > viewport.minX, item.rect.minX < viewport.maxX else { continue }
            let ring = NSBezierPath(roundedRect: item.rect.insetBy(dx: -1, dy: -1),
                                    xRadius: 8.5, yRadius: 8.5)
            Ink.secondary.setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 分辨率 · 帧率 · 时长，时长写成 20s 这种短形式，比「20 秒」利落；单位一律小写
    private func metaLine() -> String {
        var parts: [String] = []
        if !data.meta.isEmpty { parts.append(data.meta) }
        if let d = durationTag() { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    private func durationTag() -> String? {
        guard data.duration > 0.5 else { return nil }
        let total = Int(data.duration.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60, s = total % 60
        return s == 0 ? "\(m)m" : "\(m)m\(s)s"
    }

    /// 品牌标记：面板左上角用「米白圆角底 + 果冻」的徽章，跟网站下载卡一致。
    /// BrandMarkBadge.png 是矢量导出的 128px 位图，缩到 38pt 仍然锐利。
    /// 找不到资源时退回旧的渐变方块，绝不空着。
    private func drawIcon() {
        let r = iconRect
        if let img = BrandMark.badge {
            let sh = NSShadow()
            sh.shadowBlurRadius = 5
            sh.shadowOffset = NSSize(width: 0, height: -1.5)
            sh.shadowColor = NSColor.black.withAlphaComponent(0.20)
            NSGraphicsContext.saveGraphicsState()
            sh.set()
            img.draw(in: r)
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        if let img = BrandMark.mark {
            let box = r.insetBy(dx: 1, dy: 1)
            let s = min(box.width / img.size.width, box.height / img.size.height)
            let w = img.size.width * s, h = img.size.height * s
            img.draw(in: NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
            return
        }
        let path = NSBezierPath(roundedRect: r, xRadius: 11.5, yRadius: 11.5)
        if let g = NSGradient(colors: [Brand.gradTop, Brand.gradBottom]) {
            g.draw(in: path, angle: -70)
        } else {
            Brand.accent.setFill()
            path.fill()
        }
        guard let base = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: nil) else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let img = base.withSymbolConfiguration(cfg) ?? base
        let s = img.size
        img.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2,
                            width: s.width, height: s.height))
    }

    private func drawCoverThumb(_ img: NSImage?, in r: NSRect) {
        let path = NSBezierPath(roundedRect: r, xRadius: 7.5, yRadius: 7.5)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let img, img.size.width > 0, img.size.height > 0 {
            let s = max(r.width / img.size.width, r.height / img.size.height)
            let w = img.size.width * s, h = img.size.height * s
            img.draw(in: NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
        } else {
            Ink.fill.setFill()
            r.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        Ink.edge.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// 通栏发丝线：左右各内缩一个 pad，跟输入框、预览图同一条左右基准线，
    /// 不跟着卡片圆角一路顶到边（那样在圆角处会显得比内容宽出去一截）
    private func divider(at y: CGFloat) {
        Ink.hair.setFill()
        NSRect(x: pad, y: y, width: bounds.width - pad * 2, height: 1).fill()
    }

    private func text(_ s: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor, align: NSTextAlignment = .left) {
        guard !s.isEmpty else { return }
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: p,
        ]
        (s as NSString).draw(in: rect, withAttributes: attrs)
    }

    // MARK: 交互

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private func hit(at point: NSPoint) -> PanelHit {
        var p = point
        p.y -= PanelBody.tail          // 内容坐标不含尖角
        if p.y < 0 { return .none }
        if libraryRect.contains(p) { return .library }
        if stripViewport.contains(p) {
            for item in stripItems where item.rect.insetBy(dx: -2, dy: -2).contains(p) {
                return .thumb(item.index)
            }
        }
        return .none
    }

    override func mouseMoved(with event: NSEvent) {
        let h = hit(at: convert(event.locationInWindow, from: nil))
        if h != hover { hover = h; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hover != .none { hover = .none; needsDisplay = true }
    }

    /// 调试用：把某张缩略图钉成悬停态，拍照核对描边有没有被裁掉
    func debugHover(_ index: Int) {
        hover = .thumb(index)
        needsDisplay = true
    }

    /// 缩略图条：滚轮 / 触控板双指滑，或者直接按住在条上拖
    private var pressPoint: NSPoint = .zero
    private var pressOffset: CGFloat = 0
    private var pressHit: PanelHit = .none
    private var dragged = false

    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        pressHit = hit(at: pressPoint)
        pressOffset = stripOffset
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard maxOffset > 0 else { return }
        var pp = pressPoint
        pp.y -= PanelBody.tail
        guard stripViewport.contains(pp) else { return }

        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - pressPoint.x
        if abs(dx) > 3 { dragged = true }
        guard dragged else { return }
        stripOffset = min(max(pressOffset - dx, 0), maxOffset)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragged = dragged
        let h = pressHit
        dragged = false
        pressHit = .none
        guard !wasDragged else { return }
        switch h {
        case .library: onOpenLibrary?()
        case .thumb(let i): onSelect?(i)
        case .none: break
        }
    }

    /// 调试用：直接改偏移量，验证横向滚动
    func debugScroll(_ dx: CGFloat) {
        stripOffset = min(max(stripOffset + dx, 0), maxOffset)
        needsDisplay = true
        print("[strip] offset=\(stripOffset) max=\(maxOffset) items=\(stripItems.count)")
    }

    override func scrollWheel(with event: NSEvent) {
        guard maxOffset > 0 else { return }
        let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        guard dx != 0 else { return }
        let next = min(max(stripOffset - dx, 0), maxOffset)
        if next != stripOffset {
            stripOffset = next
            needsDisplay = true
        }
    }
}

// MARK: - 浮层窗口

/// 装内容的壳：只负责图层动画，不参与绘制
private final class PanelShell: NSView {
    override var isOpaque: Bool { false }
}

/// 面板底下那层系统毛玻璃。窗口是 borderless + 透明底，
/// `.behindWindow` 才会去抓窗口后面的壁纸来模糊；再用卡片轮廓当 mask 把圆角和尖角切出来。
private final class PanelGlass: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // .menu：比 .popover 更轻薄的一档磨砂（系统菜单用的就是它），
        // 背后依然糊成一片、认不出字，但颗粒感没那么重，透出来的颜色更干净
        material = .menu
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 尖角跟着菜单栏图标跑，每次弹出都要重画遮罩
    func updateMask(tailCenter: CGFloat) {
        maskImage = PanelBody.glassMask(size: bounds.size, tailCenter: tailCenter)
    }
}

/// 无边框窗口默认当不了 key window，右上角那个输入框就收不到键盘。
/// 这里放开 canBecomeKey（但仍然不做 main window）。
private final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class MenuPanelController: NSWindowController {
    let body = PanelBody(frame: .zero)
    private let shell = PanelShell()
    private let glass = PanelGlass(frame: .zero)
    private var monitorLocal: Any?
    private var monitorGlobal: Any?
    private var closing = false
    /// 弹出前自己是不是已经在前台：为了打字抢过焦点，收起来时再还回去
    private var activeBeforeShow = true

    init() {
        let win = PanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: PanelBody.width, height: PanelBody.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        win.isFloatingPanel = true
        // 只有点到要打字的地方才拿键盘，点缩略图不该把别人的输入抢走
        win.becomesKeyOnlyIfNeeded = true
        win.level = .statusBar
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        win.animationBehavior = .none

        shell.frame = NSRect(x: 0, y: 0, width: PanelBody.width, height: PanelBody.height)
        shell.autoresizingMask = [.width, .height]
        shell.wantsLayer = true
        win.contentView = shell

        // 毛玻璃垫在最底下，body 再画一层淡白和内容
        glass.frame = shell.bounds
        glass.autoresizingMask = [.width, .height]
        shell.addSubview(glass)
        glass.updateMask(tailCenter: PanelBody.width / 2)

        body.frame = shell.bounds
        body.autoresizingMask = [.width, .height]
        shell.addSubview(body)

        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isShown: Bool { window?.isVisible ?? false }
    private(set) var lastDismiss = Date.distantPast

    func refresh(_ data: PanelData) {
        body.data = data
    }

    /// 链接交出去之后把输入框清空，下次打开是干净的
    func clearLink() { body.clearLink() }

    /// 后台导入的进度 / 结论，都落在面板自己的链接框里
    func showImportProgress(_ text: String, progress: Double = 0) {
        body.showImportProgress(text, progress: progress)
    }
    func showImportDone(_ text: String, isError: Bool = false) {
        body.showImportDone(text, isError: isError)
    }

    /// 导入完成后把新缩略图滚进可见范围（只是露面，不替用户换壁纸）
    func revealThumb(_ i: Int, data: PanelData) {
        body.revealThumb(i, data: data)
    }

    func show(relativeTo button: NSStatusBarButton, data: PanelData) {
        body.data = data
        guard let win = window, let buttonWindow = button.window else { return }

        let rectInWindow = button.convert(button.bounds, to: nil)
        let anchor = buttonWindow.convertToScreen(rectInWindow)
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY))
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var x = anchor.midX - PanelBody.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - PanelBody.width - 8)
        // 尖角指着图标：面板顶边正好贴住菜单栏底边
        var y = anchor.minY - PanelBody.height
        y = max(y, visible.minY + 8)

        body.tailCenter = min(max(anchor.midX - x, 34), PanelBody.width - 34)
        body.needsDisplay = true
        glass.updateMask(tailCenter: body.tailCenter)

        win.setFrame(NSRect(x: x, y: y, width: PanelBody.width, height: PanelBody.height), display: true)
        if ProcessInfo.processInfo.environment["VW_PANEL_DEBUG"] != nil {
            print("[panel] anchor=\(Int(anchor.minX)),\(Int(anchor.minY)) \(Int(anchor.width))x\(Int(anchor.height)) "
                  + "frame=\(Int(x)),\(Int(y)) tail=\(Int(body.tailCenter))")
        }

        closing = false
        activeBeforeShow = NSApp.isActive
        win.alphaValue = 0
        win.orderFrontRegardless()
        // 不抢应用焦点，但让面板能接按键（ESC 收起）
        win.makeKey()
        win.makeFirstResponder(body)
        body.onCancel = { [weak self] in self?.dismiss() }
        body.startBadge()
        playIn()
        installMonitors()
    }

    // MARK: 动效

    /// 从尖角那一点"长"出来：缩放锚点设在尖角，带一点过冲的回弹。
    private func playIn() {
        guard let layer = shell.layer else { return }
        layer.removeAllAnimations()

        let size = shell.bounds.size
        let ax = body.tailCenter / max(size.width, 1)
        layer.anchorPoint = CGPoint(x: ax, y: 1)
        layer.position = CGPoint(x: size.width * ax, y: size.height)
        layer.transform = CATransform3DIdentity

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.84
        spring.toValue = 1.0
        spring.mass = 1
        spring.stiffness = 520
        spring.damping = 28
        spring.initialVelocity = 3
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")

        // 淡入用窗口 alpha：图层 opacity 淡不到窗口投影，会先冒出一个满尺寸的影子
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1
        }

        if ProcessInfo.processInfo.environment["VW_PANEL_DEBUG"] != nil {
            print("[panel] anim=\(layer.animationKeys() ?? []) anchor=\(layer.anchorPoint) pos=\(layer.position) size=\(size)")
        }
    }

    /// 收起：缩回去一点点再淡出，比直接消失更像"回到了图标里"
    private func playOut(then finish: @escaping () -> Void) {
        guard let layer = shell.layer, shell.bounds.width > 0 else { finish(); return }
        layer.removeAllAnimations()
        let size = shell.bounds.size
        let ax = body.tailCenter / max(size.width, 1)
        layer.anchorPoint = CGPoint(x: ax, y: 1)
        layer.position = CGPoint(x: size.width * ax, y: size.height)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.965
        scale.duration = 0.10
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(scale, forKey: "shrink")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            finish()
        }
    }

    func debugScroll(_ dx: CGFloat) {
        body.debugScroll(dx)
    }

    /// 调试：把面板画成 PNG（沙盒没有屏幕录制权限时验版式用）
    /// 直接把图层缓存写成文件，不再套一层 NSImage 合成——那条路在 draw 之后
    /// 调 lockFocus 会把堆踩坏，偶发 SIGTRAP。
    func snapshot(to path: String) {
        // 环境变量偶尔取出来是空的，兜一个固定路径，别让调试白跑
        let out = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // 环境变量偶尔传进来是一串空格，路径里必须有 / 才认
        let target = out.contains("/") && !out.hasSuffix("/") ? out : "/tmp/panel.png"
        guard let rep = body.bitmapImageRepForCachingDisplay(in: body.bounds) else {
            print("[snapshot] 没有 rep")
            return
        }
        body.cacheDisplay(in: body.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("[snapshot] 编码失败")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: target))
            print("[snapshot] \(Int(rep.pixelsWide))x\(Int(rep.pixelsHigh)) -> \(target)")
        } catch {
            print("[snapshot] 写失败 \(target): \(error)")
        }
    }

    func dismiss() {
        guard !closing else { return }
        closing = true
        lastDismiss = Date()
        removeMonitors()
        playOut { [weak self] in
            guard let self else { return }
            self.body.stopBadge()
            self.window?.orderOut(nil)
            self.closing = false
            self.releaseActivation()
        }
    }

    /// 为了打字把 App 拉到前台了；面板收起来后如果自己没别的窗口，就把焦点还给原来的 App
    private func releaseActivation() {
        guard !activeBeforeShow, NSApp.isActive else { return }
        let othersVisible = NSApp.windows.contains { $0.isVisible && $0 !== window }
        guard !othersVisible else { return }
        NSApp.deactivate()
    }

    /// 屏幕外点一下就收起
    private func installMonitors() {
        removeMonitors()
        monitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
            [weak self] event in
            guard let self, let win = self.window else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    // 正在往链接框里打字：ESC 先退出输入，别把整块面板收掉
                    if self.body.isEditingLink {
                        self.body.endLinkEditing()
                    } else {
                        self.dismiss()
                    }
                    return nil
                }
                return event
            }
            if !win.frame.contains(NSEvent.mouseLocation) { self.dismiss() }
            return event
        }
        monitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.dismiss()
        }
    }

    private func removeMonitors() {
        if let m = monitorLocal { NSEvent.removeMonitor(m); monitorLocal = nil }
        if let m = monitorGlobal { NSEvent.removeMonitor(m); monitorGlobal = nil }
    }
}
