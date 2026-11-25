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
    /// 壁纸库内长按拖动重排：from/to 都是「移除源之后的插入位置」
    func libraryMove(from: Int, to: Int)
    /// 重命名第 index 张壁纸（只改文件名主体，扩展名由 App 侧保留）。
    /// 返回 false 表示名字不合法 / 重名 / 写入失败，卡片会留在编辑态让用户改。
    func libraryRename(index: Int, to name: String) -> Bool
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
    /// 锁屏动态播放（需要用户在系统设置里选一次壁纸）
    func librarySetDynamicLock(_ on: Bool)
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
        // 网页壁纸没有视频轨可读，直接给固定值，别拿 dongweb:// 去碰 AVURLAsset
        if !url.isFileURL {
            let info = Info(aspect: 16.0 / 9.0, duration: 0, pixel: "网页", fps: 0)
            infoCache[url.path] = info
            return info
        }
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
        // 网页壁纸：统一地球图标
        if !video.isFileURL { return WebThumb.icon() }
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
        // 网页壁纸：统一地球图标（同步给，没得抽帧）
        if !video.isFileURL { completion(WebThumb.icon()); return }
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

    /// 改名后清掉旧路径的内存缓存（磁盘上的 jpg 由调用方一起搬走）
    static func forget(_ video: URL) {
        let key = video.path
        cacheLock.lock()
        memory[key] = nil
        infoCache[key] = nil
        cacheLock.unlock()
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
    /// 右下角微调按钮：点了就只调这一张
    var onTune: (() -> Void)?
    /// 长按拖动重排：事件坐标都给外面，卡片只负责「什么时候开始 / 跟手移动 / 结束」
    var onDragBegin: (() -> Void)?
    var onDragMove: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private let thumbWrap = NSView()
    private let media = MediaView()
    private let shade = GradientView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private let tuneButton = NSButton()
    private let renameButton = NSButton()
    private let renameField = NSTextField()
    private var renaming = false
    /// 提交新名字：返回 true 表示改名成功，false 就留在编辑态
    var onCommitRename: ((String) -> Bool)?
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "正在使用")

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var tracking: NSTrackingArea?
    private var hovered = false

    // 长按拖动：按住 0.42s 才算重排，短按仍然是「设为壁纸」
    private var pressTimer: Timer?
    private var pressOrigin: NSPoint = .zero      // 鼠标按下时的窗口坐标
    private var dragOrigin: NSPoint = .zero       // 拖动开始时卡片的 frame.origin
    private var dragging = false
    private var movedBeforeHold = false           // 长按没到就挪了鼠标：这次当普通拖动，不触发任何动作

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

        // 右下角微调（跟删除同款：只在悬停时出现）。点了开微调弹层、就调这一张
        tuneButton.isBordered = false
        tuneButton.wantsLayer = true
        tuneButton.layer?.cornerRadius = 11
        tuneButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        tuneButton.image = NSImage(systemSymbolName: "slider.horizontal.3",
                                   accessibilityDescription: "微调这张")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        tuneButton.contentTintColor = .white
        tuneButton.isHidden = true
        tuneButton.target = self
        tuneButton.action = #selector(tuneTapped)
        addSubview(tuneButton)

        // 右上角下方：重命名。跟删除/微调同款小圆钮，悬停才出现
        renameButton.isBordered = false
        renameButton.wantsLayer = true
        renameButton.layer?.cornerRadius = 11
        renameButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        renameButton.image = NSImage(systemSymbolName: "pencil",
                                     accessibilityDescription: "重命名")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        renameButton.contentTintColor = .white
        renameButton.isHidden = true
        renameButton.target = self
        renameButton.action = #selector(renameTapped)
        addSubview(renameButton)

        // 行内改名输入框：平时不挂，点铅笔才叠到名字位置上
        renameField.isBordered = false
        renameField.isBezeled = false
        renameField.drawsBackground = true
        renameField.backgroundColor = NSColor.black.withAlphaComponent(0.62)
        renameField.textColor = .white
        renameField.font = .systemFont(ofSize: 13, weight: .semibold)
        renameField.focusRingType = .none
        renameField.usesSingleLineMode = true
        renameField.lineBreakMode = .byTruncatingTail
        renameField.target = self
        renameField.action = #selector(commitRename)
        renameField.delegate = self

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

    deinit {
        pressTimer?.invalidate()
        stopPlayback()
    }

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
        metaLabel.frame = NSRect(x: pad, y: pad, width: max(0, w - pad * 2 - 26), height: 14)
        nameLabel.frame = NSRect(x: pad, y: pad + 15, width: max(0, w - pad * 2), height: 18)
        shade.frame = NSRect(x: 0, y: 0, width: w, height: min(h, 148))
        deleteButton.frame = NSRect(x: w - 30, y: h - 30, width: 22, height: 22)
        renameButton.frame = NSRect(x: w - 30, y: h - 58, width: 22, height: 22)
        tuneButton.frame = NSRect(x: w - 30, y: 8, width: 22, height: 22)

        if renaming {
            // 输入框跟名字标签同一行、同一字号，视觉上就像直接在原地改字
            renameField.frame = NSRect(x: pad - 4, y: nameLabel.frame.minY - 3,
                                       width: max(60, w - pad * 2 + 8), height: 24)
        }

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
        tuneButton.isHidden = false
        renameButton.isHidden = false
        thumbWrap.layer?.borderWidth = 1
        thumbWrap.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        if player == nil {
            // 网页壁纸没有本地视频可预览，保持地球图标（避免 AVPlayer 吃 dongweb:// 报错）
            guard url.isFileURL else { return }
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
        // 拖动中途鼠标必然离开卡片，这时候别收悬停态：否则卡片会一边跟着手走一边变暗。
        // 改名时同理：不然输入框刚点开、鼠标一动名字就淡没了。
        guard hovered, !dragging, !renaming else { return }
        hovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            shade.animator().alphaValue = 0
            nameLabel.animator().alphaValue = 0
            metaLabel.animator().alphaValue = 0
        }
        deleteButton.isHidden = true
        tuneButton.isHidden = true
        renameButton.isHidden = true
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
        tuneButton.isHidden = false
        thumbWrap.layer?.borderWidth = 1
        thumbWrap.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        guard url.isFileURL else { return }   // 网页壁纸没有可预览的视频
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

    /// 卡片被移除前调用，别留着解码器和长按计时器
    func teardown() {
        pressTimer?.invalidate()
        pressTimer = nil
        endRename()      // 正在改名就把输入框收掉，别留成孤儿视图
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
        pressOrigin = event.locationInWindow
        movedBeforeHold = false
        dragging = false
        pressTimer?.invalidate()
        // common mode：滚动 / 菜单跟踪时也能按时触发
        pressTimer = Timer(timeInterval: 0.32, target: self,
                           selector: #selector(beginReorderDrag), userInfo: nil, repeats: false)
        RunLoop.current.add(pressTimer!, forMode: .common)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        if !dragging {
            // 手抖 / 按住的同时就开始挪，不该取消长按：真人几乎都是边按边动的。
            // 这里只标记「这次不算点击」，计时器继续走，到点照样进入拖动。
            // 只有松手时还没到长按时间，才什么都不做。
            if hypot(p.x - pressOrigin.x, p.y - pressOrigin.y) > 7 {
                movedBeforeHold = true
            }
            return
        }
        // gallery 是 flipped 坐标：鼠标往上（window y 增大）时卡片 y 要减小
        var f = frame
        f.origin = NSPoint(x: dragOrigin.x + (p.x - pressOrigin.x),
                           y: dragOrigin.y - (p.y - pressOrigin.y))
        frame = f
        onDragMove?(p)
    }

    override func mouseUp(with event: NSEvent) {
        pressTimer?.invalidate()
        pressTimer = nil
        if dragging {
            dragging = false
            alphaValue = 1
            // 落下：图层缩放弹回 1（frame 的落位由 GalleryView 的弹簧接管）
            let drop = CASpringAnimation(keyPath: "transform")
            drop.mass = 1; drop.stiffness = 320; drop.damping = 24
            drop.fromValue = NSValue(caTransform3D: layer?.presentation()?.transform
                                     ?? layer?.transform ?? CATransform3DIdentity)
            drop.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            drop.duration = drop.settlingDuration
            layer?.removeAnimation(forKey: "vw_lift")
            layer?.transform = CATransform3DIdentity
            layer?.add(drop, forKey: "vw_drop")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.zPosition = 0
            layer?.shadowOpacity = 0.13
            thumbWrap.layer?.borderWidth = hovered ? 1 : 0
            thumbWrap.layer?.borderColor = hovered
                ? NSColor.white.withAlphaComponent(0.35).cgColor : nil
            CATransaction.commit()
            onDragEnd?()
        } else if !movedBeforeHold {
            onApply?()   // 短按还是老行为：设为壁纸（放到 mouseUp 才触发，更符合点击习惯）
        }
    }

    @objc private func beginReorderDrag() {
        guard !dragging else { return }
        pressTimer?.invalidate()
        pressTimer = nil
        dragging = true
        dragOrigin = frame.origin
        // 提到最前面，别被后面的卡片压住。
        // 用图层 zPosition 而不是重新 addSubview —— 后者会先把视图摘下来再挂回去，
        // 可能打断「按住期间」的事件响应，导致后续 mouseDragged 收不到。
        layer?.zPosition = 20
        alphaValue = 0.94
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowOpacity = 0.34
        thumbWrap.layer?.borderWidth = 2
        thumbWrap.layer?.borderColor = NSColor.controlAccentColor.cgColor
        CATransaction.commit()
        // 抬起手感：轻微放大。用图层 transform（不动 frame，免得跟手移动 + 弹簧抢同一个 frame）。
        // 系统弹簧阻尼 ≈0.72，跟 iOS 拿起图标的手感一致。
        let lift = CASpringAnimation(keyPath: "transform")
        lift.mass = 1; lift.stiffness = 300; lift.damping = 22
        lift.fromValue = NSValue(caTransform3D: layer?.transform ?? CATransform3DIdentity)
        lift.toValue = NSValue(caTransform3D: CATransform3DMakeScale(1.035, 1.035, 1))
        lift.duration = lift.settlingDuration
        layer?.add(lift, forKey: "vw_lift")
        onDragBegin?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let apply = NSMenuItem(title: "设为壁纸", action: #selector(applyTapped), keyEquivalent: "")
        apply.target = self
        menu.addItem(apply)
        let rename = NSMenuItem(title: "重命名…", action: #selector(renameTapped), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)
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
    /// 微调弹层的锚点：锚在按钮上，箭头正好指着它
    var tuneAnchor: NSView { tuneButton }
    @objc private func tuneTapped() { onTune?() }

    // MARK: 重命名（行内编辑）

    @objc private func renameTapped() {
        beginRename()
    }

    /// 在名字那一行原地变成输入框，像访达里改名一样
    func beginRename() {
        guard !renaming else { return }
        // 网页壁纸没有文件名可改
        guard url.isFileURL else {
            NSSound.beep()
            return
        }
        renaming = true
        hovered = true                       // 编辑期间保住悬停态（名字、按钮都别淡掉）
        nameLabel.alphaValue = 1
        shade.alphaValue = 1
        renameField.stringValue = url.deletingPathExtension().lastPathComponent
        thumbWrap.addSubview(renameField)
        needsLayout = true
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(renameField)
        // 全选，直接打字就替换掉旧名字
        if let editor = renameField.currentEditor() as? NSTextView {
            editor.selectAll(nil)
        }
    }

    @objc private func commitRename() {
        let raw = renameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = url.deletingPathExtension().lastPathComponent
        // 没改 / 改名后为空：当作取消，别弹错误
        if raw.isEmpty || raw == old {
            endRename()
            return
        }
        if onCommitRename?(raw) == true {
            endRename()
        } else {
            // 重名 / 非法字符 / 写入失败：留在编辑态，让用户改
            NSSound.beep()
            window?.makeFirstResponder(renameField)
        }
    }

    func endRename() {
        guard renaming else { return }
        renaming = false
        renameField.removeFromSuperview()
        window?.makeFirstResponder(nil)
        // 鼠标如果已经不在卡片上，正常收起悬停态
        if let win = window {
            let p = convert(win.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(p) { endHover() }
        }
    }
}

extension WallpaperCard: NSTextFieldDelegate {
    /// ESC 退出编辑（回车由 action 走 commitRename）
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endRename()
            return true
        }
        return false
    }
}

// MARK: - 瀑布流容器

/// 二维阻尼弹簧（参数对齐 Apple CASpringAnimation 默认：mass=1 / stiffness=200 / damping=20，
/// 阻尼比 ≈0.71，落位有一点点回弹但不晃）。直接积分到 view.frame，避开 layer.position
/// 在 flipped 容器里的坐标换算问题。
private struct VWSpring {
    var x: CGFloat, y: CGFloat
    var vx: CGFloat = 0, vy: CGFloat = 0
    var tx: CGFloat, ty: CGFloat

    init(frame: NSRect) {
        x = frame.minX; y = frame.minY
        tx = x; ty = y
    }

    mutating func retarget(_ f: NSRect) { tx = f.minX; ty = f.minY }

    /// 步进一帧（dt 秒），返回 false 表示已经收敛。
    /// 用指数衰减逼近目标：x += (target-x) * (1-e^(-k·dt))。这是标准 ease-out 插值，
    /// 单调收敛、绝不过冲，视觉上跟 Apple 的 spring(damping<1) 很接近但数值稳定。
    mutating func step(_ dt: CGFloat) -> Bool {
        let rate: CGFloat = 11.0   // 越大越快；11 ≈ 0.3s 内走完 95%
        let a = 1 - exp(-rate * dt)
        x += (tx - x) * a
        y += (ty - y) * a
        vx = (tx - x) * rate       // 仅用于收敛判定
        vy = (ty - y) * rate
        if abs(x - tx) < 0.35, abs(y - ty) < 0.35 {
            x = tx; y = ty; vx = 0; vy = 0
            return false
        }
        return true
    }
}

final class GalleryView: NSView {
    var onApply: ((Int) -> Void)?
    var onDelete: ((Int) -> Void)?
    var onReveal: ((Int) -> Void)?
    /// (卡片序号, 锚点视图)：控制器拿来切壁纸 + 开微调弹层
    var onTune: ((Int, NSView) -> Void)?

    /// 整片壁纸库任意位置（含卡片之上）都能接收拖进来的视频。
    /// 卡片本身是 `WallpaperCard`，拖到卡片上时若只靠外壳 `shell` 回退，
    /// 某些情况下落点会判到卡片、收不到添加；让直接装着卡片的 gallery 也注册为
    /// 拖拽目标，落在卡片（卡片→gallery）或缝隙（gallery）都直接命中这里。
    var onDrop: (([URL]) -> Void)?
    var onDragStateChange: ((Bool) -> Void)?
    /// 长按重排落位：(原序号, 移除源之后的插入位置)
    var onMove: ((Int, Int) -> Void)?
    /// 重命名：(序号, 新名字) → 是否成功
    var onRename: ((Int, String) -> Bool)?
    private var accepts = false

    private var dragFrom = -1
    private var dragTo = -1
    private var draggedStart: NSRect = .zero
    private var draggingCard: WallpaperCard?
    private let dropHighlight = NSView()

    /// 重排时的弹簧：目标 frame → 当前弹簧状态。key 用卡片的 URL，重建后不串。
    private var springs: [String: VWSpring] = [:]
    private var springTimer: Timer?
    private var lastSpringTick: TimeInterval = 0

    private var dropRegistered = false
    private func ensureDropRegistered() {
        guard !dropRegistered else { return }
        dropRegistered = true
        registerForDraggedTypes([.fileURL])
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ensureDropRegistered()
        // 落点高亮框：画在目标卡片外一圈，让用户看清松手会排到哪
        dropHighlight.wantsLayer = true
        dropHighlight.isHidden = true
        dropHighlight.layer?.cornerRadius = Look.radius + 3
        dropHighlight.layer?.borderWidth = 2.5
        dropHighlight.layer?.borderColor = NSColor.controlAccentColor.cgColor
        addSubview(dropHighlight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func acceptFiles(from sender: NSDraggingInfo) -> Bool {
        !ShellView.mediaURLs(from: sender.draggingPasteboard).isEmpty
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts = acceptFiles(from: sender)
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
        let files = ShellView.mediaURLs(from: sender.draggingPasteboard)
        accepts = false
        onDragStateChange?(false)
        guard !files.isEmpty else { return false }
        onDrop?(files)
        return true
    }

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
        let oldPaths = urls.map { $0.path }
        let newPaths = newURLs.map { $0.path }
        let sameSet = Set(oldPaths) == Set(newPaths)
        // 只是顺序变了（拖动重排）：复用同一批卡片对象，弹簧滑到新位置，不销毁重建。
        // 只有增删文件才走重建分支 —— 重建会打断弹簧，也丢掉正在播的视频。
        let reorderOnly = sameSet && oldPaths != newPaths && cards.count == newURLs.count
        let changed = !sameSet || cards.count != newURLs.count
        urls = newURLs
        self.current = current

        if changed {
            stopSprings()
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
        } else if reorderOnly {
            var byPath: [String: WallpaperCard] = [:]
            for c in cards { byPath[c.url.path] = c }
            cards = newPaths.compactMap { byPath[$0] }
        }

        for (i, c) in cards.enumerated() { c.setCurrent(i == current) }

        let width = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        if width > 0 { lastWidth = width }
        if reorderOnly {
            // 落位弹簧：所有卡片（含刚被拖的那张）从当前位置滑到新顺序的格子
            let (frames, total) = layoutFrames(for: cards)
            springTo(frames, total: total)
        } else {
            relayout()
        }
    }

    private func makeCard(for url: URL) -> WallpaperCard {
        let info = GalleryThumb.info(for: url)
        let card = WallpaperCard(
            url: url,
            aspect: info.aspect,
            name: WebStreams.displayName(for: url) ?? url.deletingPathExtension().lastPathComponent,
            meta: metaText(for: url, duration: info.duration))

        card.onApply = { [weak self, weak card] in
            guard let self, let card, let i = self.cards.firstIndex(where: { $0 === card }) else { return }
            self.onApply?(i)
        }
        card.onTune = { [weak self, weak card] in
            guard let self, let card, let i = self.cards.firstIndex(where: { $0 === card }) else { return }
            self.onTune?(i, card.tuneAnchor)
        }
        card.onDelete = { [weak self, weak card] in
            guard let self, let card, let i = self.cards.firstIndex(where: { $0 === card }) else { return }
            self.onDelete?(i)
        }
        card.onReveal = { [weak self, weak card] in
            guard let self, let card, let i = self.cards.firstIndex(where: { $0 === card }) else { return }
            self.onReveal?(i)
        }
        card.onDragBegin = { [weak self, weak card] in
            guard let self, let card else { return }
            self.beginReorder(card)
        }
        card.onDragMove = { [weak self, weak card] p in
            guard let self, let card else { return }
            self.updateReorder(dragging: card, windowPoint: p)
        }
        card.onDragEnd = { [weak self] in
            self?.finishReorder()
        }
        card.onCommitRename = { [weak self, weak card] name in
            guard let self, let card,
                  let i = self.cards.firstIndex(where: { $0 === card }) else { return false }
            return self.onRename?(i, name) ?? false
        }
        // 同一时刻只允许一张卡在悬停：鼠标移到别处时，把之前那张强行收回
        card.onHoverStart = { [weak self, weak card] in
            self?.clearHoverState(except: card)
        }
        return card
    }

    private func metaText(for url: URL, duration: Double) -> String {
        // 网页壁纸没有文件大小，直接报类型
        guard url.isFileURL else { return "网页壁纸" }
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

    /// 纯计算：给定一组卡片顺序，算出各自的 frame 和内容总高（不改任何视图状态）。
    /// 正式排版 / 拖动避让预览 / 落位都复用它，保证「预览位置」和「落地位置」完全一致。
    private func layoutFrames(for order: [WallpaperCard]) -> ([String: NSRect], CGFloat) {
        var frames: [String: NSRect] = [:]
        let width = max(lastWidth, 360)
        let usable = width - Look.inset * 2
        guard usable > 0 else { return (frames, 0) }

        let target: CGFloat = 238
        var cols = max(1, Int(((usable + Look.gap) / (target + Look.gap)).rounded()))
        cols = min(cols, Look.maxCols)
        if !order.isEmpty { cols = min(cols, order.count) }

        var colW = (usable - CGFloat(cols - 1) * Look.gap) / CGFloat(cols)
        if colW > Look.maxColW {
            cols = max(1, Int((usable + Look.gap) / (Look.maxColW + Look.gap)))
            colW = (usable - CGFloat(cols - 1) * Look.gap) / CGFloat(cols)
        }

        var heights = [CGFloat](repeating: Look.topInset, count: max(cols, 1))
        for (i, card) in order.enumerated() {
            let h = colW * heightRatio(for: card, index: i)
            var target2 = 0
            for k in 1..<heights.count where heights[k] < heights[target2] - 0.5 { target2 = k }
            let x = Look.inset + CGFloat(target2) * (colW + Look.gap)
            let y = heights[target2]
            frames[card.url.path] = NSRect(x: x, y: y, width: colW, height: h)
            heights[target2] = y + h + Look.gap
        }
        var total = (heights.max() ?? Look.topInset) + Look.bottomInset
        if order.isEmpty { total = 0 }
        return (frames, total)
    }

    /// 立即排版（初始化 / 窗口缩放用，不要动画）
    private func relayout() {
        guard !relaying else { return }
        relaying = true
        defer { relaying = false }

        stopSprings()
        let (frames, total) = layoutFrames(for: cards)
        for c in cards {
            guard let f = frames[c.url.path] else { continue }
            c.frame = f
            c.needsLayout = true
        }
        let width = max(lastWidth, 360)
        let visible = enclosingScrollView?.contentView.bounds.height ?? total
        setFrameSize(NSSize(width: width, height: max(total, visible)))

        if ProcessInfo.processInfo.environment["VW_GALLERY_DEBUG"] != nil {
            var lines: [String] = []
            lines.append("[gallery] width=\(Int(width)) total=\(Int(total)) cards=\(cards.count)")
            for (i, c) in cards.enumerated() {
                lines.append("  #\(i) x=\(Int(c.frame.minX)) y=\(Int(c.frame.minY)) w=\(Int(c.frame.width)) h=\(Int(c.frame.height)) aspect=\(String(format: "%.2f", c.aspect))")
            }
            try? lines.joined(separator: "\n").write(
                toFile: "/tmp/vw-gallery.txt", atomically: true, encoding: .utf8)
        }
    }

    // MARK: 弹簧动画（Apple HIG 式阻尼插值）

    /// 把每张卡朝目标 frame 弹过去；draggedPath 对应的卡片跳过（它跟手，不参与避让动画）
    private func springTo(_ frames: [String: NSRect], total: CGFloat,
                          skip draggedPath: String? = nil, resize: Bool = true) {
        for c in cards {
            let path = c.url.path
            guard path != draggedPath, let f = frames[path] else { continue }
            if var s = springs[path] {
                s.retarget(f)
                springs[path] = s
            } else {
                var s = VWSpring(frame: c.frame)
                s.retarget(f)
                springs[path] = s
            }
        }
        // 拖动中不要跟着 preview 顺序反复改 contentSize：不同排布总高不同，
        // 每来一次 mouseDragged 就 setFrameSize 会让滚动区上下抖。松手后再统一设。
        if resize {
            let visible = enclosingScrollView?.contentView.bounds.height ?? total
            setFrameSize(NSSize(width: max(lastWidth, 360), height: max(total, visible)))
        }
        startSpringTimer()
    }

    private func startSpringTimer() {
        guard springTimer == nil else { return }
        lastSpringTick = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 60.0, target: self,
                      selector: #selector(springTick), userInfo: nil, repeats: true)
        RunLoop.current.add(t, forMode: .common)
        springTimer = t
    }

    @objc private func springTick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = CGFloat(min(0.05, max(0.001, now - lastSpringTick)))
        lastSpringTick = now
        var moving = false
        for c in cards {
            let path = c.url.path
            guard var s = springs[path] else { continue }
            if s.step(dt) {
                moving = true
                springs[path] = s          // 值类型：必须把这一帧的结果写回，否则每帧都从旧值重算
            } else {
                springs[path] = nil
            }
            var f = c.frame
            f.origin = NSPoint(x: s.x, y: s.y)
            c.frame = f
        }
        if !moving { stopSprings() }
    }

    private func stopSprings() {
        springTimer?.invalidate()
        springTimer = nil
        springs.removeAll()
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

    // MARK: 长按拖动重排

    private func beginReorder(_ card: WallpaperCard) {
        // 连续拖动时，这张卡可能还带着上一次的落位弹簧在跑。拖动期间 frame 由
        // mouseDragged 直接跟手写，弹簧若再按旧目标拉一帧，就会「跟手同时被拽回」，
        // 表现为明显抽搐。这里先把它清掉。
        springs[card.url.path] = nil
        dragFrom = cards.firstIndex(where: { $0 === card }) ?? -1
        dragTo = dragFrom
        draggingCard = card
        clearHoverState()   // 其它卡片收起，避免拖动时一片视频在播
        // 记下被拖卡当前位置，松手时弹簧从「手松开的地方」弹进目标格子
        draggedStart = card.frame
        // 落点判定用的稳定网格（原顺序的格子），不受弹簧插值影响
        settleFrames = layoutFrames(for: cards).0
        lastNearest = dragFrom
    }

    private var lastNearest = -1   // 滞后用：上一次判定的最近卡片下标

    /// 原顺序下的目标格子。拖动判距必须用它，不能用 c.frame：
    /// c.frame 正被弹簧逐帧改写，拿它算「离谁最近」会形成反馈震荡（拖到边界来回抽搐）。
    private var settleFrames: [String: NSRect] = [:]

    /// 找离手最近的一张卡当落点，并判断插在它前面还是后面。
    private func updateReorder(dragging card: WallpaperCard, windowPoint: NSPoint) {
        guard dragFrom >= 0 else { return }
        let p = convert(windowPoint, from: nil)   // flipped 坐标：y 往下增大
        var best = -1
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for (i, c) in cards.enumerated() where c !== card {
            // 用静态网格格位判距，不用 c.frame（它正被弹簧改写，会形成反馈震荡）
            let cf = settleFrames[c.url.path] ?? c.frame
            let dx = max(cf.minX - p.x, 0, p.x - cf.maxX)
            let dy = max(cf.minY - p.y, 0, p.y - cf.maxY)
            let d = hypot(dx, dy)
            if d < bestDist { bestDist = d; best = i }
        }
        guard best >= 0 else {
            dragTo = dragFrom
            lastNearest = -1
            dropHighlight.isHidden = true
            return
        }
        // 滞后（hysteresis）：鼠标停在两张卡的交界处时，最近目标会来回翻转，
        // 预览布局跟着重排就是肉眼可见的「抽搐」。新候选必须明显更近（<0.75×）
        // 才切换，否则维持上一次的判定。
        var chosen = best
        if lastNearest >= 0, lastNearest < cards.count, lastNearest != best,
           let lf = settleFrames[cards[lastNearest].url.path] {
            let ldx = max(lf.minX - p.x, 0, p.x - lf.maxX)
            let ldy = max(lf.minY - p.y, 0, p.y - lf.maxY)
            if bestDist > hypot(ldx, ldy) * 0.75 { chosen = lastNearest }
        }
        lastNearest = chosen
        let target = cards[chosen]
        let tf = settleFrames[target.url.path] ?? target.frame
        // 跨行看上下，同一行看左右
        let after = (p.y < tf.minY || p.y > tf.maxY)
            ? p.y > tf.maxY
            : p.x > tf.midX
        // 换算成「源卡片移除之后」的插入位置：源在目标前面时，目标下标会左移一位
        // 必须用 chosen（滞后后的稳定目标），否则 target 和插入位不对应，仍会来回跳
        let to = dragFrom < chosen ? (after ? chosen : chosen - 1)
                                   : (after ? chosen + 1 : chosen)
        dragTo = max(0, min(to, cards.count - 1))

        // 避让排布：按「假如现在松手」的顺序先算一遍目标格子，让被挤到的卡片
        // 弹簧滑开留出空位；被拖的那张跳过（它正跟手）。高亮框落在空位上。
        var preview = cards
        if let dragged = draggingCard, let fi = preview.firstIndex(where: { $0 === dragged }) {
            preview.remove(at: fi)
            preview.insert(dragged, at: dragTo)
        }
        let (frames, total) = layoutFrames(for: preview)
        springTo(frames, total: total, skip: draggingCard?.url.path, resize: false)

        if dragTo == dragFrom {
            dropHighlight.isHidden = true
        } else if let slot = frames[draggingCard?.url.path ?? ""] {
            // 只在「从隐藏变显示」时提到最前。原先每次 mouseDragged 都
            // removeFromSuperview + addSubview，鼠标一动就重建 layer，会闪。
            if dropHighlight.isHidden {
                dropHighlight.removeFromSuperview()
                addSubview(dropHighlight)
            }
            dropHighlight.frame = slot.insetBy(dx: -3, dy: -3)
            dropHighlight.isHidden = false
        }
    }

    private func finishReorder() {
        dropHighlight.isHidden = true
        let from = dragFrom, to = dragTo
        dragFrom = -1
        dragTo = -1

        // 被拖的卡片此刻还停在手松开的位置。先把它的弹簧目标设为「插入后」
        // 的格子，让它弹进去；数据由 onMove 异步提交，卡片对象复用所以动画不断。
        if from >= 0, to >= 0, from != to, let dragged = draggingCard {
            var preview = cards
            let moved = preview.remove(at: from)
            preview.insert(moved, at: to)
            let (frames, total) = layoutFrames(for: preview)
            springTo(frames, total: total)   // 含被拖卡：从松手处弹入新格子
            onMove?(from, to)                // 委托侧重排 + 持久化，不重建卡片
        } else {
            // 没换位：所有卡片（含被拖的那张）弹回原位
            let (frames, total) = layoutFrames(for: cards)
            springTo(frames, total: total)
        }
        draggingCard = nil
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

// MARK: - 底栏的极简滑杆

/// 底栏用的细滑杆：一条 3pt 细轨 + 9pt 圆点，单色白，不参与系统强调色。
/// 不用 NSSlider 的原因：它的强调色是一条很跳的绿线，跟窗口里的橙色图标打架，
/// 而且控件本身太重——一个"调光"的东西不该比内容更显眼。
final class MiniSlider: NSView {
    var onChange: ((CGFloat) -> Void)?
    /// 0…1，越右越透
    var value: CGFloat = 0.88 {
        didSet {
            let clamped = min(1, max(0, value))
            if clamped != value { value = clamped; return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 78, height: 18) }

    private let trackHeight: CGFloat = 3
    private let knobDiameter: CGFloat = 9

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.midY
        // 空轨
        let track = NSRect(x: 0, y: mid - trackHeight / 2,
                           width: bounds.width, height: trackHeight)
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: track, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

        // 已选段 + 圆点
        let knobX = knobDiameter / 2 + (bounds.width - knobDiameter) * value
        let filled = NSRect(x: 0, y: mid - trackHeight / 2, width: knobX, height: trackHeight)
        NSColor.white.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: filled, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX - knobDiameter / 2, y: mid - knobDiameter / 2,
                                    width: knobDiameter, height: knobDiameter)).fill()
    }

    override func mouseDown(with event: NSEvent) { apply(event) }
    override func mouseDragged(with event: NSEvent) { apply(event) }

    private func apply(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let usable = max(1, bounds.width - knobDiameter)
        value = (p.x - knobDiameter / 2) / usable
        onChange?(value)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
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

    /// 外观切换（深/浅色）后重新着色：图标亮度跟底栏玻璃走，不跟 window.appearance
    func refreshAppearance() { restyle() }

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
        //   开着 → 饱和主题橙 + 一层很淡的同色雾
        //   关着/动作键 → 浅暖橙：底栏玻璃恒为深色，灰白描边在上面糊成一团，
        //                  换成有颜色的暖橙既亮又清楚（用户诉求）
        // 状态区分靠「开态有淡雾底 + 图标形态变化」，不靠灰/橙，所以两态都用橙也不冲突。
        // 注意：SF Symbol 的 paletteColors 第二色对单色描边符号（power/plus/folder/
        // gearshape）不起作用，所以主体色本身必须带颜色，不能指望第二色上纹路。
        let ink: NSColor
        let palette: [NSColor]
        if isOn && !isAction {
            ink = Brand.accent
            palette = [Brand.accent, Brand.gradBottom]   // 多色符号给一点层次
        } else {
            ink = hovered ? Brand.gradTop : Brand.gradTop.withAlphaComponent(0.92)
            palette = [ink, Brand.accent]                // 多色符号的里层用深一档橙
        }

        if let base = NSImage(systemSymbolName: shownSymbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: palette))
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

/// 设置弹层里的分组标题：整行可点，右侧一个箭头 + 状态摘要。
/// 收起时只留这一行，点开才把下面的开关铺出来，免得弹层一路长到屏幕外。
final class SettingsSectionHeader: NSView {
    var onToggle: (() -> Void)?
    private(set) var expanded = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.alignment = .right
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = Self.chevronImage(expanded: false)

        addSubview(titleLabel)
        addSubview(summaryLabel)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            summaryLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            summaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            summaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor,
                                                  constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func chevronImage(expanded: Bool) -> NSImage? {
        NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: expanded ? "收起" : "展开")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
    }

    func update(summary: String, expanded: Bool) {
        summaryLabel.stringValue = summary
        summaryLabel.isHidden = summary.isEmpty
        if self.expanded != expanded {
            self.expanded = expanded
            chevron.image = Self.chevronImage(expanded: expanded)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - 「反馈」入口

/// 设置弹层底部的「反馈」：平时只有两个字，鼠标压上去才浮出飞书群信息，
/// 点一下直接唤起飞书进群。目的是"想反馈的人找得到，又不用在界面上摊一堆文字"。
final class FeedbackLink: NSView {
    /// 飞书群邀请链接（点「反馈」直接打开）
    static let inviteURL = URL(string:
        "https://applink.feishu.cn/client/chat/chatter/add_by_link?link_token=de4l4bc2-75cf-4d5e-b088-2c7ca62f1bee")!

    var onOpen: (() -> Void)?
    /// 卡片挂在哪个视图上（设置弹层传根视图；不传就退回窗口 contentView）
    weak var tipHost: NSView?

    private let label = NSTextField(labelWithString: "反馈")
    private var tip: FeedbackTip?
    private var tracking: NSTrackingArea?
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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
        hideWork?.cancel()
        hideWork = nil
        label.textColor = .labelColor
        showTip()
    }

    override func mouseExited(with event: NSEvent) {
        label.textColor = .secondaryLabelColor
        // 稍微留一点时间：鼠标从文字移到卡片上时不至于闪一下就没
        let work = DispatchWorkItem { [weak self] in self?.hideTip() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    override func mouseDown(with event: NSEvent) {
        onOpen?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func showTip() {
        guard tip == nil, let host = tipHost ?? window?.contentView else { return }
        let card = FeedbackTip()
        card.frame.size = FeedbackTip.size
        // 卡片浮在「反馈」上方，左右不越出弹层。
        // 挂到弹层根视图而不是这一行：行高只有 18pt，卡片会被行裁掉。
        let inHost = convert(bounds, to: host)
        var x = inHost.midX - FeedbackTip.size.width / 2
        x = min(max(x, 8), max(8, host.bounds.width - FeedbackTip.size.width - 8))
        var y = inHost.maxY + 6
        if y + FeedbackTip.size.height > host.bounds.height - 6 {
            y = max(6, inHost.minY - FeedbackTip.size.height - 6)   // 上面放不下就翻到下面
        }
        card.frame.origin = NSPoint(x: x, y: y)
        card.alphaValue = 0
        host.addSubview(card)
        tip = card
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            card.animator().alphaValue = 1
        }
    }

    /// 调试用：不需要真实鼠标也能把卡片画出来核对版式
    func debugShowTip() { showTip() }

    private func hideTip() {
        guard let card = tip else { return }
        tip = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            card.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { card.removeFromSuperview() }
    }
}

/// 「反馈」上方那张小卡片：标题 + 用途 + 链接。纯展示，点击由外面的文字负责。
final class FeedbackTip: NSView {
    static let size = NSSize(width: 238, height: 88)

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        // 必须完全不透明：哪怕只留 4% 透过，底下的「自动暂停/自动轮换」标题
        // 也会在卡片上显出灰影，跟卡片文字叠在一起显得脏
        layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.zPosition = 50

        let title = NSTextField(labelWithString: "Dòng 用户反馈群")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .white

        let sub = NSTextField(labelWithString: "飞书群 · 问题反馈与功能建议")
        sub.font = .systemFont(ofSize: 10.5)
        sub.textColor = NSColor.white.withAlphaComponent(0.78)

        let link = NSTextField(labelWithString: "applink.feishu.cn/client/chat/…")
        link.font = .systemFont(ofSize: 9.5)
        link.textColor = NSColor.white.withAlphaComponent(0.5)
        link.lineBreakMode = .byTruncatingTail

        let hint = NSTextField(labelWithString: "点击「反馈」加入")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = Brand.accent

        for (v, y) in [(title, 64.0), (sub, 46.0), (link, 28.0), (hint, 8.0)] {
            v.frame = NSRect(x: 12, y: y, width: Self.size.width - 24, height: 15)
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 让卡片自己不吃鼠标事件：悬停判定和点击都留在「反馈」两个字上，
    /// 否则鼠标一移到卡片上就会触发 exited、卡片自己闪没
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

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

// MARK: - 壁纸库窗口透明度

/// 「窗口透明度」设置的存取 + 变更广播。值域 0…1，语义和网易云那个滑杆一致：
/// **数值越大越透**。0 = 一片深色实底，1 = 几乎全透、只剩系统模糊。
///
/// 内部仍按"涂层浓度"算（frost = 1 - transparency）：浓度是画的时候要的参数，
/// 透明度是给人看的参数，两者别混在一个名字里。
enum LibraryBackdrop {
    /// ShellView 监听它，收到就重画涂层，滑杆一拖窗口立刻跟上
    static let changed = Notification.Name("VWLibraryBackdropChanged")
    private static let key = "VWLibraryTransparency"
    /// 默认 0.88：几乎全透。桌面壁纸能清楚透上来，只留一层很淡的暗色压着卡片。
    static let defaultTransparency: CGFloat = 0.88

    /// 0 = 实色，1 = 几乎全透
    static var transparency: CGFloat {
        get {
            let ud = UserDefaults.standard
            guard ud.object(forKey: key) != nil else { return defaultTransparency }
            return min(1, max(0, CGFloat(ud.double(forKey: key))))
        }
        set {
            UserDefaults.standard.set(Double(min(1, max(0, newValue))), forKey: key)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// 画的时候用的涂层浓度 = 1 - 透明度
    static var frost: CGFloat { 1 - transparency }

    /// 壁纸库窗口深浅色。默认深色（照录屏定的）；底栏那枚磁贴切换，
    /// 切完广播 `changed`：外壳按新色重画涂层，控制器把窗口外观一起换掉。
    private static let darkKey = "VWLibraryDarkMode"

    static var darkMode: Bool {
        get { (UserDefaults.standard.object(forKey: darkKey) as? Bool) ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: darkKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}

// MARK: - 接收拖拽的外壳

/// 窗口外壳：一层磨砂底衬。
/// 和菜单栏面板（`PanelGlass` 用系统 `.menu` 材质做真模糊）保持同一个观感家族，
/// 但这里不做模糊：桌面是一段正在播放的视频，逐帧重算模糊既费 GPU，糊出来的颜色也在跳。
/// 所以只用一层均匀的半透明底衬——桌面透得上来，但不会跟着视频一帧一帧变亮变暗，
/// 缩略图仍然像"浮"在桌面上。
final class ShellView: NSView {
    static let radius: CGFloat = 16

    /// 涂层浓度（上、下）只由 frost 决定：frost 0 → 2%，frost 1 → 88%。
    ///
    /// 深浅两套涂层：深色（默认，照录屏定的）用黑玻璃，"透出来但压得住"；
    /// 浅色用白雾，给喜欢亮底的用户——底栏那枚「深色/浅色」磁贴切换，别再写死一种。
    private static func matteAlphas(frost: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let mid = 0.02 + 0.86 * frost
        // 只够分出上下，不构成高光——玻璃面不该反光
        let delta: CGFloat = 0.02
        return (min(1, mid + delta), max(0, mid - delta))
    }

    /// 调试钩子：`VW_MATTE=0.18,0.12` 临时覆盖浓度（上,下），不重编译就能比几档。
    private static let matteOverride: (top: CGFloat, bottom: CGFloat)? = {
        guard let raw = ProcessInfo.processInfo.environment["VW_MATTE"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return (CGFloat(parts[0]), CGFloat(parts[1]))
    }()

    /// 颗粒噪声的浓度。磨砂面之所以"像磨砂"，靠的就是这层极细的颗粒：
    /// 只有 3% 的不透明度、1 个物理像素大小的点，正常观看距离下看不见，
    /// 但它会打散底衬上那层渐变带来的"塑料膜感"，让半透明面读起来像材质而不是一块蒙版。
    /// 实测 2% 完全看不见，5% 近看偏脏，3% 是"远看是哑光面、凑近有质感"的平衡点。
    /// 调试钩子：`VW_GRAIN=0.05` 临时覆盖浓度。
    private static let grainAlpha: CGFloat = {
        guard let raw = ProcessInfo.processInfo.environment["VW_GRAIN"],
              let v = Double(raw) else { return 0.03 }
        return CGFloat(v)
    }()
    private static let grainTile = 256
    /// 噪声图只画一次，之后平铺——每帧随机描点在 Retina 上会卡。
    private static var grainImage: NSImage?

    var onDrop: (([URL]) -> Void)?
    var onDragStateChange: ((Bool) -> Void)?
    private var accepts = false
    private var backdropObserver: NSObjectProtocol?

    override var isOpaque: Bool { false }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        // 磨砂的边不是反光边，压得比玻璃薄一点
        layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        registerForDraggedTypes([.fileURL])
        // 滑杆动了就重画涂层（浓度只影响 draw，不用重建任何视图）
        backdropObserver = NotificationCenter.default.addObserver(
            forName: LibraryBackdrop.changed, object: nil, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }
    }

    deinit {
        if let o = backdropObserver { NotificationCenter.default.removeObserver(o) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // 深色玻璃的边：亮暗都只是极淡一圈，别做成反光的亮环
        layer?.borderColor = NSColor.white.withAlphaComponent(isDark ? 0.14 : 0.18).cgColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: Self.radius, yRadius: Self.radius)
        let frost = LibraryBackdrop.frost
        let alphas = Self.matteOverride ?? Self.matteAlphas(frost: frost)
        let base = LibraryBackdrop.darkMode ? NSColor.black : NSColor.white
        let top = base.withAlphaComponent(alphas.top)
        let bottom = base.withAlphaComponent(alphas.bottom)
        // 单向极淡的渐变只为让窗口有上下之分，不是高光——玻璃面不该反光
        if let g = NSGradient(starting: bottom, ending: top) {
            g.draw(in: path, angle: 90)
        } else {
            top.setFill()
            path.fill()
        }
        // 裁剪在圆角内，颗粒不会溢出到窗口外面。
        // 平铺尺寸取整到点，避免 256 除不尽时出现一条接缝。
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let tileW = ceil(bounds.width / Self.grainScale) * Self.grainScale
        let tileH = ceil(bounds.height / Self.grainScale) * Self.grainScale
        // 颗粒跟着浓度走：越透越不该有颗粒。全透时还留点点，会在深色桌面上变成一片脏雪花。
        Self.grain().draw(in: NSRect(x: 0, y: 0, width: tileW, height: tileH),
                          from: .zero,
                          operation: .sourceOver,
                          fraction: min(1, max(0, frost)),
                          respectFlipped: true,
                          hints: [.interpolation: NSImageInterpolation.none.rawValue])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 平铺用的颗粒图。按屏幕的 2 倍图来画：这样每个噪点正好落在 1 个物理像素上，
    /// 不会被整数放大成 2×2 的硬边方块（那样看着像马赛克，不像磨砂）。
    private static func grain() -> NSImage {
        if let cached = grainImage { return cached }
        let side = grainTile
        let scale: CGFloat = 2
        let px = side * 2
        let img = NSImage(size: NSSize(width: side, height: side))
        // 用 lockFocus 拿到带正确色彩空间的上下文，再把坐标系放大 2 倍，
        // 于是一个"1 点"的方块正好落在 1 个物理像素上。
        img.lockFocus()
        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .none
            ctx.cgContext.scaleBy(x: scale, y: scale)
        }
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        let a = grainAlpha
        for y in 0..<px {
            for x in 0..<px {
                // xorshift：只要够乱就行，不需要统计意义上的好随机
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                let r = CGFloat(seed & 0xFFFF) / 65535
                // 黑点多、白点少：白点会在暗色壁纸上先"冒出来"，压住它的比例
                let white = r > 0.55
                let c = white ? NSColor.white : NSColor.black
                c.withAlphaComponent(white ? a * 0.6 : a).setFill()
                NSRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale,
                       width: 1 / scale, height: 1 / scale).fill()
            }
        }
        img.unlockFocus()
        // 记住缩放，绘制时才知道该按哪个倍数取样
        grainScale = scale
        grainImage = img
        return img
    }

    private static var grainScale: CGFloat = 1

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 拖进来的既可以是视频，也可以是图片（图片做成静态壁纸）。
    static func mediaURLs(from pasteboard: NSPasteboard) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]
        else { return [] }
        let exts = Source.videoExts.union(Transcoder.imageExts)
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
        accepts = !Self.mediaURLs(from: sender.draggingPasteboard).isEmpty
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
        let files = Self.mediaURLs(from: sender.draggingPasteboard)
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

        // 导入时顺带推荐自选插件，写清实测占用 + 去哪下载（用户有权先知道代价）。
        let rec = NSTextField(labelWithString: Transcoder.perfectLoopRecommendationWithLink)
        rec.font = .systemFont(ofSize: 10)
        rec.textColor = NSColor.white.withAlphaComponent(0.5)
        rec.alignment = .center
        rec.maximumNumberOfLines = 2
        rec.lineBreakMode = .byWordWrapping
        rec.preferredMaxLayoutWidth = 420
        rec.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, text, sub, rec])
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

final class LibraryWindowController: NSWindowController, NSPopoverDelegate {

    private weak var delegate: WallpaperLibraryDelegate?
    private let gallery = GalleryView()
    private var scroll: GalleryScrollView!
    private var emptyView: NSView!
    private var pill: StatusPill!
    private var overlay: DropOverlay!
    private var dropTarget: ShellView!
    private weak var shell: NSView?
    private var dockTip: DockTip?
    private var appearanceObserver: NSObjectProtocol?

    init(delegate: WallpaperLibraryDelegate) {
        self.delegate = delegate
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 730),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        win.title = "壁纸库"
        win.minSize = NSSize(width: 760, height: 460)
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
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: LibraryBackdrop.changed, object: nil, queue: .main
        ) { [weak self] _ in self?.applyWindowAppearance() }
    }

    deinit {
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
    }

    /// 深浅色切换：窗口和底衬材质一起换；弹层、文字用的都是语义色，跟着自动翻。
    private func applyWindowAppearance() {
        let appearance = NSAppearance(named: LibraryBackdrop.darkMode ? .darkAqua : .aqua)
        window?.appearance = appearance
        (window?.contentView as? NSVisualEffectView)?.appearance = appearance
        // 底栏图标/文字用固定亮墨色，不随 window.appearance 翻成黑色压在深玻璃上
        let ink = Self.barInk
        transparencyIcon?.contentTintColor = ink
        barPct?.textColor = ink
        for p in [enabledPill, lockPill, autoPill, addPill, folderPill, settingsPill] {
            p?.refreshAppearance()
        }
        avatarPill?.refreshAppearance(ink: ink)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: 组装

    private func buildUI() {
        guard let win = window else { return }

        // 底衬：`.behindWindow` 的系统真模糊，跟设置弹层同一个材质家族。
        // 窗口后面的桌面（正在播的视频）会被真正"糊"进底衬，磨砂感是实打实的。
        // ShellView 的半透明涂层铺在它上面，浓度由设置弹层的「背景模糊度」滑杆控制。
        let backdrop = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 1060, height: 730))
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        // 材质外观钉在自己身上，不跟系统走：默认深色（录屏里那种"深色玻璃透出桌面"），
        // 底栏「深色/浅色」磁贴切换时由 applyWindowAppearance() 统一换。
        backdrop.appearance = NSAppearance(named: LibraryBackdrop.darkMode ? .darkAqua : .aqua)
        win.contentView = backdrop

        let shell = ShellView(frame: NSRect(x: 0, y: 0, width: 1060, height: 730))
        shell.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(shell)
        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            shell.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            shell.topAnchor.constraint(equalTo: backdrop.topAnchor),
            shell.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
        dropTarget = shell

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

        // 底座：一条几乎看不见底的深色玻璃，只借模糊和一缕反光"托"住里面的东西。
        // 窗口已经是深色玻璃了，底栏再走浅色会出现"白条上压白字"，所以跟窗口同一路。
        // floating 让它整块抬起，底下带一层柔和的投影，卡片从阴影里穿过去。
        let bar = GlassView(radius: 22, tint: 0.10, material: .popover,
                            chrome: .dark, floating: true)

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

        // 从电脑里挑视频 / 图片：常驻入口。空状态里那个按钮只在库空时才看得到，
        // 库里有壁纸之后也得有个地方能继续添加。
        let addPill = SettingPill(actionTitle: "添加文件", symbol: "plus")
        addPill.onTap = { [weak self] in self?.pickFiles() }
        self.addPill = addPill

        // 打开文件夹：同款胶囊，但不是开关，跟开关之间用一条细线隔开
        let folderPill = SettingPill(actionTitle: "打开文件夹", symbol: "folder")
        folderPill.onTap = { [weak self] in self?.delegate?.libraryRevealFolder() }
        self.folderPill = folderPill

        // 设置：匿名统计开关 + 检查更新，都放进一个小弹层，不占底栏地方
        let settingsPill = SettingPill(actionTitle: "设置", symbol: "gearshape")
        self.settingsPill = settingsPill
        settingsPill.onTap = { [weak self, weak settingsPill] in
            guard let self, let anchor = settingsPill else { return }
            self.toggleSettings(from: anchor)
        }

        // 账号头像：底栏最右。没登录是个人形剪影，登录后变成邮箱首字母的橙色圆。
        // 深浅色切换搬进了设置弹层（用户要求：这里留给个人信息）。
        let avatarPill = AvatarPill()
        self.avatarPill = avatarPill
        avatarPill.onTap = { [weak self, weak avatarPill] in
            guard let self, let anchor = avatarPill else { return }
            self.toggleAccount(from: anchor)
        }

        avatarPill.onHoverChange = { [weak self, weak avatarPill] on in
            guard let self, let p = avatarPill else { return }
            on ? self.showTip(text: "账号", anchor: p) : self.dockTip?.hide()
        }

        for p in [enabledPill, lockPill, autoPill, addPill, folderPill, settingsPill] {
            p.onHoverChange = { [weak self, weak p] on in
                guard let self, let p else { return }
                on ? self.showTip(for: p) : self.dockTip?.hide()
            }
        }

        // 窗口透明度：常驻底栏，一拖就变。语义和录屏里那个滑杆一致——越往右越透。
        // 只给一层很淡的暗色，不能做成有底色的胶囊，否则又变成"一块实心控件"。
        let transparencyIcon = NSImageView()
        transparencyIcon.image = NSImage(systemSymbolName: "circle.lefthalf.filled",
                                        accessibilityDescription: "窗口透明度")
        transparencyIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        transparencyIcon.contentTintColor = Self.barInk
        transparencyIcon.translatesAutoresizingMaskIntoConstraints = false
        self.transparencyIcon = transparencyIcon

        let barSlider = MiniSlider()
        barSlider.value = LibraryBackdrop.transparency
        barSlider.toolTip = "窗口透明度：越往右越透"
        barSlider.onChange = { [weak self] v in self?.applyTransparency(v) }
        barSlider.translatesAutoresizingMaskIntoConstraints = false
        // 宽度可伸缩：窗口宽就 78pt，拉窄时先压滑杆，别把右边几个开关挤出去
        let sliderPref = barSlider.widthAnchor.constraint(equalToConstant: 78)
        sliderPref.priority = .defaultHigh
        sliderPref.isActive = true
        barSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        barSlider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        self.barSlider = barSlider

        let barPct = NSTextField(labelWithString: "\(Int(round(LibraryBackdrop.transparency * 100)))%")
        barPct.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        barPct.textColor = Self.barInk
        barPct.alignment = .right
        barPct.translatesAutoresizingMaskIntoConstraints = false
        barPct.widthAnchor.constraint(equalToConstant: 26).isActive = true
        self.barPct = barPct

        let transparencyRow = NSStackView(views: [transparencyIcon, barSlider, barPct])
        transparencyRow.orientation = .horizontal
        transparencyRow.alignment = .centerY
        transparencyRow.spacing = 6
        transparencyRow.translatesAutoresizingMaskIntoConstraints = false

        /// 开关之间的竖线：两条都用同一个做法，别让粗细/透明度各走各的
        func makeDivider() -> NSView {
            let d = NSView()
            d.wantsLayer = true
            d.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.13).cgColor
            d.translatesAutoresizingMaskIntoConstraints = false
            d.widthAnchor.constraint(equalToConstant: 1).isActive = true
            d.heightAnchor.constraint(equalToConstant: 16).isActive = true
            return d
        }
        let divider = makeDivider()

        let pills = NSStackView(views: [transparencyRow, makeDivider(),
                                        enabledPill, lockPill, autoPill, divider,
                                        addPill, folderPill, settingsPill, avatarPill])
        pills.orientation = .horizontal
        pills.spacing = 6
        pills.alignment = .centerY
        pills.setCustomSpacing(10, after: transparencyRow)
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
        gallery.onTune = { [weak self] i, anchor in
            guard let self else { return }
            // 点哪张就调哪张：先切过去（实时效果要播出来才看得见），再在这张卡上开弹层。
            // 切换不会重建卡片（setItems 只在 URL 列表变化时重建），锚点是安全的。
            self.delegate?.libraryApply(index: i)
            self.showTuning(from: anchor)
        }
        gallery.onDelete = { [weak self] i in self?.delegate?.libraryDelete(index: i) }
        gallery.onMove = { [weak self] from, to in self?.delegate?.libraryMove(from: from, to: to) }
        gallery.onRename = { [weak self] i, name in
            self?.delegate?.libraryRename(index: i, to: name) ?? false
        }
        gallery.onReveal = { [weak self] i in
            guard let self, let urls = self.delegate?.libraryVideos(), i < urls.count else { return }
            // 网页壁纸没有真实文件可定位，跳过
            guard urls[i].isFileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([urls[i]])
        }
        // 整片壁纸库都能接收拖入的视频：落点不管在卡片上还是缝隙里都直接命中 gallery
        gallery.onDrop = { [weak self] urls in self?.delegate?.libraryAdd(urls: urls) }
        gallery.onDragStateChange = { [weak self] on in self?.overlay.setVisible(on) }

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
            linkField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
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
    private var addPill: SettingPill?
    private var folderPill: SettingPill?
    private var settingsPill: SettingPill?
    private var avatarPill: AvatarPill?
    private var settingsDarkSwitch: NSSwitch?
    private var accountPop: NSPopover?
    /// 设置弹层（匿名统计开关 + 检查更新）
    private var settingsPop: NSPopover?
    /// 画面微调弹层
    private var tuningPop: NSPopover?
    private var tuneSpeedLabel: NSTextField?
    /// 一键安装插件的进度/结果文字（装完即时刷新，不重启）
    private var pluginInstallStatus: NSTextField?
    private var pluginInstallButton: NSButton?
    private var settingsSwitch: NSSwitch?
    /// 自动暂停三规则（设置弹层里）
    private var pauseFullscreenSwitch: NSSwitch?
    private var pauseLockSwitch: NSSwitch?
    private var dynamicLockSwitch: NSSwitch?
    private var pauseLowBatterySwitch: NSSwitch?
    private var settingsAction: NSButton?
    private var settingsStatus: NSTextField?
    /// 设置弹层底部的「反馈」入口（调试渲染悬停态也要用到）
    private var feedbackLink: FeedbackLink?
    private var settingsBlurPct: NSTextField?
    private var settingsBlurSlider: NSSlider?
    /// 自动轮换的控件：总开关 / 方式 / 三个触发条件 / 定时间隔
    private var rotateSwitch: NSSwitch?
    private var rotateModePop: NSPopUpButton?
    private var rotateLaunchSwitch: NSSwitch?
    private var rotateUnlockSwitch: NSSwitch?
    private var rotateWakeSwitch: NSSwitch?
    private var rotateIntervalPop: NSPopUpButton?

    // 可折叠区块：弹层太长时只留标题行
    private var settingsVC: NSViewController?
    private var settingsRoot: NSView?
    private var settingsStack: NSStackView?
    private var pauseHeader: SettingsSectionHeader?
    private var rotateHeader: SettingsSectionHeader?
    private var pauseSectionRows: [NSView] = []
    private var rotateSectionRows: [NSView] = []
    /// 默认都收起：需要时再展开
    private var pauseExpanded = false
    private var rotateExpanded = false
    /// 底栏常驻的「窗口透明度」：滑杆 + 百分比，和设置弹层里那个是同一份值
    private var barSlider: MiniSlider?
    private var barPct: NSTextField?
    private var transparencyIcon: NSImageView?
    /// 底栏图标/文字的固定墨色：底栏玻璃恒为深色，亮色才看得清（不跟 window.appearance）
    private static var barInk: NSColor {
        LibraryBackdrop.darkMode
            ? NSColor.white.withAlphaComponent(0.94)
            : NSColor.white.withAlphaComponent(0.86)
    }
    private var settingsTimer: Timer?
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

    // MARK: 设置弹层（匿名统计 + 更新）

    /// 调试用：把设置弹层那块内容画成 PNG（弹层是独立窗口，截不到，只能自己渲染）
    /// 调试用：把整个壁纸库窗口拍成图（重点看底栏那颗头像）
    func debugSnapshotWindow(to path: String) {
        guard let v = window?.contentView else { return }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        print("[window] shot size=\(v.bounds.size)")
    }

    func debugSnapshotSettings(to path: String) {
        let vc = makeSettingsController()
        guard let v = vc.view as NSView? else { return }
        // VW_SETTINGS_EXPAND=1 先把两组都展开再截图，核对折叠前后高度
        if ProcessInfo.processInfo.environment["VW_SETTINGS_EXPAND"] != nil {
            toggleSettingsSection(.pause)
            toggleSettingsSection(.rotate)
        }
        v.layoutSubtreeIfNeeded()
        // VW_FEEDBACK_TIP=1 直接把「反馈」的悬停卡片画出来核对版式
        if ProcessInfo.processInfo.environment["VW_FEEDBACK_TIP"] != nil {
            feedbackLink?.debugShowTip()
            v.layoutSubtreeIfNeeded()
        }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        print("[settings] shot size=\(v.bounds.size) analytics=\(Analytics.shared.isEnabled)")
    }

    private func toggleSettings(from anchor: NSView) {
        if let pop = settingsPop, pop.isShown {
            pop.performClose(nil)
            return
        }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = makeSettingsController()
        pop.delegate = self
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        settingsPop = pop

        refreshSettingsState()
        settingsTimer?.invalidate()
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refreshSettingsState()
        }
        RunLoop.main.add(t, forMode: .common)
        settingsTimer = t
    }

    // MARK: 画面微调弹层

    private func showTuning(from anchor: NSView) {
        if let pop = tuningPop, pop.isShown {
            pop.close()
        }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = makeTuningController()
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        tuningPop = pop
    }

    private func makeTuningController() -> NSViewController {
        let vc = NSViewController()
        let width: CGFloat = 330
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 460))
        root.wantsLayer = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        func heading(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: 13, weight: .semibold)
            return l
        }
        func caption(_ s: String, tint: NSColor? = nil) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: s)
            l.font = .systemFont(ofSize: 11)
            l.textColor = tint ?? .secondaryLabelColor
            l.maximumNumberOfLines = 0
            l.preferredMaxLayoutWidth = width - 32
            l.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
            return l
        }
        func sliderRow(_ title: String, value: String, min: Double, max: Double,
                       current: Double, action: Selector) -> (NSStackView, NSTextField) {
            let r = NSStackView()
            r.orientation = .horizontal
            r.alignment = .centerY
            r.spacing = 8
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12.5)
            label.widthAnchor.constraint(equalToConstant: 62).isActive = true
            let slider = NSSlider(value: current, minValue: min, maxValue: max,
                                  target: self, action: action)
            slider.controlSize = .small
            slider.widthAnchor.constraint(equalToConstant: 148).isActive = true
            let val = NSTextField(labelWithString: value)
            val.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            val.textColor = .secondaryLabelColor
            val.alignment = .right
            val.widthAnchor.constraint(equalToConstant: 52).isActive = true
            r.addArrangedSubview(label)
            r.addArrangedSubview(slider)
            r.addArrangedSubview(val)
            r.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
            return (r, val)
        }
        func selectRow(_ title: String, items: [String], selected: Int,
                       action: Selector) -> NSStackView {
            let r = NSStackView()
            r.orientation = .horizontal
            r.alignment = .centerY
            r.spacing = 8
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12.5)
            label.widthAnchor.constraint(equalToConstant: 62).isActive = true
            let pop = NSPopUpButton(frame: .zero, pullsDown: false)
            pop.addItems(withTitles: items)
            pop.selectItem(at: selected)
            pop.target = self
            pop.action = action
            pop.controlSize = .small
            r.addArrangedSubview(label)
            r.addArrangedSubview(pop)
            r.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
            return r
        }

        stack.addArrangedSubview(heading("画面微调"))
        stack.addArrangedSubview(caption("拖完即走，设置会记住"))
        stack.addArrangedSubview(caption("实时生效 · 当前这张壁纸", tint: .controlAccentColor))

        let speed = sliderRow("播放速度", value: String(format: "%.2f×", Tuning.speed),
                              min: 0.5, max: 2, current: Tuning.speed,
                              action: #selector(tuneSpeedChanged(_:)))
        stack.addArrangedSubview(speed.0)
        tuneSpeedLabel = speed.1

        let line = NSBox()
        line.boxType = .separator
        stack.addArrangedSubview(line)
        line.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        stack.addArrangedSubview(caption("生成设置 · 重新生成或下次导入后写入视频"))

        let fpsIndex: Int
        switch Tuning.outputFPS {
        case 24: fpsIndex = 1
        case 30: fpsIndex = 2
        case 60: fpsIndex = 3
        default: fpsIndex = 0
        }
        stack.addArrangedSubview(selectRow("输出帧率",
                                           items: ["跟随源（≤30）", "24 fps · 更省电", "30 fps", "60 fps · 体积翻倍"],
                                           selected: fpsIndex, action: #selector(tuneFPSChanged(_:))))
        let f = Tuning.fadeSeconds
        let fadeIndex = f < 0.1 ? 0 : (f < 0.3 ? 1 : (f < 0.6 ? 2 : 3))
        stack.addArrangedSubview(selectRow("首尾淡化", items: ["关闭（默认 · 无缝循环）", "溶解 0.2 s", "溶解 0.4 s", "溶解 0.8 s"],
                                           selected: fadeIndex, action: #selector(tuneFadeChanged(_:))))

        let regen = NSButton(title: "用新设置重新生成这张壁纸",
                             target: self, action: #selector(tuneRegenerateTapped))
        regen.bezelStyle = .rounded
        regen.controlSize = .small
        regen.font = .systemFont(ofSize: 11.5)
        stack.addArrangedSubview(regen)
        regen.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        let reset = NSButton(title: "还原默认", target: self, action: #selector(tuneResetTapped))
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.font = .systemFont(ofSize: 11.5)
        stack.addArrangedSubview(reset)
        reset.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        // 底部状态：反映实际生成管线。PerfectLoop 是用户自选插件，没装就回退普通循环，
        // 并在此给出带实测占用的推荐；装了才显示「PerfectLoop 无缝循环」。
        let fpsText = Tuning.outputFPS > 0 ? "\(Tuning.outputFPS) fps" : "30 fps"
        let pluginOn = Tuning.usePerfectLoop && Transcoder.perfectLoopAvailable()
        let loopText = pluginOn ? "PerfectLoop 无缝循环" : "无缝循环"
        let fadeText = Tuning.fadeSeconds > 0
            ? String(format: "溶解 %.1f s", Tuning.fadeSeconds) : "溶解关闭"
        stack.addArrangedSubview(caption("默认 1.00× · 整段循环 · \(fpsText) · \(loopText) · \(fadeText)"))
        if !pluginOn {
            stack.addArrangedSubview(caption(Transcoder.perfectLoopRecommendation, tint: .controlAccentColor))
            // 一键安装：点一下 App 自己下载/解压/装依赖/部署，装完立即生效，无需离开 App 或重启。
            let installBtn = NSButton(title: "一键安装 PerfectLoop 插件",
                                      target: self, action: #selector(tuneInstallPluginTapped))
            installBtn.bezelStyle = .rounded
            installBtn.controlSize = .small
            installBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
            installBtn.contentTintColor = .controlAccentColor
            installBtn.isEnabled = !PerfectLoopInstaller.shared.isInstalling
            stack.addArrangedSubview(installBtn)
            installBtn.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
            pluginInstallButton = installBtn
            // 安装进度 / 结果（含占用说明）。装完即时刷新面板，不用重启。
            let status = caption(Transcoder.perfectLoopInstallSteps)
            status.font = .systemFont(ofSize: 10)
            status.maximumNumberOfLines = 3
            status.lineBreakMode = .byWordWrapping
            status.preferredMaxLayoutWidth = width - 40
            stack.addArrangedSubview(status)
            pluginInstallStatus = status
        }

        vc.view = root
        root.layoutSubtreeIfNeeded()
        let h = max(stack.fittingSize.height, 120)
        root.setFrameSize(NSSize(width: width, height: h))
        vc.preferredContentSize = NSSize(width: width, height: h)
        return vc
    }

    @objc private func tuneSpeedChanged(_ sender: NSSlider) {
        Tuning.speed = sender.doubleValue
        tuneSpeedLabel?.stringValue = String(format: "%.2f×", Tuning.speed)
    }
    @objc private func tuneFPSChanged(_ sender: NSPopUpButton) {
        let options = [0, 24, 30, 60]
        let i = sender.indexOfSelectedItem
        guard i >= 0, i < options.count else { return }
        Tuning.outputFPS = options[i]
    }
    @objc private func tuneFadeChanged(_ sender: NSPopUpButton) {
        let options = [0.0, 0.2, 0.4, 0.8]
        let i = sender.indexOfSelectedItem
        guard i >= 0, i < options.count else { return }
        Tuning.fadeSeconds = options[i]
    }
    @objc private func tuneRegenerateTapped() {
        NotificationCenter.default.post(name: Tuning.regenerateRequested, object: nil)
    }
    @objc private func tuneResetTapped() {
        Tuning.reset()
        tuningPop?.contentViewController = makeTuningController()
    }

    /// 一键安装插件：App 内下载/解压/装依赖/部署，装完清缓存即时生效，无需离开 App 或重启。
    @objc private func tuneInstallPluginTapped() {
        pluginInstallButton?.isEnabled = false
        pluginInstallStatus?.textColor = .secondaryLabelColor
        PerfectLoopInstaller.shared.install(
            progress: { [weak self] line in
                self?.pluginInstallStatus?.stringValue = line
            },
            finished: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    // 清缓存后重建面板：底部状态会从「无缝循环」变成「PerfectLoop 无缝循环」，
                    // 安装区整块消失，用户立刻看到已启用。
                    self.tuningPop?.contentViewController = self.makeTuningController()
                case .failure(let err):
                    self.pluginInstallStatus?.stringValue = err.message
                    self.pluginInstallStatus?.textColor = .systemRed
                    self.pluginInstallButton?.isEnabled = true
                }
            }
        )
    }

    private func makeSettingsController() -> NSViewController {
        let vc = NSViewController()
        // 宽度按文档那段说明的阅读舒适度定：一行 22 个汉字上下
        let width: CGFloat = 330
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 220))
        root.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        // 标题
        let title = NSTextField(labelWithString: "设置")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)

        // 存起来：折叠时要靠它重算弹层高度
        settingsVC = vc
        settingsRoot = root
        settingsStack = stack
        pauseSectionRows = []
        rotateSectionRows = []
        // 每次打开都回到收起态（用户要的默认收起）
        pauseExpanded = false
        rotateExpanded = false

        // 外观：深浅色从底栏搬进来（底栏那个位置让给账号头像）
        let lookRow = NSStackView()
        lookRow.orientation = .horizontal
        lookRow.alignment = .centerY
        lookRow.spacing = 8
        let lookLabel = NSTextField(labelWithString: "深色模式")
        lookLabel.font = .systemFont(ofSize: 12.5)
        let lookSwitch = NSSwitch()
        lookSwitch.state = LibraryBackdrop.darkMode ? .on : .off
        lookSwitch.target = self
        lookSwitch.action = #selector(darkModeChanged(_:))
        settingsDarkSwitch = lookSwitch
        lookRow.addArrangedSubview(lookLabel)
        lookRow.addArrangedSubview(lookSwitch)
        stack.addArrangedSubview(lookRow)
        lookRow.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        // 统计开关：名字和说明都是文档里定好的原文，别改
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let label = NSTextField(labelWithString: "发送匿名使用统计")
        label.font = .systemFont(ofSize: 12.5)
        let sw = NSSwitch()
        sw.state = Analytics.shared.isEnabled ? .on : .off
        sw.target = self
        sw.action = #selector(analyticsSwitchChanged(_:))
        settingsSwitch = sw
        row.addArrangedSubview(label)
        row.addArrangedSubview(sw)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        let note = NSTextField(wrappingLabelWithString:
            "帮助我们了解哪些功能好用。仅记录使用次数与成败，不含任何文件名、链接或个人信息，"
            + "可在设置中彻底关闭。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 0
        note.preferredMaxLayoutWidth = width - 32
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        // 窗口透明度：调壁纸库窗口底衬的浓度，拖动立即生效。
        // 语义和录屏里那个滑杆一致：数值越大越透。
        let blurRow = NSStackView()
        blurRow.orientation = .horizontal
        blurRow.alignment = .centerY
        blurRow.spacing = 8
        let blurLabel = NSTextField(labelWithString: "窗口透明度")
        blurLabel.font = .systemFont(ofSize: 12.5)
        let blurSlider = NSSlider(value: Double(LibraryBackdrop.transparency) * 100,
                                  minValue: 0, maxValue: 100,
                                  target: self, action: #selector(blurSliderChanged(_:)))
        blurSlider.controlSize = .small
        let blurPct = NSTextField(labelWithString: "\(Int(round(LibraryBackdrop.transparency * 100)))%")
        blurPct.font = .systemFont(ofSize: 11)
        blurPct.textColor = .secondaryLabelColor
        blurPct.setContentHuggingPriority(.required, for: .horizontal)
        settingsBlurPct = blurPct
        settingsBlurSlider = blurSlider
        blurRow.addArrangedSubview(blurLabel)
        blurRow.addArrangedSubview(blurSlider)
        blurRow.addArrangedSubview(blurPct)
        stack.addArrangedSubview(blurRow)
        blurRow.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        blurSlider.widthAnchor.constraint(equalToConstant: 130).isActive = true

        // 自动暂停：壁纸是背景，前景该独占资源时让路（借鉴 Lively 的暂停策略）。
        // 命中时只停住画面、不关壁纸，条件解除后原地续播。
        // 默认收起：这块三个开关平时不用看，收起来弹层才不挤。
        let pauseHeading = SettingsSectionHeader(title: "自动暂停")
        pauseHeading.onToggle = { [weak self] in self?.toggleSettingsSection(.pause) }
        stack.addArrangedSubview(pauseHeading)
        pauseHeading.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        pauseHeader = pauseHeading

        // 一行「标签 + 开关」。同时登记到所属折叠组，收起时整行隐藏
        func settingsRow(_ title: String, on: Bool, action: Selector,
                         section: SettingsSection) -> NSSwitch {
            let r = NSStackView()
            r.orientation = .horizontal
            r.alignment = .centerY
            r.spacing = 8
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12.5)
            let sw = NSSwitch()
            sw.state = on ? .on : .off
            sw.target = self
            sw.action = action
            r.addArrangedSubview(label)
            r.addArrangedSubview(sw)
            stack.addArrangedSubview(r)
            r.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
            appendRow(r, to: section)
            r.isHidden = true      // 默认收起
            return sw
        }
        pauseFullscreenSwitch = settingsRow("前台全屏时暂停", on: Tuning.pauseOnFullscreen,
                                            action: #selector(pauseFullscreenChanged(_:)),
                                            section: .pause)
        pauseLockSwitch = settingsRow("锁屏 / 息屏时暂停", on: Tuning.pauseOnLock,
                                      action: #selector(pauseLockChanged(_:)), section: .pause)
        dynamicLockSwitch = settingsRow("锁屏动态播放（视频）", on: DynamicLockScreen.isEnabled,
                                        action: #selector(dynamicLockChanged(_:)), section: .pause)
        pauseLowBatterySwitch = settingsRow("低电量模式时暂停", on: Tuning.pauseOnLowBattery,
                                           action: #selector(pauseLowBatteryChanged(_:)),
                                           section: .pause)

        // 自动轮换：什么时候自动换下一张。同样默认收起
        let rotHeading = SettingsSectionHeader(title: "自动轮换")
        rotHeading.onToggle = { [weak self] in self?.toggleSettingsSection(.rotate) }
        stack.addArrangedSubview(rotHeading)
        rotHeading.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        rotateHeader = rotHeading

        rotateSwitch = settingsRow("自动轮换壁纸", on: Rotation.enabled,
                                   action: #selector(rotateEnabledChanged(_:)), section: .rotate)

        // 换的规则：随机 / 顺序
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 8
        let modeLabel = NSTextField(labelWithString: "切换方式")
        modeLabel.font = .systemFont(ofSize: 12.5)
        let modePop = NSPopUpButton(frame: .zero, pullsDown: false)
        modePop.addItems(withTitles: ["随机", "顺序（下一张）"])
        modePop.selectItem(at: Rotation.mode == .random ? 0 : 1)
        modePop.target = self
        modePop.action = #selector(rotateModeChanged(_:))
        modePop.controlSize = .small
        modePop.font = .systemFont(ofSize: 12)
        modeRow.addArrangedSubview(modeLabel)
        modeRow.addArrangedSubview(NSView())      // 中间留白，把下拉推到右边
        modeRow.addArrangedSubview(modePop)
        stack.addArrangedSubview(modeRow)
        modeRow.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        rotateModePop = modePop
        appendRow(modeRow, to: .rotate)
        modeRow.isHidden = true

        // 触发条件（多选）
        rotateLaunchSwitch = settingsRow("每次启动时切换", on: Rotation.onLaunch,
                                         action: #selector(rotateLaunchChanged(_:)), section: .rotate)
        rotateUnlockSwitch = settingsRow("锁屏解锁时切换", on: Rotation.onUnlock,
                                         action: #selector(rotateUnlockChanged(_:)), section: .rotate)
        rotateWakeSwitch = settingsRow("从睡眠唤醒时切换", on: Rotation.onWake,
                                        action: #selector(rotateWakeChanged(_:)), section: .rotate)

        // 定时切换
        let ivRow = NSStackView()
        ivRow.orientation = .horizontal
        ivRow.alignment = .centerY
        ivRow.spacing = 8
        let ivLabel = NSTextField(labelWithString: "定时切换")
        ivLabel.font = .systemFont(ofSize: 12.5)
        let ivPop = NSPopUpButton(frame: .zero, pullsDown: false)
        ivPop.addItems(withTitles: Rotation.intervalOptions.map { $0.title })
        if let idx = Rotation.intervalOptions.firstIndex(where: { abs($0.seconds - Rotation.interval) < 1 }) {
            ivPop.selectItem(at: idx)
        }
        ivPop.target = self
        ivPop.action = #selector(rotateIntervalChanged(_:))
        ivPop.controlSize = .small
        ivPop.font = .systemFont(ofSize: 12)
        ivRow.addArrangedSubview(ivLabel)
        ivRow.addArrangedSubview(NSView())
        ivRow.addArrangedSubview(ivPop)
        stack.addArrangedSubview(ivRow)
        ivRow.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
        rotateIntervalPop = ivPop
        appendRow(ivRow, to: .rotate)
        ivRow.isHidden = true

        updateRotationControlsEnabled()
        refreshSectionHeaders()

        let line = NSBox()
        line.boxType = .separator
        stack.addArrangedSubview(line)
        line.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        // 版本 + 检查更新
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let versionRow = NSStackView()
        versionRow.orientation = .horizontal
        versionRow.alignment = .centerY
        versionRow.spacing = 8
        let verLabel = NSTextField(labelWithString: "Dòng \(ver)（\(build)）")
        verLabel.font = .systemFont(ofSize: 11.5)
        verLabel.textColor = .secondaryLabelColor
        let btn = NSButton(title: "检查更新", target: self, action: #selector(updateButtonTapped))
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.font = .systemFont(ofSize: 11.5)
        settingsAction = btn
        // 反馈入口：平时只有「反馈」两个字，悬停才展开飞书群信息，点击直接进群
        let feedback = FeedbackLink()
        feedback.tipHost = root
        feedbackLink = feedback
        feedback.onOpen = {
            Analytics.shared.track("feedback_open")
            NSWorkspace.shared.open(FeedbackLink.inviteURL)
        }
        versionRow.addArrangedSubview(verLabel)
        versionRow.addArrangedSubview(feedback)
        versionRow.addArrangedSubview(NSView())      // 中间留白，把按钮推到右边
        versionRow.addArrangedSubview(btn)
        stack.addArrangedSubview(versionRow)
        versionRow.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        let status = NSTextField(wrappingLabelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 0
        status.preferredMaxLayoutWidth = width - 32
        settingsStatus = status
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalToConstant: width - 32).isActive = true

        vc.view = root
        // 高度按内容长：弹层不留大片空白
        root.layoutSubtreeIfNeeded()
        let h = max(stack.fittingSize.height, 120)
        root.setFrameSize(NSSize(width: width, height: h))
        vc.preferredContentSize = NSSize(width: width, height: h)
        refreshSettingsState()
        return vc
    }

    @objc private func pauseFullscreenChanged(_ sender: NSSwitch) {
        Tuning.pauseOnFullscreen = sender.state == .on
        refreshSectionHeaders()
    }
    @objc private func pauseLockChanged(_ sender: NSSwitch) {
        Tuning.pauseOnLock = sender.state == .on
        refreshSectionHeaders()
    }
    @objc private func pauseLowBatteryChanged(_ sender: NSSwitch) {
        Tuning.pauseOnLowBattery = sender.state == .on
        refreshSectionHeaders()
    }
    /// 锁屏动态：交给主程序部署视频 + 引导去系统设置选壁纸。
    /// 这里不做任何系统调用，失败也不影响桌面壁纸。
    @objc private func dynamicLockChanged(_ sender: NSSwitch) {
        delegate?.librarySetDynamicLock(sender.state == .on)
    }

    // MARK: 自动轮换

    /// 设置弹层里可折叠的两组
    enum SettingsSection { case pause, rotate }

    private func appendRow(_ view: NSView, to section: SettingsSection) {
        switch section {
        case .pause: pauseSectionRows.append(view)
        case .rotate: rotateSectionRows.append(view)
        }
    }

    private func rows(for section: SettingsSection) -> [NSView] {
        section == .pause ? pauseSectionRows : rotateSectionRows
    }

    /// 展开 / 收起一组：隐藏子行后重算弹层高度，NSPopover 会跟着长高一截
    private func toggleSettingsSection(_ section: SettingsSection) {
        switch section {
        case .pause: pauseExpanded.toggle()
        case .rotate: rotateExpanded.toggle()
        }
        let expanded = section == .pause ? pauseExpanded : rotateExpanded
        for v in rows(for: section) { v.isHidden = !expanded }
        refreshSectionHeaders()
        resizeSettingsPopover()
    }

    /// 收起时在标题右边写一句状态，省得用户为了看一眼还得展开
    private func refreshSectionHeaders() {
        let pauseOn = [Tuning.pauseOnFullscreen, Tuning.pauseOnLock, Tuning.pauseOnLowBattery]
            .filter { $0 }.count
        pauseHeader?.update(summary: pauseOn == 0 ? "全部关闭" : "\(pauseOn) 项开启",
                            expanded: pauseExpanded)

        let rotateSummary: String
        if Rotation.enabled {
            let modeText = Rotation.mode == .random ? "随机" : "顺序"
            rotateSummary = "已开启 · \(modeText)"
        } else {
            rotateSummary = "已关闭"
        }
        rotateHeader?.update(summary: rotateSummary, expanded: rotateExpanded)
    }

    /// 折叠后内容变短，弹层要跟着缩，否则下面空一大片
    private func resizeSettingsPopover() {
        guard let vc = settingsVC, let root = settingsRoot, let stack = settingsStack else { return }
        let width: CGFloat = 330
        root.layoutSubtreeIfNeeded()
        let h = max(stack.fittingSize.height, 120)
        guard abs(root.frame.height - h) > 0.5 else { return }
        root.setFrameSize(NSSize(width: width, height: h))
        // NSPopover 会按这个值自动长高/缩短，箭头仍然指着原来那个按钮
        vc.preferredContentSize = NSSize(width: width, height: h)
    }

    @objc private func rotateEnabledChanged(_ sender: NSSwitch) {
        Rotation.enabled = sender.state == .on
        updateRotationControlsEnabled()
        refreshSectionHeaders()
    }

    @objc private func rotateModeChanged(_ sender: NSPopUpButton) {
        Rotation.mode = sender.indexOfSelectedItem == 0 ? .random : .sequential
        refreshSectionHeaders()
    }

    @objc private func rotateLaunchChanged(_ sender: NSSwitch) {
        Rotation.onLaunch = sender.state == .on
    }

    @objc private func rotateUnlockChanged(_ sender: NSSwitch) {
        Rotation.onUnlock = sender.state == .on
    }

    @objc private func rotateWakeChanged(_ sender: NSSwitch) {
        Rotation.onWake = sender.state == .on
    }

    @objc private func rotateIntervalChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        guard Rotation.intervalOptions.indices.contains(i) else { return }
        Rotation.interval = Rotation.intervalOptions[i].seconds
    }

    /// 总开关关掉时，下面这些子项统一置灰，一眼看出「现在不生效」
    private func updateRotationControlsEnabled() {
        let on = Rotation.enabled
        rotateModePop?.isEnabled = on
        rotateLaunchSwitch?.isEnabled = on
        rotateUnlockSwitch?.isEnabled = on
        rotateWakeSwitch?.isEnabled = on
        rotateIntervalPop?.isEnabled = on
    }

    @objc private func analyticsSwitchChanged(_ sender: NSSwitch) {
        let on = sender.state == .on
        // 关的时候内部会先把 analytics_toggle 发出去、再清队列删 ID
        Analytics.shared.setEnabled(on)
        refreshSettingsState()
    }

    @objc private func blurSliderChanged(_ sender: NSSlider) {
        let v = CGFloat(sender.doubleValue / 100)
        LibraryBackdrop.transparency = v
        settingsBlurPct?.stringValue = "\(Int(round(sender.doubleValue)))%"
        barSlider?.value = v
        barPct?.stringValue = "\(Int(round(sender.doubleValue)))%"
    }

    /// 底栏那个滑杆：和设置弹层里的是同一份值，拖哪个另一个都跟着走
    private func applyTransparency(_ value: CGFloat) {
        LibraryBackdrop.transparency = value
        barPct?.stringValue = "\(Int(round(value * 100)))%"
        settingsBlurSlider?.doubleValue = Double(value) * 100
        settingsBlurPct?.stringValue = "\(Int(round(value * 100)))%"
    }

    @objc private func updateButtonTapped() {
        if case .installing = Updater.shared.state { return }
        if let r = Updater.shared.pendingRelease {
            Updater.shared.download(r)
        } else {
            Updater.shared.check(manual: true)
        }
        refreshSettingsState()
    }

    /// 把 Analytics / Updater 的当前状态画到弹层上
    // MARK: 账号

    /// 点底栏头像：弹账号面板（未登录是登录表单，已登录是个人信息 + 同步状态）
    private func toggleAccount(from anchor: NSView) {
        if let pop = accountPop, pop.isShown {
            pop.performClose(nil)
            return
        }
        guard SyncConfig.isConfigured || SyncCenter.shared.isLoggedIn else {
            let a = NSAlert()
            a.messageText = "同步服务器还没配置"
            a.informativeText = "这个版本没有填 SyncBaseURL，登录会失败。请更新到正式版。"
            a.runModal()
            return
        }
        let vc = AccountViewController()
        let pop = NSPopover()
        vc.hostPopover = pop
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = vc
        pop.delegate = self
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        accountPop = pop
        avatarPill?.refresh()
    }

    @objc private func darkModeChanged(_ sender: NSSwitch) {
        LibraryBackdrop.darkMode = sender.state == .on
    }

    private func refreshSettingsState() {
        settingsSwitch?.state = Analytics.shared.isEnabled ? .on : .off
        settingsDarkSwitch?.state = LibraryBackdrop.darkMode ? .on : .off
        pauseFullscreenSwitch?.state = Tuning.pauseOnFullscreen ? .on : .off
        pauseLockSwitch?.state = Tuning.pauseOnLock ? .on : .off
        pauseLowBatterySwitch?.state = Tuning.pauseOnLowBattery ? .on : .off
        dynamicLockSwitch?.state = DynamicLockScreen.isEnabled ? .on : .off
        rotateSwitch?.state = Rotation.enabled ? .on : .off
        rotateLaunchSwitch?.state = Rotation.onLaunch ? .on : .off
        rotateUnlockSwitch?.state = Rotation.onUnlock ? .on : .off
        rotateWakeSwitch?.state = Rotation.onWake ? .on : .off
        updateRotationControlsEnabled()
        refreshSectionHeaders()
        guard let btn = settingsAction, let status = settingsStatus else { return }

        switch Updater.shared.state {
        case .idle:
            btn.title = "检查更新"
            status.stringValue = Analytics.shared.isEnabled
                ? "统计已开启；关掉后本地队列会清空，不再发送任何请求。"
                : "统计已关闭，不会发送任何数据。"
        case .checking:
            btn.title = "检查中…"
            status.stringValue = "正在向服务器查询最新版本…"
        case .upToDate:
            btn.title = "检查更新"
            status.stringValue = "已经是最新版本了。"
        case .available(let r):
            btn.title = "立即更新"
            status.stringValue = "新版本 \(r.displayName) 可用"
                + (r.sizeText.isEmpty ? "。" : "（\(r.sizeText)）。")
                + (r.notes.isEmpty ? "" : "\n\(r.notes)")
        case .downloading(let r, let p):
            btn.title = "下载中…"
            status.stringValue = "正在下载 \(r.displayName)（\(Int(p * 100))%）…"
        case .ready(let r, _):
            btn.title = "检查更新"
            status.stringValue = "\(r.displayName) 已下载，把 Dòng 拖进「应用程序」即可。"
        case .installing(let r):
            btn.title = "安装中…"
            status.stringValue = "正在把 \(r.displayName) 装进去，装好会自动重开。"
        case .failed(let msg):
            btn.title = "重试"
            status.stringValue = msg
        }
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

        let title = NSTextField(labelWithString: "把视频或图片拖到这里")
        title.font = roundedFont(19, .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let sub = NSTextField(labelWithString: "视频会自动去跳帧、做成无缝循环；图片直接当静态壁纸，\n都会收进壁纸库，点一下就能换上")
        sub.font = .systemFont(ofSize: 11.5)
        sub.textColor = .tertiaryLabelColor
        sub.alignment = .center
        sub.maximumNumberOfLines = 2
        sub.translatesAutoresizingMaskIntoConstraints = false

        let pick = NSButton(title: "或者从电脑里选…", target: self, action: #selector(pickFiles))
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
        // 透明度可能被设置弹层改过，开窗按当前值对齐一次
        let t = LibraryBackdrop.transparency
        barSlider?.value = t
        barPct?.stringValue = "\(Int(round(t * 100)))%"
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
        showTip(text: pill.tipText, anchor: pill)
    }

    /// 头像不是 SettingPill，但气泡长得一样
    private func showTip(text: String, anchor: NSView) {
        guard let shell, let tip = dockTip else { return }
        let r = anchor.convert(anchor.bounds, to: shell)
        tip.show(text: text, above: r, in: shell)
    }

    // MARK: 动作

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        // .image 是抽象类型，多数系统版本会展开成所有图片格式；再把常见具体格式
        // 列一遍，保证 HEIC / WebP / GIF 也能选到。
        panel.allowedContentTypes = [
            .movie, .mpeg4Movie, .quickTimeMovie, .image,
            .jpeg, .png, .heic, .webP, .tiff, .bmp, .gif,
        ]
        panel.message = "选视频或图片（可多选）；图片会做成静态壁纸\n\(Transcoder.perfectLoopRecommendationWithLink)"
        if panel.runModal() == .OK {
            delegate?.libraryAdd(urls: panel.urls)
        }
    }
}
