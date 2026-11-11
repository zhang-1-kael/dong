import Cocoa
import AVFoundation
import QuartzCore
import UniformTypeIdentifiers

// MARK: - 数据源协议（与 App 侧保持一致）

protocol WallpaperLibraryDelegate: AnyObject {
    func libraryVideos() -> [URL]
    func libraryCurrentIndex() -> Int
    func libraryApply(index: Int)
    func libraryDelete(index: Int)
    func libraryAdd(urls: [URL])
    func libraryAddLink()
    /// 直接拿一条已经确认过的链接去下载
    func libraryImportLink(_ link: String)
    func libraryRevealFolder()

    // 开关状态（现在排在窗口底部那一行）
    func libraryIsEnabled() -> Bool
    func librarySetEnabled(_ on: Bool)
    func libraryIsLockSync() -> Bool
    func librarySetLockSync(_ on: Bool)
    func libraryIsAutostart() -> Bool
    func librarySetAutostart(_ on: Bool)
}

// MARK: - 版面常量

private enum Look {
    static let gap: CGFloat = 16
    static let inset: CGFloat = 12
    static let maxColW: CGFloat = 300
    static let maxCols: Int = 6
    static let radius: CGFloat = 14
    /// 顶部留白：只避开红绿灯，链接框已经挪到底部了
    static let topInset: CGFloat = 46
    /// 底部留白：卡片要从悬浮底座下面穿过去，最后一行不能被挡住
    static let bottomInset: CGFloat = 72
    /// 底部底座（悬浮条）：距窗口边缘、条高
    static let barInset: CGFloat = 16
    static let barHeight: CGFloat = 44
}

// MARK: - 封面图（比菜单缩略图大一号，专门给瀑布流用）

enum GalleryThumb {
    static var dir: URL {
        Source.home.appendingPathComponent("Library/Application Support/VideoWallpaper/gallery")
    }

    struct Info {
        let aspect: CGFloat
        let duration: Double
        let pixel: String
        let fps: Int

        /// 「1920×1080 · 30fps」
        var descriptor: String {
            fps > 0 ? "\(pixel) · \(fps) fps" : pixel
        }
    }

    private static var memory: [String: NSImage] = [:]
    private static var infoCache: [String: Info] = [:]
    private static let queue = DispatchQueue(label: "vw.gallery.thumbs", qos: .userInitiated,
                                             attributes: .concurrent)
    private static let cacheLock = NSLock()

    private static func fileURL(for video: URL) -> URL {
        dir.appendingPathComponent(video.deletingPathExtension().lastPathComponent + ".jpg")
    }

    /// 视频宽高比 / 时长（主线程同步读本地文件，够快，只算一次）
    static func info(for url: URL) -> Info {
        let key = url.path
        if let hit = infoCache[key] { return hit }
        let asset = AVURLAsset(url: url)
        var aspect: CGFloat = 16.0 / 9.0
        var duration: Double = 0
        var pixel = "—"
        var fps = 0
        if let track = asset.tracks(withMediaType: .video).first {
            let s = track.naturalSize.applying(track.preferredTransform)
            let w = abs(s.width), h = abs(s.height)
            if w > 1, h > 1 {
                aspect = w / h
                pixel = "\(Int(w.rounded()))×\(Int(h.rounded()))"
            }
            let rate = track.nominalFrameRate
            if rate.isFinite, rate > 0 { fps = Int(rate.rounded()) }
        }
        let d = CMTimeGetSeconds(asset.duration)
        if d.isFinite, d > 0 { duration = d }
        let info = Info(aspect: aspect, duration: duration, pixel: pixel, fps: fps)
        infoCache[key] = info
        return info
    }

    /// 只要已经在磁盘上的封面，不做后台生成（面板弹出必须即时）
    static func cached(for video: URL) -> NSImage? {
        let key = video.path
        cacheLock.lock()
        let hit = memory[key]
        cacheLock.unlock()
        if let hit { return hit }
        guard let img = NSImage(contentsOf: fileURL(for: video)) else { return nil }
        cacheLock.lock(); memory[key] = img; cacheLock.unlock()
        return img
    }

    /// 有缓存立刻给，没有就后台抽帧，回来再补图（不卡窗口）
    static func load(for video: URL, completion: @escaping (NSImage?) -> Void) {
        let key = video.path
        cacheLock.lock()
        let hit = memory[key]
        cacheLock.unlock()
        if let hit { completion(hit); return }

        let out = fileURL(for: video)
        if let img = NSImage(contentsOf: out) {
            cacheLock.lock(); memory[key] = img; cacheLock.unlock()
            completion(img)
            return
        }
        queue.async {
            let ok = generate(from: video, to: out)
            let img = ok ? NSImage(contentsOf: out) : nil
            if let img {
                cacheLock.lock(); memory[key] = img; cacheLock.unlock()
            }
            DispatchQueue.main.async { completion(img) }
        }
    }

    /// 取时长的 35% 处那一帧（避开片头转场），存成 jpg
    @discardableResult
    private static func generate(from video: URL, to out: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if let thumbDate = (try? fm.attributesOfItem(atPath: out.path))?[.modificationDate] as? Date,
           let videoDate = (try? fm.attributesOfItem(atPath: video.path))?[.modificationDate] as? Date,
           thumbDate >= videoDate, fm.fileExists(atPath: out.path) {
            return true
        }

        let asset = AVURLAsset(url: video)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 900, height: 900)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 1.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1.5, preferredTimescale: 600)

        let dur = CMTimeGetSeconds(asset.duration)
        let t = (dur.isFinite && dur > 0.5) ? dur * 0.35 : 1.0
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg,
                                                                      properties: [.compressionFactor: 0.84])
        else { return false }
        return (try? data.write(to: out)) != nil
    }
}

// MARK: - 图片 + 播放器（悬停时视频盖在封面上）

private final class MediaView: NSView {
    let imageView = NSImageView()
    let playerHost = PlayerHost()

    var playerLayer: AVPlayerLayer { playerHost.playerLayer }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = false
        addSubview(imageView)

        // 关键：播放层必须是「后加的子视图」。
        // 之前直接往 self.layer 加 AVPlayerLayer，AppKit 排布子视图时会把它压到封面图层下面，
        // 结果视频一直在播（rate=1.0、时间在走），却整块被静态封面盖住，肉眼看就是没动。
        addSubview(playerHost)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setImage(_ image: NSImage?) {
        imageView.image = image
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 等比填满（cover），多出来的部分由 masksToBounds 裁掉，绝不拉变形
        if let img = imageView.image, img.size.width > 0, img.size.height > 0,
           bounds.width > 0, bounds.height > 0 {
            let scale = max(bounds.width / img.size.width, bounds.height / img.size.height)
            let w = img.size.width * scale, h = img.size.height * scale
            imageView.frame = NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2,
                                     width: w, height: h)
        } else {
            imageView.frame = bounds
        }
        playerHost.frame = bounds
        CATransaction.commit()
    }
}

/// 专门承载 AVPlayerLayer 的视图。它自己不带任何子视图，
/// 所以手写的子图层不会被 AppKit 重排到下面去。
private final class PlayerHost: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - 渐变遮罩（悬停时压一层，让白字看得清）

private final class GradientView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [
            NSColor.black.withAlphaComponent(0.80).cgColor,
            NSColor.black.withAlphaComponent(0.42).cgColor,
            NSColor.black.withAlphaComponent(0.0).cgColor,
        ]
        gradient.locations = [0, 0.45, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - 一张壁纸卡片

final class WallpaperCard: NSView {
    let url: URL
    let aspect: CGFloat

    var onApply: (() -> Void)?
    var onDelete: (() -> Void)?
    var onReveal: (() -> Void)?
    /// 开始悬停时通知外面，让别的卡片先收起来（同一时刻只允许一张卡是悬停态）
    var onHoverStart: (() -> Void)?

    private let thumbWrap = NSView()
    private let media = MediaView()
    private let shade = GradientView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "正在使用")

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var tracking: NSTrackingArea?
    private var hovered = false

    init(url: URL, aspect: CGFloat, name: String, meta: String) {
        self.url = url
        self.aspect = aspect
        super.init(frame: .zero)

        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.13
        layer?.shadowRadius = 11
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        thumbWrap.wantsLayer = true
        thumbWrap.layer?.cornerRadius = Look.radius
        thumbWrap.layer?.masksToBounds = true
        thumbWrap.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        addSubview(thumbWrap)

        media.wantsLayer = true
        thumbWrap.addSubview(media)

        shade.alphaValue = 0
        thumbWrap.addSubview(shade)

        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.alphaValue = 0
        thumbWrap.addSubview(nameLabel)

        metaLabel.stringValue = meta
        metaLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        metaLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.alphaValue = 0
        thumbWrap.addSubview(metaLabel)

        // 右上角删除（只在悬停时出现，平时不挡视线）
        deleteButton.isBordered = false
        deleteButton.wantsLayer = true
        deleteButton.layer?.cornerRadius = 11
        deleteButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "删除")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        deleteButton.contentTintColor = .white
        deleteButton.isHidden = true
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        addSubview(deleteButton)

        // 左上角「正在使用」
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        badge.isHidden = true
        badgeLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        badgeLabel.textColor = .white
        badge.addSubview(badgeLabel)
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { stopPlayback() }

    func setImage(_ image: NSImage?) {
        media.setImage(image)
    }

    func setCurrent(_ on: Bool) {
        badge.isHidden = !on
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = bounds.width, h = bounds.height
        thumbWrap.frame = bounds
        media.frame = thumbWrap.bounds
        media.needsLayout = true
        let pad: CGFloat = 12
        metaLabel.frame = NSRect(x: pad, y: pad, width: max(0, w - pad * 2), height: 14)
        nameLabel.frame = NSRect(x: pad, y: pad + 15, width: max(0, w - pad * 2), height: 18)
        shade.frame = NSRect(x: 0, y: 0, width: w, height: min(h, 148))
        deleteButton.frame = NSRect(x: w - 30, y: h - 30, width: 22, height: 22)

        let bw = ceil(badgeLabel.intrinsicContentSize.width) + 18
        badge.frame = NSRect(x: 10, y: h - 30, width: bw, height: 20)
        badgeLabel.frame = NSRect(x: 9, y: 3, width: bw - 18, height: 14)

        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Look.radius,
                                   cornerHeight: Look.radius, transform: nil)
        CATransaction.commit()
    }

    // MARK: 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { startHover() }
    override func mouseExited(with event: NSEvent) { endHover() }

    private func startHover() {
        guard !hovered else { return }
        // 只认「鼠标真的停在这张卡上」。窗口重新显示、滚动、系统补发事件时
        // 都可能收到假的 mouseEntered，靠这一句挡掉。
        guard let win = window else { return }
        let p = convert(win.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(p) else { return }

        hovered = true
        onHoverStart?()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            shade.animator().alphaValue = 1
            nameLabel.animator().alphaValue = 1
            metaLabel.animator().alphaValue = 1
        }
        deleteButton.isHidden = false
        thumbWrap.layer?.borderWidth = 1
        thumbWrap.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        if player == nil {
            let item = AVPlayerItem(url: url)
            let p = AVQueuePlayer()
            p.isMuted = true
            p.actionAtItemEnd = .advance
            p.automaticallyWaitsToMinimizeStalling = false
            looper = AVPlayerLooper(player: p, templateItem: item)
            player = p
            media.playerLayer.player = p
            p.play()
        } else {
            player?.play()
        }
        media.playerLayer.isHidden = false
    }

    private func endHover() {
        guard hovered else { return }
        hovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            shade.animator().alphaValue = 0
            nameLabel.animator().alphaValue = 0
            metaLabel.animator().alphaValue = 0
        }
        deleteButton.isHidden = true
        thumbWrap.layer?.borderWidth = 0
        stopPlayback()
    }

    /// 外部强制收回悬停态（窗口关掉、失焦、滚动、别的卡被悬停时）
    func clearHover() {
        guard hovered else { return }
        endHover()
    }

    var isHovering: Bool { hovered }

    /// 调试用：跳过「鼠标真的在这」的校验，直接进悬停态
    func debugSimulateHover() {
        guard !hovered else { return }
        hovered = true
        shade.alphaValue = 1
        nameLabel.alphaValue = 1
        metaLabel.alphaValue = 1
        deleteButton.isHidden = false
        thumbWrap.layer?.borderWidth = 1
        thumbWrap.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        let item = AVPlayerItem(url: url)
        let p = AVQueuePlayer()
        p.isMuted = true
        p.actionAtItemEnd = .advance
        p.automaticallyWaitsToMinimizeStalling = false
        looper = AVPlayerLooper(player: p, templateItem: item)
        player = p
        media.playerLayer.player = p
        p.play()
        media.playerLayer.isHidden = false
    }

    private func stopPlayback() {
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        media.playerLayer.player = nil
        media.playerLayer.isHidden = true
    }

    /// 卡片被移除前调用，别留着解码器
    func teardown() {
        endHover()
        stopPlayback()
    }

    var debugLine: String {
        let img = media.imageView.image
        let size = img.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "nil"
        let f = media.imageView.frame
        return "\(url.lastPathComponent) card=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) img=\(size) imgFrame=\(Int(f.width))x\(Int(f.height))@\(Int(f.minX)),\(Int(f.minY)) bounds=\(Int(bounds.width))x\(Int(bounds.height))"
    }

    // MARK: 交互

    override func mouseDown(with event: NSEvent) {
        onApply?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let apply = NSMenuItem(title: "设为壁纸", action: #selector(applyTapped), keyEquivalent: "")
        apply.target = self
        menu.addItem(apply)
        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealTapped), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        menu.addItem(.separator())
        let del = NSMenuItem(title: "删除…", action: #selector(deleteTapped), keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func applyTapped() { onApply?() }
    @objc private func revealTapped() { onReveal?() }
    @objc private func deleteTapped() { onDelete?() }
}

// MARK: - 瀑布流容器

final class GalleryView: NSView {
    var onApply: ((Int) -> Void)?
    var onDelete: ((Int) -> Void)?
    var onReveal: ((Int) -> Void)?

    private var cards: [WallpaperCard] = []
    private var urls: [URL] = []
    private var current = -1
    private var lastWidth: CGFloat = 0
    private var relaying = false

    override var isFlipped: Bool { true }

    /// 把某几张卡的悬停态收掉（keep 为 nil 就是全收）
    func clearHoverState(except keep: WallpaperCard? = nil) {
        for c in cards where c !== keep { c.clearHover() }
    }

    var hoveredCount: Int { cards.filter { $0.isHovering }.count }

    /// 调试用：把前 n 张卡强行置成悬停态
    func debugHover(count: Int) {
        for c in cards.prefix(count) { c.debugSimulateHover() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 从窗口里摘下来时，tracking area 不会再给 mouseExited，
        // 不主动收掉的话卡片会一直停在「已悬停」：名字挂着、视频还在放。
        if window == nil { clearHoverState() }
    }

    // MARK: 数据

    func setItems(_ newURLs: [URL], current: Int) {
        let changed = newURLs.map { $0.path } != urls.map { $0.path }
        urls = newURLs
        self.current = current

        if changed {
            for c in cards {
                c.teardown()
                c.removeFromSuperview()
            }
            cards = newURLs.map { makeCard(for: $0) }
            for c in cards { addSubview(c) }

            for c in cards {
                GalleryThumb.load(for: c.url) { [weak c] image in
                    guard let c, let image else { return }
                    c.setImage(image)
                }
            }
        }

        for (i, c) in cards.enumerated() { c.setCurrent(i == current) }

        let width = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        if width > 0 { lastWidth = width }
        relayout()
    }

    private func makeCard(for url: URL) -> WallpaperCard {
        let info = GalleryThumb.info(for: url)
        let card = WallpaperCard(
            url: url,
            aspect: info.aspect,
            name: url.deletingPathExtension().lastPathComponent,
            meta: metaText(for: url, duration: info.duration))

        card.onApply = { [weak self, weak card] in
            guard let self, let card, let i = self.cards.firstIndex(where: { $0 === card }) else { return }
            self.onApply?(i)
        }
        card.onDelete = { [weak self, weak card] in
            guard let self, let card, let i = self.cards.firstIndex(where: { $0 === card }) else { return }
            self.onDelete?(i)
        }
        card.onReveal = { [weak self, weak card] in
            guard let self, let card, let i = self.cards.firstIndex(where: { $0 === card }) else { return }
            self.onReveal?(i)
        }
        // 同一时刻只允许一张卡在悬停：鼠标移到别处时，把之前那张强行收回
        card.onHoverStart = { [weak self, weak card] in
            self?.clearHoverState(except: card)
        }
        return card
    }

    private func metaText(for url: URL, duration: Double) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let mb = String(format: "%.1f MB", Double(size) / 1_048_576)
        guard duration > 0.5 else { return mb }
        let total = Int(duration.rounded())
        return mb + " · " + String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: 瀑布流排版

    override func layout() {
        super.layout()
        let width = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        if width > 0, abs(width - lastWidth) > 0.5 {
            lastWidth = width
            relayout()
        }
    }

    private func relayout() {
        guard !relaying else { return }
        relaying = true
        defer { relaying = false }

        let width = max(lastWidth, 360)
        let usable = width - Look.inset * 2
        guard usable > 0 else { return }

        // 先按「理想栏宽」定列数，而不是能塞几列就塞几列
        let target: CGFloat = 238
        var cols = max(1, Int(((usable + Look.gap) / (target + Look.gap)).rounded()))
        cols = min(cols, Look.maxCols)
        if !cards.isEmpty { cols = min(cols, cards.count) }

        var colW = (usable - CGFloat(cols - 1) * Look.gap) / CGFloat(cols)
        if colW > Look.maxColW {
            cols = max(1, Int((usable + Look.gap) / (Look.maxColW + Look.gap)))
            colW = (usable - CGFloat(cols - 1) * Look.gap) / CGFloat(cols)
        }

        var heights = [CGFloat](repeating: Look.topInset, count: max(cols, 1))

        for (i, card) in cards.enumerated() {
            let h = colW * heightRatio(for: card, index: i)

            // 挑当前最矮的一列（瀑布流的关键：短边优先）
            var target2 = 0
            for k in 1..<heights.count where heights[k] < heights[target2] - 0.5 { target2 = k }

            let x = Look.inset + CGFloat(target2) * (colW + Look.gap)
            let y = heights[target2]
            card.frame = NSRect(x: x, y: y, width: colW, height: h)
            card.needsLayout = true
            heights[target2] = y + h + Look.gap
        }

        var total = (heights.max() ?? Look.topInset) + Look.bottomInset
        if cards.isEmpty { total = 0 }
        let visible = enclosingScrollView?.contentView.bounds.height ?? total
        setFrameSize(NSSize(width: width, height: max(total, visible)))

        if ProcessInfo.processInfo.environment["VW_GALLERY_DEBUG"] != nil {
            var lines: [String] = []
            lines.append("[gallery] width=\(Int(width)) cols=\(cols) colW=\(Int(colW)) total=\(Int(total)) cards=\(cards.count)")
            for (i, c) in cards.enumerated() {
                lines.append("  #\(i) x=\(Int(c.frame.minX)) y=\(Int(c.frame.minY)) w=\(Int(c.frame.width)) h=\(Int(c.frame.height)) aspect=\(String(format: "%.2f", c.aspect))")
            }
            try? lines.joined(separator: "\n").write(
                toFile: "/tmp/vw-gallery.txt", atomically: true, encoding: .utf8)
        }
    }

    /// 卡片高度（相对于栏宽的倍数）。
    /// 我们的视频大多被转成同一个屏幕比例，纯按原比例排会变成整齐格子，
    /// 所以按文件名给一个稳定的"节奏"值，再做适度裁切，才有瀑布流的疏密。
    private func heightRatio(for card: WallpaperCard, index: Int) -> CGFloat {
        let a = max(card.aspect, 0.3)
        let natural = 1 / a
        let pattern: [CGFloat]
        if a < 0.92 {
            pattern = [1.42, 1.18, 1.55, 1.30, 1.24, 1.46]
        } else if a < 1.25 {
            pattern = [0.96, 1.12, 0.86, 1.04, 0.90, 1.20]
        } else {
            pattern = [0.68, 0.80, 0.63, 0.86, 0.72, 0.76]
        }
        let pick = pattern[stableHash(card.url.lastPathComponent) % pattern.count]
        // 别把超宽 / 超高的片子裁得太狠
        let lo = max(natural * 0.84, 0.56)
        let hi = min(natural * 1.36, 1.72)
        return min(max(pick, lo), hi)
    }

    private func stableHash(_ s: String) -> Int {
        var h = 7
        for u in s.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x0fff_ffff }
        return h
    }
}

// MARK: - 顶部链接输入框（一直露着，不用先点一次）

// MARK: - 液态玻璃底

/// 液态玻璃：`withinWindow` 的真背景模糊（底下滚动的缩略图会被"喝"进来），
/// 叠一层薄涂层控透明度，再加一圈上亮下暗的细边和顶部高光。
/// 底座的透明度只由 tintAlpha 决定，跟里面按钮各算各的，互不影响。
///
/// `floating` 让整块"浮"起来：模糊内容放在内层裁剪，圆角阴影画在外层，
/// 这样有阴影也不会被 `masksToBounds` 切掉。
final class GlassView: NSView {
    /// 亮玻璃（浅色底盘）／暗玻璃（近黑悬浮底）／清水玻璃（几乎没有底色，只留一层薄雾和反光）
    enum Chrome { case light, dark, clear }

    private let clip = NSView()
    private let blur = NSVisualEffectView()
    private let tintView = NSView()
    private let glowView = NSView()
    private let tintLayer = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    let radius: CGFloat
    private let chrome: Chrome
    private var tintAlpha: CGFloat = 0
    private var tintColor: NSColor = .white

    init(radius: CGFloat, tint: CGFloat,
         material: NSVisualEffectView.Material = .popover,
         chrome: Chrome = .light,
         floating: Bool = false) {
        self.radius = radius
        self.chrome = chrome
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false

        if floating {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.16
            layer?.shadowRadius = 18
            layer?.shadowOffset = CGSize(width: 0, height: -6)
        }

        clip.wantsLayer = true
        clip.layer?.cornerRadius = radius
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = 1
        clip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clip)

        switch chrome {
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
            tintColor = .black
            clip.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        case .light:
            clip.layer?.borderColor = NSColor.white.withAlphaComponent(0.52).cgColor
        case .clear:
            tintColor = .white
            clip.layer?.borderColor = NSColor.white.withAlphaComponent(0.34).cgColor
        }

        blur.material = material
        blur.blendingMode = .withinWindow
        blur.state = .active
        if chrome == .dark { blur.appearance = NSAppearance(named: .darkAqua) }
        blur.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(blur)

        tintLayer.startPoint = CGPoint(x: 0.5, y: 1)
        tintLayer.endPoint = CGPoint(x: 0.5, y: 0)
        tintView.wantsLayer = true
        tintView.layer?.addSublayer(tintLayer)
        tintView.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(tintView)

        glowLayer.startPoint = CGPoint(x: 0.5, y: 1)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 0)
        let glowA: CGFloat
        switch chrome {
        case .dark: glowA = 0.10
        case .light: glowA = 0.34
        case .clear: glowA = 0.30
        }
        glowLayer.colors = [NSColor.white.withAlphaComponent(glowA).cgColor,
                            NSColor.white.withAlphaComponent(0).cgColor]
        glowView.wantsLayer = true
        glowView.layer?.addSublayer(glowLayer)
        glowView.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(glowView)

        NSLayoutConstraint.activate([
            clip.leadingAnchor.constraint(equalTo: leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor),
            clip.topAnchor.constraint(equalTo: topAnchor),
            clip.bottomAnchor.constraint(equalTo: bottomAnchor),

            blur.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            blur.topAnchor.constraint(equalTo: clip.topAnchor),
            blur.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: clip.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            glowView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            glowView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            glowView.topAnchor.constraint(equalTo: clip.topAnchor),
            glowView.heightAnchor.constraint(equalToConstant: 13),
        ])

        setTint(tint)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 0 = 全透（只留模糊），1 = 一片实色
    func setTint(_ a: CGFloat) {
        tintAlpha = a
        rebuildTint()
    }

    /// 单独调描边浓淡：小磁贴不需要那么明显的白边
    func setBorder(_ a: CGFloat, color: NSColor = .white) {
        clip.layer?.borderColor = color.withAlphaComponent(a).cgColor
    }

    /// 开着的开关用主题色染一下玻璃，跟"没开"的一眼区分
    func setColor(_ c: NSColor) {
        tintColor = c
        rebuildTint()
    }

    private func rebuildTint() {
        // 清水玻璃的渐变要更平，不然中间会出现一道可见的分界
        let spread: CGFloat = chrome == .clear ? 0.07 : 0.13
        let top = min(1, tintAlpha + spread)
        let bottom = max(0, tintAlpha - spread * 0.7)
        tintLayer.colors = [tintColor.withAlphaComponent(bottom).cgColor,
                            tintColor.withAlphaComponent(top).cgColor]
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = tintView.bounds
        glowLayer.frame = glowView.bounds
        if layer?.shadowOpacity ?? 0 > 0 {
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius,
                                       cornerHeight: radius, transform: nil)
        }
        CATransaction.commit()
    }
}

final class LinkField: NSView, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?
    private let field = NSTextField()
    private let glass = GlassView(radius: 15, tint: 0.05, material: .popover, chrome: .clear)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        // 输入框不再叠一层白胶囊，改成极淡的"内凹"一层，跟底座拉开但不抢眼
        glass.setColor(.labelColor)
        glass.setBorder(0.13, color: .labelColor)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        icon.contentTintColor = NSColor.labelColor.withAlphaComponent(0.38)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 11)
        field.textColor = .labelColor
        field.placeholderString = idlePlaceholder
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 12),

            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        // 底子是 GlassView 画的，这里留空
    }

    func focus() {
        window?.makeFirstResponder(field)
    }

    var text: String { field.stringValue }

    func clear() {
        field.stringValue = ""
        window?.makeFirstResponder(nil)
    }

    private let idlePlaceholder = "粘贴视频链接，回车开始下载"
    private var noticeWork: DispatchWorkItem?

    /// 输入不像链接时就地提示一句，不用弹窗口
    func notice(_ msg: String) {
        noticeWork?.cancel()
        field.placeholderString = msg
        NSSound.beep()
        let work = DispatchWorkItem { [weak self] in
            self?.field.placeholderString = self?.idlePlaceholder ?? ""
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    override func mouseDown(with event: NSEvent) { focus() }

    // MARK: 粘贴

    /// 这是个没有菜单栏的后台程序，⌘V 没人处理，所以自己接住
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
            if let ed = field.currentEditor() as? NSTextView {
                ed.copy(nil)
                return true
            }
        case "x":
            if let ed = field.currentEditor() as? NSTextView {
                ed.cut(nil)
                return true
            }
        default:
            break
        }
        return super.performKeyEquivalent(with: event)
    }

    func pasteLink() {
        let board = NSPasteboard.general
        var raw = board.string(forType: .string)
        if raw == nil || raw?.isEmpty == true {
            raw = board.string(forType: .URL)
        }
        guard let letters = raw, !letters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            notice("剪贴板里没有可粘贴的链接")
            return
        }
        let text = Self.extractLink(letters)

        if let ed = field.currentEditor() as? NSTextView {
            let full = NSRange(location: 0, length: (ed.string as NSString).length)
            ed.insertText(text, replacementRange: full)
        } else {
            field.stringValue = text
        }
        needDisplayPlaceholderReset()
    }

    /// 平台复制出来的多是「标题 + 链接」，只留里面那条链接。
    /// 实现统一放在 Downloader 里，别处（面板、菜单）共用一份，避免两套判定分叉。
    static func extractLink(_ raw: String) -> String {
        Downloader.extractLink(raw)
    }

    private func needDisplayPlaceholderReset() {
        // 粘进来的内容如果不像链接，提示一下，但仍留在框里让人改
        let v = field.stringValue
        if !v.isEmpty, !Downloader.looksLikeLink(v) {
            field.placeholderString = "粘贴视频链接，回车开始下载"
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { NSSound.beep(); return true }
            onSubmit?(text)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    /// 只是防止贴进超长文本，判定交给回车
    func controlTextDidChange(_ obj: Notification) {
        let v = field.stringValue
        if v.count > 400 { field.stringValue = String(v.prefix(400)) }
    }
}

// MARK: - 底部程序坞上的方形磁贴

/// 程序坞风格：一个个圆角方形磁贴，只放图标；鼠标悬停时由外面弹出名字气泡。
final class SettingPill: NSView {
    private(set) var title: String
    private var symbol: String
    private(set) var isOn: Bool
    /// 纯动作按钮（比如「打开文件夹」）：没有开关状态，点了就执行
    private let isAction: Bool
    /// 开关型磁贴可以按状态换图标（「动态 / 静态」）
    var onText: String?
    var offText: String?
    var onSymbol: String?
    var offSymbol: String?
    var onToggle: ((Bool) -> Void)?
    var onTap: (() -> Void)?
    /// 悬停时通知外面弹/收名字气泡
    var onHoverChange: ((Bool) -> Void)?

    static let side: CGFloat = 30

    private let glass = GlassView(radius: 9, tint: 0.04, material: .popover, chrome: .clear)
    private let iconView = NSImageView()
    private var hovered = false { didSet { restyle() } }
    private var tracking: NSTrackingArea?

    init(title: String, symbol: String, on: Bool) {
        self.title = title
        self.symbol = symbol
        self.isOn = on
        self.isAction = false
        super.init(frame: .zero)
        setup()
    }

    /// 同款外形，不带状态
    init(actionTitle: String, symbol: String) {
        self.title = actionTitle
        self.symbol = symbol
        self.isOn = false
        self.isAction = true
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        iconView.imageScaling = .scaleNone
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),

            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        restyle()
    }

    func setOn(_ on: Bool) {
        guard !isAction, on != isOn else { return }
        isOn = on
        restyle()
    }

    /// 气泡里显示的名字（开关型跟着状态走：动态 / 静态）
    var tipText: String { isAction ? title : shownText }

    private var shownText: String {
        guard !isAction else { return title }
        return isOn ? (onText ?? title) : (offText ?? title)
    }

    private var shownSymbol: String {
        guard !isAction else { return symbol }
        return isOn ? (onSymbol ?? symbol) : (offSymbol ?? symbol)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    private func restyle() {
        // 全透明悬浮：底色几乎看不见，靠图标本身表达状态
        //   开着 → 主题色图标 + 一层很淡的主题色雾
        //   关着 → 灰图标，什么都没有
        //   动作键 → 灰图标，悬停才浮现一层淡雾
        let ink: NSColor
        if isOn && !isAction {
            ink = Brand.accent
        } else {
            ink = NSColor.labelColor.withAlphaComponent(hovered ? 0.92 : 0.58)
        }

        if let base = NSImage(systemSymbolName: shownSymbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
            iconView.image = base.withSymbolConfiguration(cfg) ?? base
        }

        if isOn && !isAction {
            glass.setColor(Brand.accent)
            glass.setTint(hovered ? 0.22 : 0.15)
        } else {
            glass.setColor(.labelColor)
            glass.setTint(hovered ? 0.10 : 0.03)
        }
        glass.setBorder(hovered ? 0.22 : 0.0)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        onHoverChange?(false)
    }

    /// 外部清场（窗口收起、失焦）
    func clearHover() {
        guard hovered else { return }
        hovered = false
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if isAction {
            onTap?()
            return
        }
        isOn.toggle()
        restyle()
        onHoverChange?(hovered)
        onToggle?(isOn)
    }
}

// MARK: - 程序坞上方那枚名字气泡

/// 鼠标压在磁贴上时浮出来的小标签，位置照着系统程序坞的标签做。
final class DockTip: NSView {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        translatesAutoresizingMaskIntoConstraints = true
        isHidden = true

        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// target 是磁贴在父视图坐标系里的位置
    func show(text: String, above target: NSRect, in host: NSView) {
        label.stringValue = text
        let w = max(30, ceil(label.intrinsicContentSize.width) + 20)
        let h: CGFloat = 19
        var x = target.midX - w / 2
        x = min(max(4, x), max(4, host.bounds.width - w - 4))
        let y = target.maxY + 6
        frame = NSRect(x: x.rounded(), y: y.rounded(), width: w, height: h)
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}

// MARK: - 底部浮动状态胶囊

final class StatusPill: NSView {
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var heightC: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0

        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small
        bar.isHidden = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 5),
            bar.heightAnchor.constraint(equalToConstant: 3),
        ])

        heightC = heightAnchor.constraint(equalToConstant: 32)
        heightC.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(text: String, progress: Double, busy: Bool) {
        label.stringValue = text
        bar.isHidden = !busy
        bar.doubleValue = progress
        heightC.constant = busy ? 46 : 32
        if alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0
        }
    }
}

// MARK: - 接收拖拽的外壳

/// 窗口外壳：一块透明玻璃。
/// 不做背景模糊（原来 `NSVisualEffectView` 的材质会把桌面糊成一片奶白），
/// 只上一层极淡的白渐变 + 一圈细边，桌面从底下透上来，缩略图才像"浮"在桌面上的。
final class ShellView: NSView {
    static let radius: CGFloat = 16

    var onDrop: (([URL]) -> Void)?
    var onDragStateChange: ((Bool) -> Void)?
    private var accepts = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        registerForDraggedTypes([.fileURL])
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: Self.radius, yRadius: Self.radius)
        let top = NSColor.white.withAlphaComponent(0.20)
        let bottom = NSColor.white.withAlphaComponent(0.05)
        if let g = NSGradient(starting: bottom, ending: top) {
            g.draw(in: path, angle: 90)
        } else {
            top.setFill()
            path.fill()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func videoURLs(from pasteboard: NSPasteboard) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]
        else { return [] }
        let exts: Set<String> = ["mp4", "mov", "m4v"]
        var out: [URL] = []
        for u in items {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let inner = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
                out += inner.filter { exts.contains($0.pathExtension.lowercased()) }
            } else if exts.contains(u.pathExtension.lowercased()) {
                out.append(u)
            }
        }
        return out
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts = !Self.videoURLs(from: sender.draggingPasteboard).isEmpty
        onDragStateChange?(accepts)
        return accepts ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        accepts = false
        onDragStateChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = Self.videoURLs(from: sender.draggingPasteboard)
        accepts = false
        onDragStateChange?(false)
        guard !files.isEmpty else { return false }
        onDrop?(files)
        return true
    }
}

/// 拖拽时浮在最上面的提示层（不吃鼠标事件）
final class DropOverlay: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0
        isHidden = true

        layer?.cornerRadius = 18
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 30, weight: .light))
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(labelWithString: "松开，收进壁纸库")
        text.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        text.textColor = .white
        text.alignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false

        let sub = NSTextField(labelWithString: "会自动去跳帧、按屏幕裁切、做成无缝循环")
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = NSColor.white.withAlphaComponent(0.65)
        sub.alignment = .center
        sub.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, text, sub])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setVisible(_ on: Bool) {
        if on { isHidden = false }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = on ? 1 : 0
        } completionHandler: { [weak self] in
            if !on { self?.isHidden = true }
        }
    }
}

/// 自己画的细滚动条：4pt 宽的小圆条，只在滚动时浮出来，停下就淡掉。
/// 系统那条太粗、还带滑轨，会把右侧内容挤出一条很宽的灰带。
final class ThinScrollerKnob: NSView {
    static let width: CGFloat = 4
    /// 离窗口右沿的距离
    static let inset: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.width / 2
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.26).cgColor
        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 不吃鼠标事件，免得挡住缩略图的点击
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 窗口缩放时立刻通知瀑布流重排（documentView 自身宽度不变，等不到 layout）
final class GalleryScrollView: NSScrollView {
    var onResize: (() -> Void)?
    var onScroll: (() -> Void)?

    private let knob = ThinScrollerKnob()
    private var fadeWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(knob)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
        layoutKnob()
    }

    override func layout() {
        super.layout()
        layoutKnob()
    }

    // 滚动时鼠标没动，卡片下面的内容换了，得主动把悬停态收掉
    override func scrollWheel(with event: NSEvent) {
        onScroll?()
        super.scrollWheel(with: event)
        layoutKnob()
        flashKnob()
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        onScroll?()
        layoutKnob()
        flashKnob()
    }

    /// 调试：滚到某个位置并把细条固定显示出来，方便截图核对
    func debugShowKnob(offset: CGFloat) {
        contentView.scroll(to: NSPoint(x: 0, y: offset))
        reflectScrolledClipView(contentView)
        fadeWork?.cancel()
        knob.isHidden = false
        knob.alphaValue = 1
        layoutKnob()
    }

    func layoutKnob() {
        let trackH = bounds.height
        let viewH = contentView.bounds.height
        let totalH = documentView?.frame.height ?? 0
        guard trackH > 1, totalH > viewH + 2 else {
            knob.isHidden = true
            return
        }
        let h = max(34, trackH * max(0.06, viewH / totalH))
        let maxOffset = totalH - viewH
        let offset = min(max(0, contentView.bounds.origin.y), maxOffset)
        let progress = maxOffset > 0 ? offset / maxOffset : 0
        let top = progress * (trackH - h)
        // NSScrollView 没翻转，y 从下往上算
        let x = bounds.width - ThinScrollerKnob.inset - ThinScrollerKnob.width
        knob.frame = NSRect(x: x, y: trackH - top - h,
                            width: ThinScrollerKnob.width, height: h)
    }

    /// 滚动时浮出来，停手 0.8 秒后淡掉
    private func flashKnob() {
        guard !knob.isHidden else { return }
        fadeWork?.cancel()
        if knob.alphaValue < 1 {
            knob.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                knob.animator().alphaValue = 1
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                self.knob.animator().alphaValue = 0
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}

// MARK: - 窗口

final class LibraryWindowController: NSWindowController {

    private weak var delegate: WallpaperLibraryDelegate?
    private let gallery = GalleryView()
    private var scroll: GalleryScrollView!
    private var emptyView: NSView!
    private var pill: StatusPill!
    private var overlay: DropOverlay!
    private var dropTarget: ShellView!
    private weak var shell: NSView?
    private var dockTip: DockTip?

    init(delegate: WallpaperLibraryDelegate) {
        self.delegate = delegate
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 730),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        win.title = "壁纸库"
        win.minSize = NSSize(width: 720, height: 460)
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.isReleasedWhenClosed = false
        super.init(window: win)
        buildUI()
        let restored = win.setFrameUsingName("VWLibraryWindow")
        win.setFrameAutosaveName("VWLibraryWindow")
        if !restored { win.center() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: 组装

    private func buildUI() {
        guard let win = window else { return }

        let shell = ShellView(frame: NSRect(x: 0, y: 0, width: 1060, height: 730))
        dropTarget = shell
        win.contentView = shell

        shell.onDrop = { [weak self] urls in self?.delegate?.libraryAdd(urls: urls) }
        shell.onDragStateChange = { [weak self] on in self?.overlay.setVisible(on) }

        // 链接框：挪到左下角，悬浮在瀑布流上方（底下的缩略图会从玻璃里透出来）
        let linkField = LinkField()
        linkField.onSubmit = { [weak self] text in
            guard let self else { return }
            guard Downloader.looksLikeLink(text) else {
                self.linkField?.notice("这不像是一条视频链接，检查一下再试")
                return
            }
            self.linkField?.clear()
            self.delegate?.libraryImportLink(text)
        }
        self.linkField = linkField

        // 底座：一条几乎看不见底的清水玻璃，只借模糊和一缕反光"托"住里面的东西。
        // floating 让它整块抬起，底下带一层柔和的投影，卡片从阴影里穿过去。
        let bar = GlassView(radius: 22, tint: 0.07, material: .popover,
                            chrome: .clear, floating: true)

        let enabledPill = SettingPill(title: "动态", symbol: "play.fill", on: true)
        enabledPill.onText = "动态"
        enabledPill.offText = "静态"
        enabledPill.onSymbol = "play.fill"
        enabledPill.offSymbol = "pause.fill"
        let lockPill = SettingPill(title: "锁屏跟随", symbol: "lock.fill", on: true)
        let autoPill = SettingPill(title: "开机自启", symbol: "power", on: false)
        enabledPill.onToggle = { [weak self] on in
            self?.delegate?.librarySetEnabled(on)
            self?.syncSettings()
        }
        lockPill.onToggle = { [weak self] on in
            self?.delegate?.librarySetLockSync(on)
            self?.syncSettings()
        }
        autoPill.onToggle = { [weak self] on in
            self?.delegate?.librarySetAutostart(on)
            self?.syncSettings()
        }
        self.enabledPill = enabledPill
        self.lockPill = lockPill
        self.autoPill = autoPill

        // 名字气泡：跟系统程序坞一样，鼠标压上去才浮出来
        let tip = DockTip()
        dockTip = tip

        // 打开文件夹：同款胶囊，但不是开关，跟开关之间用一条细线隔开
        let folderPill = SettingPill(actionTitle: "打开文件夹", symbol: "folder")
        folderPill.onTap = { [weak self] in self?.delegate?.libraryRevealFolder() }

        for p in [enabledPill, lockPill, autoPill, folderPill] {
            p.onHoverChange = { [weak self, weak p] on in
                guard let self, let p else { return }
                on ? self.showTip(for: p) : self.dockTip?.hide()
            }
        }

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.13).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let pills = NSStackView(views: [enabledPill, lockPill, autoPill, divider, folderPill])
        pills.orientation = .horizontal
        pills.spacing = 6
        pills.alignment = .centerY
        pills.setCustomSpacing(10, after: autoPill)
        pills.setCustomSpacing(10, after: divider)
        pills.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(pills)

        // 瀑布流
        let scroller = GalleryScrollView()
        scroll = scroller
        scroll.documentView = gallery
        // 不要系统滚动条（太粗、带滑轨、还会挤压右侧内容），改成自己画的 4pt 细条
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .allowed
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroller.onResize = { [weak self] in
            guard let self else { return }
            self.gallery.needsLayout = true
        }
        scroller.onScroll = { [weak self] in self?.gallery.clearHoverState() }

        gallery.onApply = { [weak self] i in self?.delegate?.libraryApply(index: i) }
        gallery.onDelete = { [weak self] i in self?.delegate?.libraryDelete(index: i) }
        gallery.onReveal = { [weak self] i in
            guard let self, let urls = self.delegate?.libraryVideos(), i < urls.count else { return }
            NSWorkspace.shared.activateFileViewerSelecting([urls[i]])
        }

        emptyView = makeEmptyView()

        pill = StatusPill()
        overlay = DropOverlay()

        shell.addSubview(scroll)
        shell.addSubview(bar)
        shell.addSubview(linkField)
        shell.addSubview(emptyView)
        shell.addSubview(pill)
        shell.addSubview(tip)
        shell.addSubview(overlay)
        self.shell = shell

        // 链接框的"理想"宽度：窗口够宽就按 320 走，窗口窄了自己缩，不挤坏右边的开关
        let linkPref = linkField.widthAnchor.constraint(equalToConstant: 320)
        linkPref.priority = .defaultHigh
        linkPref.isActive = true

        NSLayoutConstraint.activate([
            // 底座：跟卡片左右边缘对齐（Look.inset 同一数值），半透明，卡片从它下面穿过去
            bar.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: Look.barInset),
            bar.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -Look.barInset),
            bar.bottomAnchor.constraint(equalTo: shell.bottomAnchor, constant: -Look.barInset),
            bar.heightAnchor.constraint(equalToConstant: Look.barHeight),

            // 链接框：底座里头靠左，高度跟着条走，宽度可缩
            linkField.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 9),
            linkField.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            linkField.heightAnchor.constraint(equalToConstant: 30),
            linkField.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            linkField.widthAnchor.constraint(lessThanOrEqualToConstant: 330),

            // 开关组：贴右边，跟链接框之间留一点空
            pills.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -9),
            pills.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            pills.leadingAnchor.constraint(greaterThanOrEqualTo: linkField.trailingAnchor, constant: 12),

            // 瀑布流铺满整窗，卡片会从底座底下滚过去（玻璃是靠这个"活"起来的）
            scroll.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: shell.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: shell.bottomAnchor),

            emptyView.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -26),
            emptyView.widthAnchor.constraint(equalToConstant: 340),

            // 处理进度挪到右上角（原来那行提示的位置），不跟底部控件抢地方
            pill.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -22),
            pill.topAnchor.constraint(equalTo: shell.topAnchor, constant: 52),
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: 460),

            overlay.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 10),
            overlay.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -10),
            overlay.topAnchor.constraint(equalTo: shell.topAnchor, constant: 10),
            overlay.bottomAnchor.constraint(equalTo: shell.bottomAnchor, constant: -10),
        ])

        // 窗口拉伸时重排瀑布流
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResized),
            name: NSWindow.didResizeNotification, object: win)

        // 窗口收起、失焦、被遮住、App 退到后台：一律把悬停态清掉
        for name in [NSWindow.willCloseNotification,
                     NSWindow.didResignKeyNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowLostAttention(_:)), name: name, object: win)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification, object: nil)

        reload()
    }

    private var linkField: LinkField?
    private var enabledPill: SettingPill?
    private var lockPill: SettingPill?
    private var autoPill: SettingPill?
    private var hoverTestStarted = false
    /// 提示的自动收起计时器（换新内容时作废重排）
    private var busyHideWork: DispatchWorkItem?

    /// 三个开关的显示状态永远以 App 侧为准
    private func syncSettings() {
        guard let delegate else { return }
        enabledPill?.setOn(delegate.libraryIsEnabled())
        lockPill?.setOn(delegate.libraryIsLockSync())
        autoPill?.setOn(delegate.libraryIsAutostart())
    }

    private func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) {
            return f
        }
        return base
    }

    private func makeEmptyView() -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "rectangle.stack.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 40, weight: .ultraLight))
        icon.contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "把视频拖到这里")
        title.font = roundedFont(19, .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let sub = NSTextField(labelWithString: "会自动去跳帧、按屏幕比例裁切、做成无缝循环，\n然后收进壁纸库，点一下就能换上")
        sub.font = .systemFont(ofSize: 11.5)
        sub.textColor = .tertiaryLabelColor
        sub.alignment = .center
        sub.maximumNumberOfLines = 2
        sub.translatesAutoresizingMaskIntoConstraints = false

        let pick = NSButton(title: "或者选一个文件…", target: self, action: #selector(pickFiles))
        pick.bezelStyle = .rounded
        pick.controlSize = .small
        pick.font = .systemFont(ofSize: 11.5)
        pick.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, title, sub, pick])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 9
        stack.setCustomSpacing(14, after: sub)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    // MARK: 刷新

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // 关窗时鼠标可能正压在某张卡上（收不到 mouseExited），开窗先统一归零，
        // 免得一进来就有卡片挂着名字、还在后台放视频
        gallery.clearHoverState()
        // 进来就能直接打字，不用先点一次输入框
        DispatchQueue.main.async { [weak self] in self?.linkField?.focus() }
        // 调试：把粘贴板塞进指定内容后走一遍粘贴，输出结果
        if let raw = ProcessInfo.processInfo.environment["VW_TEST_PASTE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(raw, forType: .string)
                self.linkField?.pasteLink()
                let got = self.linkField?.text ?? ""
                let out = "in=\(raw)\nout=\(got)\n"
                try? out.write(toFile: "/tmp/vw-paste.txt", atomically: true, encoding: .utf8)
                exit(0)
            }
        }
        // 调试：模拟一条失败提示，看它会不会自己收（VW_NOTIFY_TEST=1）
        if ProcessInfo.processInfo.environment["VW_NOTIFY_TEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.setBusy(false, progress: 0,
                             text: "「叶罗丽放下剧本佛在救你.mp4」处理失败：视频处理失败（源文件可能不受支持）")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    print("[notify] 出现后 alpha=\(self.pill?.alphaValue ?? -1)")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
                print("[notify] 9.5 秒后 alpha=\(self.pill?.alphaValue ?? -1)")
                exit(0)
            }
        }
        // 调试：模拟处理进度
        if ProcessInfo.processInfo.environment["VW_SIMULATE_BUSY"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.setBusy(true, progress: 0.42, text: "正在优化 08-水墨对决-王不见王.mp4（42%）")
            }
        }
        // 调试：强制几张卡进入悬停态 → 截图 → 模拟「关窗/失焦」清掉 → 再截图
        if let raw = ProcessInfo.processInfo.environment["VW_HOVER_TEST"], !hoverTestStarted {
            hoverTestStarted = true
            let n = max(1, Int(raw) ?? 3)
            let base = ProcessInfo.processInfo.environment["VW_HOVER_SHOT"] ?? "/tmp/vw-hover"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                self.gallery.debugHover(count: n)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    print("[hover] 强制悬停 \(n) 张 → 实际悬停数=\(self.gallery.hoveredCount)")
                    self.snapshot(to: base + "-on.png")
                    // 走真实路径：关窗 → 再开窗，看悬停态有没有被带回来
                    self.window?.performClose(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        print("[hover] 关窗后 → 实际悬停数=\(self.gallery.hoveredCount)")
                        self.showWindow(nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            print("[hover] 重新开窗后 → 实际悬停数=\(self.gallery.hoveredCount)")
                            self.snapshot(to: base + "-off.png")
                            exit(0)
                        }
                    }
                }
            }
        }
        // 调试：把某枚磁贴的名字气泡显示出来截图（没屏幕录制权限时核对位置用）
        if let which = ProcessInfo.processInfo.environment["VW_TIP_SHOT"],
           let path = ProcessInfo.processInfo.environment["VW_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                let pill: SettingPill? = which == "folder" ? nil : self.lockPill
                if let pill { self.showTip(for: pill) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.snapshot(to: path)
                    exit(0)
                }
            }
        }
        // 调试：把细滚动条固定显示出来截图（核对宽度 / 位置）
        if ProcessInfo.processInfo.environment["VW_KNOB_TEST"] != nil,
           let path = ProcessInfo.processInfo.environment["VW_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let total = self.scroll.documentView?.frame.height ?? 0
                let viewH = self.scroll.contentView.bounds.height
                self.scroll.debugShowKnob(offset: (total - viewH) * 0.45)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.snapshot(to: path)
                    print("[knob] total=\(Int(total)) viewH=\(Int(viewH))")
                    exit(0)
                }
            }
        }
        // 调试：把窗口内容画成图片后退出（沙盒没有屏幕录制权限时也能看效果）
        if let path = ProcessInfo.processInfo.environment["VW_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                self.snapshot(to: path)
                exit(0)
            }
        }
        // 调试：打印瀑布流排版后退出（无屏幕录制权限时核对布局用）
        if ProcessInfo.processInfo.environment["VW_GALLERY_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                self.gallery.needsLayout = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let visible = self.scroll.documentVisibleRect
                    let extra = "\n[window] \(Int(self.window?.frame.width ?? 0))x\(Int(self.window?.frame.height ?? 0)) clip=\(Int(self.scroll.contentView.bounds.width))x\(Int(self.scroll.contentView.bounds.height)) visibleY=\(Int(visible.maxY))"
                    if let s = try? String(contentsOfFile: "/tmp/vw-gallery.txt", encoding: .utf8) {
                        try? (s + extra).write(toFile: "/tmp/vw-gallery.txt", atomically: true, encoding: .utf8)
                    }
                    exit(0)
                }
            }
        }
    }

    private func snapshot(to path: String) {
        guard let window, let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        // 滚动区自己再来一张：整窗快照取不到 clip 里的内容
        if let grepp = gallery.bitmapImageRepForCachingDisplay(in: gallery.bounds) {
            gallery.cacheDisplay(in: gallery.bounds, to: grepp)
            if let d = grepp.representation(using: .png, properties: [:]),
               let gpath = URL(string: path)?.deletingPathExtension().path {
                try? d.write(to: URL(fileURLWithPath: gpath + "-gallery.png"))
            }
        }
        var lines: [String] = []
        for sub in gallery.subviews {
            guard let c = sub as? WallpaperCard else { continue }
            lines.append(c.debugLine)
        }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/vw-cards.txt", atomically: true, encoding: .utf8)

        // 调试：把底部那条栏的实际坐标打出来，核对链接框 / 开关组的宽度
        var frames: [String] = ["content \(Int(view.bounds.width))x\(Int(view.bounds.height))"]
        func dump(_ v: NSView, _ indent: String) {
            if v is WallpaperCard { return }
            frames.append("\(indent)\(type(of: v)) x=\(Int(v.frame.minX)) y=\(Int(v.frame.minY)) w=\(Int(v.frame.width)) h=\(Int(v.frame.height))")
            for inner in v.subviews { dump(inner, indent + "  ") }
        }
        for sub in view.subviews where sub !== gallery { dump(sub, "") }
        try? frames.joined(separator: "\n").write(toFile: "/tmp/vw-frames.txt", atomically: true, encoding: .utf8)
    }

    func reload() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.reload() }
            return
        }
        guard let delegate else { return }
        let videos = delegate.libraryVideos()
        gallery.setItems(videos, current: delegate.libraryCurrentIndex())
        emptyView.isHidden = !videos.isEmpty
        scroll.isHidden = videos.isEmpty
        syncSettings()
    }

    func setBusy(_ busy: Bool, progress: Double = 0, text: String = "") {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.setBusy(busy, progress: progress, text: text) }
            return
        }
        // 每来一条新状态就把上一条的自动收起计划取消，不然旧计时器会把新提示提前收掉
        busyHideWork?.cancel()
        busyHideWork = nil

        guard let pill else { return }
        if !busy && text.isEmpty {
            pill.hide()
            return
        }
        pill.show(text: text.isEmpty ? (busy ? "处理中…" : "") : text,
                  progress: progress, busy: busy)

        // 处理中不自动收；一旦是"结案陈词"（成功 / 失败），过几秒自己收起来
        guard !busy else { return }
        let isTrouble = text.contains("失败") || text.contains("无法") || text.contains("找不到")
        let delay: TimeInterval = isTrouble ? 7.0 : 3.6
        let work = DispatchWorkItem { [weak self] in
            self?.busyHideWork = nil
            self?.setBusy(false, progress: 0, text: "")
        }
        busyHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @objc private func windowResized() {
        gallery.needsLayout = true
        dockTip?.hide()
    }

    @objc private func windowLostAttention(_ note: Notification) {
        // 被遮住时 occlusionState 里已经没有 .visible，其它事件直接清
        if note.name == NSWindow.didChangeOcclusionStateNotification,
           let w = note.object as? NSWindow, w.occlusionState.contains(.visible) {
            return
        }
        gallery.clearHoverState()
        dockTip?.hide()
        enabledPill?.clearHover()
        lockPill?.clearHover()
        autoPill?.clearHover()
    }

    @objc private func appResignedActive() {
        gallery.clearHoverState()
        dockTip?.hide()
    }

    /// 磁贴上方浮一块名字气泡（位置照程序坞标签来）
    private func showTip(for pill: SettingPill) {
        guard let shell, let tip = dockTip else { return }
        let r = pill.convert(pill.bounds, to: shell)
        tip.show(text: pill.tipText, above: r, in: shell)
    }

    // MARK: 动作

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "选择要当壁纸的视频（可多选）"
        if panel.runModal() == .OK {
            delegate?.libraryAdd(urls: panel.urls)
        }
    }
}
