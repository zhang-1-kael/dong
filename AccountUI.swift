import Cocoa

// 账号相关的共用控件。原来这些都塞在 AccountPopover.swift 里，
// 现在弹层换成了 AccountWindow，控件单独放一个文件，窗口和底栏都能用。


/// 底栏最右边那颗头像。
///
/// 没登录：一个人形剪影，点了开账号面板。
/// 已登录：品牌橙渐变圆 + 邮箱首字母，一眼知道「这是我自己」。
final class AvatarPill: NSView {

    static let side: CGFloat = 30

    var onTap: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private let glass = GlassView(radius: 9, tint: 0.04, material: .popover, chrome: .clear)
    private let circle = NSView()
    private let grad = CAGradientLayer()
    private let avatarImage = CALayer()
    private let initial = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    /// 同步时绕着头像转的一圈进度环：不打开面板也能看出在动
    private let ringTrack = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var hovered = false { didSet { restyle() } }
    private var tracking: NSTrackingArea?
    private var inkColor: NSColor = .white

    init() {
        super.init(frame: .zero)
        wantsLayer = true          // 进度环要挂在 self.layer 上，没这行等于没画
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        circle.wantsLayer = true
        circle.layer?.cornerRadius = 11
        circle.layer?.masksToBounds = true
        circle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)
        grad.startPoint = CGPoint(x: 0.5, y: 1)
        grad.endPoint = CGPoint(x: 0.5, y: 0)
        grad.colors = [Brand.gradTop.cgColor, Brand.gradBottom.cgColor]
        circle.layer?.addSublayer(grad)

        avatarImage.contentsGravity = .resizeAspectFill
        avatarImage.masksToBounds = true
        avatarImage.isHidden = true
        circle.layer?.addSublayer(avatarImage)

        initial.font = .systemFont(ofSize: 11.5, weight: .semibold)
        initial.textColor = .white
        initial.alignment = .center
        initial.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(initial)

        iconView.imageScaling = .scaleNone
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // 头像本身是橙的，进度弧用白色才看得清；底下垫一圈淡轨表示「总共多长」
        ringTrack.fillColor = NSColor.clear.cgColor
        ringTrack.strokeColor = NSColor.white.withAlphaComponent(0.20).cgColor
        ringTrack.lineWidth = 1.8
        ringTrack.strokeStart = 0
        ringTrack.strokeEnd = 1
        ringTrack.isHidden = true
        layer?.addSublayer(ringTrack)

        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        ring.lineWidth = 1.8
        ring.lineCap = .round
        ring.strokeStart = 0
        ring.strokeEnd = 0
        ring.isHidden = true
        layer?.addSublayer(ring)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: centerYAnchor),
            circle.widthAnchor.constraint(equalToConstant: 22),
            circle.heightAnchor.constraint(equalToConstant: 22),
            initial.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            initial.centerYAnchor.constraint(equalTo: circle.centerYAnchor, constant: -0.5),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
        // 登录 / 退出 / 同步状态变化都跟着换头像
        NotificationCenter.default.addObserver(self, selector: #selector(syncChanged),
                                               name: SyncCenter.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func syncChanged() {
        DispatchQueue.main.async { self.refresh() }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grad.frame = circle.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        avatarImage.frame = circle.bounds
        avatarImage.cornerRadius = circle.bounds.width / 2
        CATransaction.commit()
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let r: CGFloat = 12.6
        let path = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2),
                          transform: nil)
        // 从 12 点方向顺时针画
        let rot = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: -.pi / 2)
            .translatedBy(x: -c.x, y: -c.y)
        ring.path = path
        ring.setAffineTransform(rot)
        ringTrack.path = path
        ringTrack.setAffineTransform(rot)
        CATransaction.commit()
    }

    func refresh() {
        let session = SyncCenter.shared.session
        if let s = session {
            let nick = SyncCenter.shared.profile?.displayName ?? ""
            let seed = nick.isEmpty ? s.email : nick
            circle.isHidden = false
            iconView.isHidden = true
            initial.stringValue = String(seed.first ?? "?").uppercased()
            if let d = SyncCenter.shared.avatarData, let img = NSImage(data: d) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                avatarImage.contents = img
                avatarImage.isHidden = false
                initial.isHidden = true
                CATransaction.commit()
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                avatarImage.isHidden = true
                initial.isHidden = false
                CATransaction.commit()
            }
        } else {
            circle.isHidden = true
            iconView.isHidden = false
            restyle()
        }
        restyle()
    }

    /// 底栏图标统一走固定亮墨色，深浅色切换后由外壳调这个方法
    func refreshAppearance(ink: NSColor) {
        inkColor = ink
        refresh()
    }

    private func restyle() {
        // 进度环：只在同步中显示
        if let p = SyncCenter.shared.progress, SyncCenter.shared.status.isBusy {
            ring.isHidden = false
            ringTrack.isHidden = false
            ringTrack.isHidden = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.strokeEnd = CGFloat(min(max(p.fraction, 0.02), 1))
            CATransaction.commit()
        } else {
            ring.isHidden = true
            ringTrack.isHidden = true
        }
        if SyncCenter.shared.session == nil {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let base = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "账号") {
                iconView.image = base.withSymbolConfiguration(cfg) ?? base
            }
            iconView.contentTintColor = inkColor
        }
        glass.setColor(.labelColor)
        glass.setTint(hovered ? 0.10 : 0.03)
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

    func clearHover() {
        guard hovered else { return }
        hovered = false
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }
}

// MARK: - 头像视图（有图显示图，没图显示品牌渐变 + 首字母）

final class AvatarView: NSView {
    var onTap: (() -> Void)?
    var initial: String = "" {
        didSet { initialLabel.stringValue = initial }
    }
    var image: NSImage? {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.contents = image
            imageLayer.isHidden = (image == nil)
            initialLabel.isHidden = (image != nil)
            CATransaction.commit()
        }
    }

    private let gradient = CAGradientLayer()
    private let imageLayer = CALayer()
    private let initialLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.colors = [Brand.gradTop.cgColor, Brand.gradBottom.cgColor]
        layer?.addSublayer(gradient)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.isHidden = true
        layer?.addSublayer(imageLayer)

        initialLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        initialLabel.textColor = .white
        initialLabel.alignment = .center
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initialLabel)
        NSLayoutConstraint.activate([
            initialLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        imageLayer.frame = bounds
        imageLayer.cornerRadius = bounds.width / 2
        layer?.cornerRadius = bounds.width / 2
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) { onTap?() }

    override func resetCursorRects() {
        if onTap != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

// MARK: - 密码框（系统默认禁止粘贴，这里放开）

/// `NSSecureTextField` 默认吃掉 Cmd+V，右键菜单也没有「粘贴」。
/// 密码管理器生成的长密码没法手打，必须支持粘贴。
final class PasteableSecureField: NSSecureTextField {

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        if let editor = currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: editor.selectedRange())
        } else {
            stringValue += text
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: "粘贴", action: #selector(paste(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        if let editor = currentEditor() as? NSTextView, editor.selectedRange().length > 0 {
            let cut = NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "")
            cut.target = editor
            menu.insertItem(cut, at: 0)
            let copy = NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "")
            copy.target = editor
            menu.insertItem(copy, at: 1)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - 输入框（自绘圆角底，系统 bezel 在深色玻璃上太方）

final class AccountFieldBox: NSView {
    let field: NSTextField

    init(placeholder: String, secure: Bool = false) {
        field = secure ? PasteableSecureField() : NSTextField()
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = placeholder
        field.stringValue = ""
        field.isAutomaticTextCompletionEnabled = false
        field.font = .systemFont(ofSize: 13)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var text: String { field.stringValue }

    func refreshAppearance() {
        layer?.backgroundColor = Ink.inputFill.cgColor
        layer?.borderColor = Ink.inputEdge.cgColor
    }
}

// MARK: - 主按钮

final class AccountButton: NSButton {

    enum Kind { case primary, quiet }

    private let kind: Kind
    /// 文字按钮默认居中；表单里的链接要跟左对齐的字段配对
    var titleAlignment: NSTextAlignment = .center { didSet { restyle() } }
    private var hovering = false { didSet { restyle() } }
    private var tracking: NSTrackingArea?

    init(title: String, kind: Kind = .primary) {
        self.kind = kind
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 9
        font = .systemFont(ofSize: 13, weight: .medium)
        translatesAutoresizingMaskIntoConstraints = false
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 36)
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        restyle()
    }

    func updateTitle(_ t: String) {
        title = t
        restyle()
    }

    private func restyle() {
        switch kind {
        case .primary:
            let base = hovering ? Brand.gradBottom : Brand.accent
            layer?.backgroundColor = (isEnabled ? base : base.withAlphaComponent(0.45)).cgColor
            contentTintColor = .white
            attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.7),
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            ])
        case .quiet:
            layer?.backgroundColor = NSColor.clear.cgColor
            let para = NSMutableParagraphStyle()
            para.alignment = titleAlignment
            attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: hovering ? Brand.accent : Ink.secondary,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                .paragraphStyle: para,
            ])
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}

// MARK: - 用量条

final class UsageBar: NSView {
    var ratio: Double = 0 { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 5) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5)
        Ink.fill.setFill()
        track.fill()

        guard ratio > 0.001 else { return }            // 一点都没用就别画，一条橙点看着像故障
        let shown = max(min(ratio, 1), 0.02)           // 用了一点点也要看得出是「有条」
        let w = bounds.width * CGFloat(shown)
        guard w > 1 else { return }
        let bar = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height),
                               xRadius: 2.5, yRadius: 2.5)
        Brand.accent.setFill()
        bar.fill()
    }
}
