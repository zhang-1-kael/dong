import Cocoa

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
            attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: hovering ? Brand.accent : Ink.secondary,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
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

        let shown = max(min(max(ratio, 0), 1), 0.02)   // 用一点点也要看得出是「有条」
        let w = bounds.width * CGFloat(shown)
        guard w > 1 else { return }
        let bar = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height),
                               xRadius: 2.5, yRadius: 2.5)
        Brand.accent.setFill()
        bar.fill()
    }
}

// MARK: - 账号面板（点底栏头像弹出来的那个）

final class AccountViewController: NSViewController {

    private enum Mode { case login, register }

    private var mode: Mode = .login

    private var email: AccountFieldBox!
    private var password: AccountFieldBox!
    private var confirm: AccountFieldBox!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var primary: AccountButton!
    private var switcher: AccountButton!
    private var usageText: NSTextField!
    private var usageBar: UsageBar!
    private var syncBlock: NSStackView!
    private var syncBar: UsageBar!
    private var syncDetail: NSTextField!
    private var syncButton: AccountButton!
    private var editStack: NSStackView!
    private var editAvatar: AvatarView!
    private var editName: AccountFieldBox!
    private var editStatus: NSTextField!
    private var editSave: AccountButton!
    private var editRemove: AccountButton!
    private var pendingAvatar: Data?
    private var pwStack: NSStackView!
    private var pwOld: AccountFieldBox!
    private var pwNew: AccountFieldBox!
    private var pwConfirm: AccountFieldBox!
    private var pwStatus: NSTextField!
    private var pwSave: AccountButton!

    // 已登录视图
    private var profileStack: NSStackView!
    private var formStack: NSStackView!
    private var avatarBig: AvatarView!
    private var emailLabel: NSTextField!
    private var profileStatus: NSTextField!

    private let width: CGFloat = 316

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        root.wantsLayer = true
        view = root

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        buildForm(into: stack)
        buildProfile(into: stack)
        buildEdit(into: stack)
        buildPassword(into: stack)

        preferredContentSize = NSSize(width: width, height: stack.fittingSize.height)
        NotificationCenter.default.addObserver(self, selector: #selector(syncChanged),
                                               name: SyncCenter.changed, object: nil)
        applyState()
        // 调试用：VW_ACCOUNT_PW=1 直接摆出「改密码」表单，方便截图核对
        if ProcessInfo.processInfo.environment["VW_ACCOUNT_PW"] != nil {
            showPasswordForm()
        }
        if ProcessInfo.processInfo.environment["VW_ACCOUNT_EDIT"] != nil {
            showEditForm()
        }
    }

    // MARK: 未登录

    private func buildForm(into stack: NSStackView) {
        formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.alignment = .centerX
        formStack.spacing = 9
        formStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(formStack)
        formStack.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        let logoWrap = NSView()
        logoWrap.wantsLayer = true
        logoWrap.layer?.cornerRadius = 17
        logoWrap.layer?.backgroundColor = Brand.accent.withAlphaComponent(0.12).cgColor
        logoWrap.translatesAutoresizingMaskIntoConstraints = false
        formStack.addArrangedSubview(logoWrap)
        NSLayoutConstraint.activate([
            logoWrap.widthAnchor.constraint(equalToConstant: 62),
            logoWrap.heightAnchor.constraint(equalToConstant: 62),
        ])
        let logo = NSImageView()
        logo.image = BrandMark.mark
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logoWrap.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 44),
            logo.heightAnchor.constraint(equalToConstant: 44),
            logo.centerXAnchor.constraint(equalTo: logoWrap.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: logoWrap.centerYAnchor),
        ])
        formStack.setCustomSpacing(12, after: logoWrap)

        titleLabel = NSTextField(labelWithString: "登录 Dòng")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = Ink.primary
        titleLabel.alignment = .center
        formStack.addArrangedSubview(titleLabel)
        formStack.setCustomSpacing(2, after: titleLabel)

        subtitleLabel = NSTextField(labelWithString: "壁纸跟着账号走，换台电脑也在")
        subtitleLabel.font = .systemFont(ofSize: 11.5)
        subtitleLabel.textColor = Ink.tertiary
        subtitleLabel.alignment = .center
        formStack.addArrangedSubview(subtitleLabel)
        formStack.setCustomSpacing(14, after: subtitleLabel)

        email = AccountFieldBox(placeholder: "邮箱")
        formStack.addArrangedSubview(email)
        email.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        password = AccountFieldBox(placeholder: "密码（至少 8 位）", secure: true)
        formStack.addArrangedSubview(password)
        password.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        confirm = AccountFieldBox(placeholder: "再输一次密码", secure: true)
        confirm.isHidden = true
        formStack.addArrangedSubview(confirm)
        confirm.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        primary = AccountButton(title: "登录")
        primary.target = self
        primary.action = #selector(submit)
        primary.keyEquivalent = "\r"
        formStack.addArrangedSubview(primary)
        formStack.setCustomSpacing(6, after: primary)
        primary.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        primary.heightAnchor.constraint(equalToConstant: 36).isActive = true

        statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.isHidden = true
        statusLabel.isHidden = true
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 0
        statusLabel.preferredMaxLayoutWidth = width - 44
        formStack.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        switcher = AccountButton(title: "没有账号？用邮箱注册", kind: .quiet)
        switcher.target = self
        switcher.action = #selector(toggleMode)
        formStack.addArrangedSubview(switcher)

        let note = NSTextField(labelWithString: "密码加盐保存在自己服务器上，读不到原文")
        note.font = .systemFont(ofSize: 10)
        note.textColor = Ink.tertiary
        note.alignment = .center
        formStack.setCustomSpacing(10, after: switcher)
        formStack.addArrangedSubview(note)
    }

    // MARK: 已登录

    private func buildProfile(into stack: NSStackView) {
        profileStack = NSStackView()
        profileStack.orientation = .vertical
        profileStack.alignment = .centerX
        profileStack.spacing = 9
        profileStack.translatesAutoresizingMaskIntoConstraints = false
        profileStack.isHidden = true
        stack.addArrangedSubview(profileStack)
        profileStack.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        avatarBig = AvatarView()
        avatarBig.translatesAutoresizingMaskIntoConstraints = false
        avatarBig.onTap = { [weak self] in self?.showEditForm() }
        profileStack.addArrangedSubview(avatarBig)
        NSLayoutConstraint.activate([
            avatarBig.widthAnchor.constraint(equalToConstant: 64),
            avatarBig.heightAnchor.constraint(equalToConstant: 64),
        ])

        emailLabel = NSTextField(labelWithString: "")
        emailLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        emailLabel.textColor = Ink.primary
        emailLabel.alignment = .center
        emailLabel.lineBreakMode = .byTruncatingMiddle
        profileStack.addArrangedSubview(emailLabel)
        profileStack.setCustomSpacing(2, after: emailLabel)

        profileStatus = NSTextField(wrappingLabelWithString: "")
        profileStatus.font = .systemFont(ofSize: 11)
        profileStatus.textColor = Ink.secondary
        profileStatus.alignment = .center
        profileStatus.maximumNumberOfLines = 0
        profileStatus.preferredMaxLayoutWidth = width - 44
        profileStack.addArrangedSubview(profileStatus)
        profileStatus.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        // 同步进度：只在同步时出现，比一行状态文字直观
        syncBlock = NSStackView()
        syncBlock.orientation = .vertical
        syncBlock.alignment = .centerX
        syncBlock.spacing = 5
        syncBlock.isHidden = true
        syncBlock.translatesAutoresizingMaskIntoConstraints = false
        profileStack.addArrangedSubview(syncBlock)
        syncBlock.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        syncBar = UsageBar()
        syncBar.translatesAutoresizingMaskIntoConstraints = false
        syncBlock.addArrangedSubview(syncBar)
        syncBar.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        syncBar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        syncDetail = NSTextField(labelWithString: "")
        syncDetail.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        syncDetail.textColor = Ink.tertiary
        syncDetail.alignment = .center
        syncBlock.addArrangedSubview(syncDetail)

        usageBar = UsageBar()
        profileStack.addArrangedSubview(usageBar)
        profileStack.setCustomSpacing(4, after: usageBar)
        usageBar.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        usageBar.heightAnchor.constraint(equalToConstant: 5).isActive = true

        usageText = NSTextField(labelWithString: "")
        usageText.font = .systemFont(ofSize: 10.5)
        usageText.textColor = Ink.tertiary
        usageText.alignment = .center
        profileStack.addArrangedSubview(usageText)

        // 主按钮独占一行，下面一行放三个文字入口——四个挤一行会被压掉
        let sync = AccountButton(title: "立即同步")
        sync.target = self
        sync.action = #selector(syncNow)
        syncButton = sync
        profileStack.addArrangedSubview(sync)
        sync.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        sync.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let links = NSStackView()
        links.orientation = .horizontal
        links.spacing = 14
        links.alignment = .centerY
        links.translatesAutoresizingMaskIntoConstraints = false
        profileStack.setCustomSpacing(8, after: sync)
        profileStack.addArrangedSubview(links)

        let edit = AccountButton(title: "编辑资料", kind: .quiet)
        edit.target = self
        edit.action = #selector(showEditForm)
        let pw = AccountButton(title: "改密码", kind: .quiet)
        pw.target = self
        pw.action = #selector(showPasswordForm)
        let out = AccountButton(title: "退出登录", kind: .quiet)
        out.target = self
        out.action = #selector(signOut)
        links.addArrangedSubview(edit)
        links.addArrangedSubview(pw)
        links.addArrangedSubview(out)
        links.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        // 文字按钮没有固有宽度，不给约束会被压成 0
        for b in [edit, pw, out] {
            b.widthAnchor.constraint(equalToConstant: 76).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        links.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        // 文字按钮没有固有宽度，不给约束会被压成 0
        for b in [edit, pw, out] {
            b.widthAnchor.constraint(equalToConstant: 76).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
    }

    // MARK: 编辑资料

    private func buildEdit(into stack: NSStackView) {
        editStack = NSStackView()
        editStack.orientation = .vertical
        editStack.alignment = .centerX
        editStack.spacing = 9
        editStack.isHidden = true
        editStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(editStack)
        editStack.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        let head = NSTextField(labelWithString: "编辑资料")
        head.font = .systemFont(ofSize: 15, weight: .semibold)
        head.textColor = Ink.primary
        editStack.addArrangedSubview(head)

        editAvatar = AvatarView()
        editAvatar.translatesAutoresizingMaskIntoConstraints = false
        editAvatar.onTap = { [weak self] in self?.pickAvatar() }
        editStack.addArrangedSubview(editAvatar)
        NSLayoutConstraint.activate([
            editAvatar.widthAnchor.constraint(equalToConstant: 76),
            editAvatar.heightAnchor.constraint(equalToConstant: 76),
        ])
        editAvatar.initial = "?"

        let tip = NSTextField(labelWithString: "点头像换一张")
        tip.font = .systemFont(ofSize: 10.5)
        tip.textColor = Ink.tertiary
        editStack.addArrangedSubview(tip)
        editStack.setCustomSpacing(12, after: tip)

        editName = AccountFieldBox(placeholder: "昵称（最多 20 个字）")
        editStack.addArrangedSubview(editName)
        editName.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        editStatus = NSTextField(wrappingLabelWithString: "")
        editStatus.font = .systemFont(ofSize: 11)
        editStatus.textColor = .systemRed
        editStatus.alignment = .center
        editStatus.maximumNumberOfLines = 0
        editStatus.preferredMaxLayoutWidth = width - 44
        editStack.addArrangedSubview(editStatus)
        editStatus.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        editSave = AccountButton(title: "保存")
        editSave.target = self
        editSave.action = #selector(saveProfile)
        editStack.addArrangedSubview(editSave)
        editSave.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        editSave.heightAnchor.constraint(equalToConstant: 36).isActive = true

        editRemove = AccountButton(title: "移除头像", kind: .quiet)
        editRemove.target = self
        editRemove.action = #selector(removeAvatar)
        editStack.addArrangedSubview(editRemove)

        let cancel = AccountButton(title: "取消", kind: .quiet)
        cancel.target = self
        cancel.action = #selector(cancelEdit)
        editStack.addArrangedSubview(cancel)
    }

    @objc private func showEditForm() {
        guard SyncCenter.shared.session != nil else { return }
        pendingAvatar = nil
        editStatus.stringValue = ""
        editName.field.stringValue = SyncCenter.shared.profile?.displayName ?? ""
        let nick = (SyncCenter.shared.profile?.displayName.isEmpty == false)
            ? SyncCenter.shared.profile!.displayName
            : (SyncCenter.shared.session?.email ?? "?")
        editAvatar.initial = String(nick.first ?? "?").uppercased()
        if let d = SyncCenter.shared.avatarData, let img = NSImage(data: d) {
            editAvatar.image = img
        } else {
            editAvatar.image = nil
        }
        editRemove.isHidden = !(SyncCenter.shared.profile?.hasAvatar ?? false)
        formStack.isHidden = true
        profileStack.isHidden = true
        pwStack.isHidden = true
        editStack.isHidden = false
        resize()
    }

    @objc private func cancelEdit() {
        editStack.isHidden = true
        applyState()
    }

    @objc private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.message = "选一张图片做头像（会自动裁成方形）"
        guard panel.runModal() == .OK, let url = panel.url,
              let img = NSImage(contentsOf: url) else { return }
        guard let data = Self.squarePNG(img, side: 256) else {
            editStatus.stringValue = "这张图片读不出来"
            return
        }
        pendingAvatar = data
        editAvatar.image = NSImage(data: data)
        editStatus.stringValue = ""
    }

    /// 裁成正方形 + 缩到 256，避免把几 MB 的原图传到服务器
    static func squarePNG(_ image: NSImage, side: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let edge = min(size.width, size.height)
        let crop = NSRect(x: (size.width - edge) / 2, y: (size.height - edge) / 2,
                          width: edge, height: edge)
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: crop, operation: .copy, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    @objc private func saveProfile() {
        guard let session = SyncCenter.shared.session else { return }
        let name = editName.text.trimmingCharacters(in: .whitespaces)
        if name.count > 20 {
            editStatus.stringValue = "昵称最多 20 个字"
            return
        }
        editSave.setEnabled(false)
        editSave.updateTitle("保存中…")
        editStatus.stringValue = ""
        let avatar = pendingAvatar
        let oldName = SyncCenter.shared.profile?.displayName ?? ""

        DispatchQueue.global(qos: .userInitiated).async {
            var error: String?
            if let avatar {
                if case let .failure(e) = AccountAPI.uploadAvatar(token: session.token, png: avatar) {
                    error = "头像保存失败：\(e.localizedDescription)"
                }
            }
            if error == nil, name != oldName {
                if case let .failure(e) = AccountAPI.updateDisplayName(token: session.token, name: name) {
                    error = "昵称保存失败：\(e.localizedDescription)"
                }
            }
            DispatchQueue.main.async {
                self.editSave.setEnabled(true)
                self.editSave.updateTitle("保存")
                if let error {
                    self.editStatus.stringValue = error
                    self.resize()
                    return
                }
                self.pendingAvatar = nil
                SyncCenter.shared.refreshProfile { [weak self] in
                    guard let self else { return }
                    self.editStack.isHidden = true
                    self.applyState()
                }
            }
        }
    }

    @objc private func removeAvatar() {
        guard let session = SyncCenter.shared.session else { return }
        editRemove.setEnabled(false)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.deleteAvatar(token: session.token)
            DispatchQueue.main.async {
                self.editRemove.setEnabled(true)
                if case let .failure(e) = r {
                    self.editStatus.stringValue = e.localizedDescription
                    return
                }
                self.pendingAvatar = nil
                SyncCenter.shared.refreshProfile { [weak self] in
                    guard let self else { return }
                    self.editStack.isHidden = true
                    self.applyState()
                }
            }
        }
    }

    // MARK: 改密码

    private func buildPassword(into stack: NSStackView) {
        pwStack = NSStackView()
        pwStack.orientation = .vertical
        pwStack.alignment = .centerX
        pwStack.spacing = 9
        pwStack.isHidden = true
        pwStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(pwStack)
        pwStack.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        let head = NSTextField(labelWithString: "修改密码")
        head.font = .systemFont(ofSize: 15, weight: .semibold)
        head.textColor = Ink.primary
        head.alignment = .center
        pwStack.addArrangedSubview(head)

        let hint = NSTextField(labelWithString: "改完后其它设备需要重新登录")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = Ink.tertiary
        hint.alignment = .center
        pwStack.addArrangedSubview(hint)
        pwStack.setCustomSpacing(12, after: hint)

        pwOld = AccountFieldBox(placeholder: "当前密码", secure: true)
        pwNew = AccountFieldBox(placeholder: "新密码（至少 8 位）", secure: true)
        pwConfirm = AccountFieldBox(placeholder: "再输一次新密码", secure: true)
        for f in [pwOld!, pwNew!, pwConfirm!] {
            pwStack.addArrangedSubview(f)
            f.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        }

        pwStatus = NSTextField(wrappingLabelWithString: "")
        pwStatus.font = .systemFont(ofSize: 11)
        pwStatus.textColor = .systemRed
        pwStatus.alignment = .center
        pwStatus.maximumNumberOfLines = 0
        pwStatus.preferredMaxLayoutWidth = width - 44
        pwStack.addArrangedSubview(pwStatus)
        pwStatus.widthAnchor.constraint(equalToConstant: width - 44).isActive = true

        pwSave = AccountButton(title: "保存")
        pwSave.target = self
        pwSave.action = #selector(savePassword)
        pwStack.addArrangedSubview(pwSave)
        pwSave.widthAnchor.constraint(equalToConstant: width - 44).isActive = true
        pwSave.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let cancel = AccountButton(title: "取消", kind: .quiet)
        cancel.target = self
        cancel.action = #selector(cancelPassword)
        pwStack.addArrangedSubview(cancel)
    }

    @objc private func showPasswordForm() {
        pwStatus.stringValue = ""
        pwOld.field.stringValue = ""
        pwNew.field.stringValue = ""
        pwConfirm.field.stringValue = ""
        profileStack.isHidden = true
        formStack.isHidden = true
        pwStack.isHidden = false
        resize()
    }

    @objc private func cancelPassword() {
        pwStack.isHidden = true
        applyState()
        // 调试用：VW_ACCOUNT_PW=1 直接摆出「改密码」表单，方便截图核对
        if ProcessInfo.processInfo.environment["VW_ACCOUNT_PW"] != nil {
            showPasswordForm()
        }
        if ProcessInfo.processInfo.environment["VW_ACCOUNT_EDIT"] != nil {
            showEditForm()
        }
    }

    @objc private func savePassword() {
        guard let session = SyncCenter.shared.session else { return }
        let old = pwOld.text
        let new = pwNew.text
        pwStatus.stringValue = ""
        guard !old.isEmpty else { pwStatus.stringValue = "请输入当前密码"; return }
        guard new.count >= 8 else { pwStatus.stringValue = "新密码至少 8 位"; return }
        guard new == pwConfirm.text else { pwStatus.stringValue = "两次输入的新密码不一样"; return }

        pwSave.setEnabled(false)
        pwSave.updateTitle("保存中…")
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.changePassword(token: session.token, old: old, new: new)
            DispatchQueue.main.async {
                self.pwSave.setEnabled(true)
                self.pwSave.updateTitle("保存")
                switch r {
                case .success:
                    self.pwStack.isHidden = true
                    self.applyState()
                    let a = NSAlert()
                    a.messageText = "密码已修改"
                    a.informativeText = "其它设备上的登录已失效，需要重新登录。这台电脑不用。"
                    a.runModal()
                case let .failure(e):
                    self.pwStatus.stringValue = e.localizedDescription
                    self.resize()
                }
            }
        }
    }

    // MARK: 状态

    @objc private func syncChanged() {
        if isViewLoaded { applyState() }
    }

    private func applyState() {
        let session = SyncCenter.shared.session
        let signedIn = session != nil
        profileStack?.isHidden = !signedIn || !(pwStack?.isHidden ?? true) || !(editStack?.isHidden ?? true)
        formStack?.isHidden = signedIn

        if let s = session {
            let p = SyncCenter.shared.profile
            let nickname = (p?.displayName.isEmpty == false) ? p!.displayName : ""
            emailLabel?.stringValue = nickname.isEmpty ? s.email : nickname
            if !nickname.isEmpty {
                // 昵称有了，邮箱用小字挂下面一眼还能认人
                emailLabel?.toolTip = s.email
            }
            avatarBig?.initial = String((nickname.isEmpty ? s.email : nickname).first ?? "?").uppercased()
            if let d = SyncCenter.shared.avatarData, let img = NSImage(data: d) {
                avatarBig?.image = img
            } else {
                avatarBig?.image = nil
            }
            let st = SyncCenter.shared.status
            if let p = SyncCenter.shared.progress, st.isBusy {
                syncBlock?.isHidden = false
                syncBar?.ratio = p.fraction
                let pct = Int((p.fraction * 100).rounded())
                let doneMB = Self.mb(p.bytesDone)
                let totalMB = Self.mb(p.bytesTotal)
                syncDetail?.stringValue = "\(pct)%  ·  \(doneMB) / \(totalMB)  ·  第 \(max(p.done, 1))/\(p.total) 张"
            } else {
                syncBlock?.isHidden = true
            }
            switch st {
            case .idle:
                syncButton?.setEnabled(true)
                syncButton?.updateTitle("立即同步")
                profileStatus?.stringValue = "已登录 · 壁纸改动会自动同步"
                profileStatus?.textColor = Ink.secondary
                profileStatus?.font = .systemFont(ofSize: 11)
            case .syncing(let t):
                syncButton?.setEnabled(false)
                syncButton?.updateTitle("同步中…")
                profileStatus?.stringValue = t
                profileStatus?.textColor = Ink.primary
                profileStatus?.font = .systemFont(ofSize: 12.5, weight: .medium)
            case .done:
                syncButton?.setEnabled(true)
                syncButton?.updateTitle("立即同步")
                profileStatus?.stringValue = "已同步"
                profileStatus?.textColor = Ink.secondary
            case .failed(let t):
                syncButton?.setEnabled(true)
                syncButton?.updateTitle("立即同步")
                profileStatus?.stringValue = t
                profileStatus?.textColor = .systemRed
            case .signedOut:
                profileStatus?.stringValue = ""
            }
            usageBar?.isHidden = true
            usageText?.isHidden = true
            SyncCenter.shared.refreshAccount { result in
                guard case let .success(me) = result else { return }
                let used = Double(me.usedBytes), quota = Double(max(me.quotaBytes, 1))
                self.usageBar?.isHidden = false
                self.usageText?.isHidden = false
                self.usageBar?.ratio = used / quota
                self.usageText?.stringValue = "云端 \(Self.sizeText(me.usedBytes)) / \(Self.sizeText(me.quotaBytes))"
            }
        }
        resize()
    }

    private func resize() {
        statusLabel?.isHidden = statusLabel?.stringValue.isEmpty ?? true
        editStatus?.isHidden = editStatus?.stringValue.isEmpty ?? true
        pwStatus?.isHidden = pwStatus?.stringValue.isEmpty ?? true
        guard let stack = view.subviews.first as? NSStackView else { return }
        stack.layoutSubtreeIfNeeded()
        let h = max(stack.fittingSize.height, 120)
        view.frame = NSRect(x: 0, y: 0, width: width, height: h)
        preferredContentSize = NSSize(width: width, height: h)
    }

    private static func mb(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
        }
        return String(format: "%.0f MB", Double(bytes) / 1024 / 1024)
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }

    // MARK: 动作

    @objc private func toggleMode() {
        mode = mode == .login ? .register : .login
        let reg = mode == .register
        titleLabel.stringValue = reg ? "注册 Dòng 账号" : "登录 Dòng"
        subtitleLabel.stringValue = reg ? "注册完，这台电脑的壁纸就会开始上传" : "壁纸跟着账号走，换台电脑也在"
        primary.updateTitle(reg ? "注册并开始同步" : "登录")
        switcher.updateTitle(reg ? "已经有账号，去登录" : "没有账号？用邮箱注册")
        confirm.isHidden = !reg
        statusLabel.stringValue = ""
        resize()
    }

    @objc private func submit() {
        let mail = email.text.trimmingCharacters(in: .whitespaces)
        let pass = password.text
        statusLabel.stringValue = ""
        guard mail.contains("@") else { statusLabel.stringValue = "邮箱看起来不对"; return }
        guard pass.count >= 8 else { statusLabel.stringValue = "密码至少 8 位"; return }
        if mode == .register, confirm.text != pass {
            statusLabel.stringValue = "两次输入的密码不一样"
            return
        }

        primary.setEnabled(false)
        primary.updateTitle("请稍候…")
        statusLabel.stringValue = ""
        let isReg = mode == .register
        DispatchQueue.global(qos: .userInitiated).async {
            let r = isReg ? AccountAPI.register(email: mail, password: pass)
                          : AccountAPI.login(email: mail, password: pass)
            DispatchQueue.main.async {
                self.primary.setEnabled(true)
                switch r {
                case let .success(s):
                    SyncCenter.shared.signIn(s)
                    self.applyState()
                case let .failure(e):
                    self.primary.updateTitle(isReg ? "注册并开始同步" : "登录")
                    self.statusLabel.stringValue = e.localizedDescription
                    self.resize()
                }
            }
        }
    }

    @objc private func syncNow() {
        SyncCenter.shared.syncNow()
    }

    @objc private func signOut() {
        let a = NSAlert()
        a.messageText = "退出登录？"
        a.informativeText = "已同步到云端的壁纸不会删，本机的也留着。之后不再自动同步。"
        a.addButton(withTitle: "退出登录")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        SyncCenter.shared.signOut()
        applyState()
    }
}
