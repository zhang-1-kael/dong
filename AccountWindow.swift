import Cocoa

// MARK: - 闭包按钮

/// `AccountButton` 只认 target/action，设备行里的「退出」需要带着那台设备走，
/// 用闭包最省事。
final class ClosureButton: AccountButton {
    private let fire: () -> Void

    init(title: String, kind: AccountButton.Kind = .quiet, onTap: @escaping () -> Void) {
        self.fire = onTap
        super.init(title: title, kind: kind)
        target = self
        action = #selector(run)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { fire() }
}

// MARK: - 一行设置

/// 账号窗口里的「标题 —— 值 ›」行。点击整行触发，悬停有淡淡一层底。
final class AccountRow: NSView {

    var onTap: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let chevron = NSTextField(labelWithString: "›")
    private var tracking: NSTrackingArea?
    private var hovered = false { didSet { needsDisplay = true } }
    private let clickable: Bool
    private let hairline: Bool

    init(title: String,
         value: String = "",
         valueColor: NSColor = Ink.tertiary,
         titleColor: NSColor = Ink.primary,
         showsChevron: Bool = true,
         clickable: Bool = true,
         hairline: Bool = true) {
        self.clickable = clickable
        self.hairline = hairline
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5)
        titleLabel.textColor = titleColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.stringValue = value
        valueLabel.font = .systemFont(ofSize: 11.5)
        valueLabel.textColor = valueColor
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        chevron.font = .systemFont(ofSize: 13)
        chevron.textColor = Ink.tertiary
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            chevron.widthAnchor.constraint(equalToConstant: showsChevron && clickable ? 10 : 0),
            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -5),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])
        chevron.isHidden = !(showsChevron && clickable)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 值要异步拿到（恢复码状态、设备台数），所以要能事后改
    func setValue(_ text: String, color: NSColor = Ink.tertiary) {
        valueLabel.stringValue = text
        valueLabel.textColor = color
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered && clickable {
            Ink.fill.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: -6, dy: 0), xRadius: 5, yRadius: 5).fill()
        }
        if hairline {
            Ink.hair.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
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

    override func mouseEntered(with event: NSEvent) { if clickable { hovered = true } }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { if clickable { onTap?() } }

    override func resetCursorRects() {
        if clickable { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

// MARK: - 账号窗口

/// 账号窗口：**固定 400 × 432，不可拉伸**，单页分区，没有侧栏。
///
/// 为什么不做成大设置窗口：用户明确要求「不能占太多位置、要简洁」。
/// 所以只保留账号本身要用的东西，深色模式/统计这些仍留在原来的齿轮弹层里。
final class AccountWindowController: NSWindowController {

    let page = AccountPageController()

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                             width: AccountPageController.width,
                                             height: AccountPageController.height),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = .windowBackgroundColor
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: w)
        w.contentViewController = page
        w.setContentSize(NSSize(width: AccountPageController.width,
                                height: AccountPageController.height))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 贴着主窗口右下角弹出；越界就夹回屏幕内。
    func present(near parent: NSWindow?) {
        page.reload()
        guard let w = window else { return }
        if let p = parent {
            let f = p.frame
            var x = f.maxX - w.frame.width - 28
            var y = f.minY + 72
            if let scr = p.screen?.visibleFrame {
                x = max(scr.minX + 12, min(x, scr.maxX - w.frame.width - 12))
                y = max(scr.minY + 12, min(y, scr.maxY - w.frame.height - 12))
            }
            w.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            w.center()
        }
        showWindow(nil)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 调试用：把窗口内容拍成图片
    func debugSnapshot(to path: String) {
        guard let v = window?.contentView else { return }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        print("[account] shot size=\(v.bounds.size)")
    }
}

// MARK: - 页面内容

final class AccountPageController: NSViewController {

    static let width: CGFloat = 400
    static let height: CGFloat = 432

    private enum Page { case auth, profile, edit, password, devices, recovery, reset }

    private var page: Page = .auth
    private let contentWidth: CGFloat = 400 - 44

    // 登录 / 注册
    private var authEmail: AccountFieldBox?
    private var authPassword: AccountFieldBox?
    private var authConfirm: AccountFieldBox?
    private var authStatus: NSTextField?
    private var authButton: AccountButton?
    private var authSwitch: AccountButton?
    private var authTitle: NSTextField?
    private var authSubtitle: NSTextField?
    private var isRegister = false

    // 注册验证码（服务端没开通发信时整行隐藏，只保留域名真实性校验）
    private var authCode: AccountFieldBox?
    private var authSend: AccountButton?
    private var authCodeRow: NSView?
    private var mailUnavailable = false
    /// 只问一次服务端「发信开没开」
    private static var mailKnown = false
    private var codeLeft = 0
    private var codeTimer: Timer?

    // 已登录主页
    private var profAvatar: AvatarView?
    private var profName: NSTextField?
    private var profEmail: NSTextField?
    private var profStatus: NSTextField?
    private var syncSummary: NSTextField?
    private var syncQuota: NSTextField?
    private var syncBar: UsageBar?
    private var syncFoot: NSTextField?
    private var syncButton: AccountButton?

    // 编辑资料
    private var editAvatar: AvatarView?
    private var editName: AccountFieldBox?
    private var editStatus: NSTextField?
    private var editSave: AccountButton?
    private var editRemove: AccountButton?
    private var pendingAvatar: Data?

    // 改密码
    private var pwOld: AccountFieldBox?
    private var pwNew: AccountFieldBox?
    private var pwConfirm: AccountFieldBox?
    private var pwStatus: NSTextField?
    private var pwSave: AccountButton?

    // 登录设备 / 恢复码
    private var sessions: [AccountAPI.SessionInfo] = []
    private var sessionsLoaded = false
    private var sessionsLoading = false
    private var sessionsError: String?
    private var recovery: AccountAPI.RecoveryState?
    private var recoveryLoaded = false
    private var recoveryRow: AccountRow?
    /// 刚生成、还没离开页面的明文恢复码（离开就丢，服务端也只存哈希）
    private var freshCode: String?

    // 重设密码
    private var resetEmail: AccountFieldBox?
    private var resetCode: AccountFieldBox?
    private var resetPassword: AccountFieldBox?
    private var resetConfirm: AccountFieldBox?
    private var resetStatus: NSTextField?
    private var resetButton: AccountButton?
    /// 从登录页跳过来时，把已经填好的邮箱带过去
    private var pendingEmail = ""

    // 用量缓存
    private var usedBytes: Int64 = 0
    private var quotaBytes: Int64 = 0
    private var didForceDebugPage = false

    // MARK: 生命周期

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        v.wantsLayer = true
        view = v
        NotificationCenter.default.addObserver(self, selector: #selector(syncChanged),
                                               name: SyncCenter.changed, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
    }

    @objc private func syncChanged() {
        DispatchQueue.main.async {
            switch self.page {
            case .profile: self.updateLive()
            case .auth: if SyncCenter.shared.isLoggedIn { self.page = .profile; self.render() }
            default: break
            }
        }
    }

    /// 每次打开窗口都重算一次该显示哪一页
    func reload() {
        if let p = ProcessInfo.processInfo.environment["VW_ACCOUNT_PAGE"], !didForceDebugPage {
            switch p {
            case "edit": page = .edit
            case "password": page = .password
            case "devices": page = .devices
            case "recovery": page = .recovery
            case "reset": page = .reset
            case "profile": page = .profile
            case "auth": page = .auth
            case "register": page = .auth; isRegister = true
            case "register": page = .auth; isRegister = true
            default: break
            }
            didForceDebugPage = true
        } else if !SyncCenter.shared.isLoggedIn {
            page = .auth
        } else if page == .auth {
            page = .profile
        }
        render()
        // 兜底：进到主页时若这一轮还没同步过，主动拉一次——
        // 用户不必知道「立即同步」这个按钮的存在。
        if page == .profile,
           SyncCenter.shared.lastReport == nil,
           SyncCenter.shared.status == .idle {
            SyncCenter.shared.syncNow()
        }
    }

    /// 回到主页（子页面的「返回」和保存成功后都走这里）
    @objc private func goProfile() {
        freshCode = nil
        guard SyncCenter.shared.isLoggedIn else { page = .auth; render(); return }
        page = .profile
        render()
    }

    // MARK: 渲染

    private func render() {
        view.subviews.forEach { $0.removeFromSuperview() }
        clearRefs()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
        ])
        if page == .auth {
            // 登录表单内容少，垂直居中比堆在顶上好看
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 6).isActive = true
        } else {
            // 顶栏是透明的，标题栏压在上面，所以从 34 起排，避开红绿灯
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 34).isActive = true
        }

        switch page {
        case .auth:
            buildAuth(into: stack)
        case .profile: buildProfile(into: stack)
        case .edit: buildEdit(into: stack)
        case .password: buildPassword(into: stack)
        case .devices: buildDevices(into: stack)
        case .recovery: buildRecovery(into: stack)
        case .reset: buildReset(into: stack)
        }

        if page == .profile { loadUsage() }
    }

    private func clearRefs() {
        authEmail = nil; authPassword = nil; authConfirm = nil; authStatus = nil
        authButton = nil; authSwitch = nil; authTitle = nil; authSubtitle = nil
        authCode = nil; authSend = nil; authCodeRow = nil
        profAvatar = nil; profName = nil; profEmail = nil; profStatus = nil
        syncSummary = nil; syncQuota = nil; syncBar = nil; syncFoot = nil; syncButton = nil
        editAvatar = nil; editName = nil; editStatus = nil; editSave = nil; editRemove = nil
        pwOld = nil; pwNew = nil; pwConfirm = nil; pwStatus = nil; pwSave = nil
    }

    // MARK: 小工具

    private func fullWidth(_ v: NSView, in stack: NSStackView, spacing: CGFloat = 0) {
        stack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        if spacing > 0 { stack.setCustomSpacing(spacing, after: v) }
    }

    private func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor = Ink.primary, align: NSTextAlignment = .left) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .systemFont(ofSize: size, weight: weight)
        t.textColor = color
        t.alignment = align
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    private func hairline() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = Ink.hair.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    /// 分区之间的分隔线。线下面必须留白，否则分区标题会贴着线，看着像上一条的附属
    private func divider(in stack: NSStackView, after: CGFloat = 11) {
        let h = hairline()
        fullWidth(h, in: stack)
        stack.setCustomSpacing(after, after: h)
    }

    private func sectionLabel(_ s: String) -> NSTextField {
        let t = text(s, size: 10.5, color: Ink.tertiary)
        t.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return t
    }

    private func backHeader(_ title: String, in stack: NSStackView,
                            back action: Selector = #selector(goProfile)) {
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(holder)
        holder.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        holder.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.setCustomSpacing(12, after: holder)

        let back = AccountButton(title: "‹ 返回", kind: .quiet)
        back.target = self
        back.action = action
        back.titleAlignment = .left
        back.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(back)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            back.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 52),
            back.heightAnchor.constraint(equalToConstant: 22),
        ])

        let t = text(title, size: 13, weight: .medium)
        t.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(t)
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 8),
            t.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
    }

    // MARK: 登录 / 注册

    private func buildAuth(into stack: NSStackView) {
        let logoWrap = NSView()
        logoWrap.wantsLayer = true
        logoWrap.layer?.cornerRadius = 15
        logoWrap.layer?.backgroundColor = Brand.accent.withAlphaComponent(0.12).cgColor
        logoWrap.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(logoWrap)
        NSLayoutConstraint.activate([
            logoWrap.widthAnchor.constraint(equalToConstant: 56),
            logoWrap.heightAnchor.constraint(equalToConstant: 56),
        ])

        if let mark = BrandMark.mark {
            let logo = NSImageView()
            logo.image = mark
            logo.imageScaling = .scaleProportionallyUpOrDown
            logo.translatesAutoresizingMaskIntoConstraints = false
            logoWrap.addSubview(logo)
            NSLayoutConstraint.activate([
                logo.widthAnchor.constraint(equalToConstant: 40),
                logo.heightAnchor.constraint(equalToConstant: 40),
                logo.centerXAnchor.constraint(equalTo: logoWrap.centerXAnchor),
                logo.centerYAnchor.constraint(equalTo: logoWrap.centerYAnchor),
            ])
        }
        stack.setCustomSpacing(12, after: logoWrap)

        let title = text(isRegister ? "创建账号" : "登录 Dòng", size: 16, weight: .semibold)
        stack.addArrangedSubview(title)
        authTitle = title
        stack.setCustomSpacing(3, after: title)

        let sub = text("壁纸跟着账号走，换台电脑也在", size: 11.5, color: Ink.tertiary)
        stack.addArrangedSubview(sub)
        authSubtitle = sub
        stack.setCustomSpacing(16, after: sub)

        let email = AccountFieldBox(placeholder: "邮箱")
        fullWidth(email, in: stack, spacing: 8)
        authEmail = email

        if isRegister && !Self.mailKnown { loadMailConfig() }

        // 注册时要证明这个邮箱真能收信：验证码一行。服务端没开发信就整行不出现。
        if isRegister && !mailUnavailable {
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            row.heightAnchor.constraint(equalToConstant: 34).isActive = true
            stack.setCustomSpacing(8, after: row)
            authCodeRow = row

            let code = AccountFieldBox(placeholder: "邮箱验证码")
            code.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(code)
            authCode = code

            let send = AccountButton(title: "发送验证码", kind: .quiet)
            send.target = self
            send.action = #selector(sendEmailCode)
            send.translatesAutoresizingMaskIntoConstraints = false
            send.titleAlignment = .right
            row.addSubview(send)
            authSend = send

            NSLayoutConstraint.activate([
                code.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                code.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                code.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -10),
                send.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                send.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                send.widthAnchor.constraint(equalToConstant: 92),
                send.heightAnchor.constraint(equalToConstant: 34),
            ])
            applyCodeCountdown()
        }

        let password = AccountFieldBox(placeholder: "密码（至少 8 位）", secure: true)
        password.field.target = self
        password.field.action = #selector(doAuth)
        fullWidth(password, in: stack, spacing: 8)
        authPassword = password

        let confirm = AccountFieldBox(placeholder: "再输一次密码", secure: true)
        confirm.isHidden = !isRegister
        fullWidth(confirm, in: stack, spacing: 8)
        authConfirm = confirm

        let status = text("", size: 11, color: .systemRed)
        status.maximumNumberOfLines = 0
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = contentWidth
        status.isHidden = true
        fullWidth(status, in: stack, spacing: 4)
        authStatus = status

        let primary = AccountButton(title: isRegister ? "注册并开始同步" : "登录")
        primary.target = self
        primary.action = #selector(doAuth)
        fullWidth(primary, in: stack)
        primary.heightAnchor.constraint(equalToConstant: 36).isActive = true
        authButton = primary
        stack.setCustomSpacing(10, after: primary)

        // 左边切换注册，右边忘记密码——忘了密码的人就在这一页，别让他再去找
        let linkRow = NSView()
        linkRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(linkRow)
        linkRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        linkRow.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let switcher = AccountButton(title: isRegister ? "已经有账号，去登录" : "没有账号？用邮箱注册",
                                     kind: .quiet)
        switcher.target = self
        switcher.action = #selector(toggleRegister)
        switcher.titleAlignment = .left
        switcher.translatesAutoresizingMaskIntoConstraints = false
        linkRow.addSubview(switcher)
        authSwitch = switcher
        NSLayoutConstraint.activate([
            switcher.leadingAnchor.constraint(equalTo: linkRow.leadingAnchor),
            switcher.centerYAnchor.constraint(equalTo: linkRow.centerYAnchor),
            switcher.widthAnchor.constraint(equalToConstant: 130),
            switcher.heightAnchor.constraint(equalToConstant: 24),
        ])

        let forgot = AccountButton(title: "忘记密码？", kind: .quiet)
        forgot.target = self
        forgot.action = #selector(openReset)
        forgot.titleAlignment = .right
        forgot.translatesAutoresizingMaskIntoConstraints = false
        linkRow.addSubview(forgot)
        NSLayoutConstraint.activate([
            forgot.trailingAnchor.constraint(equalTo: linkRow.trailingAnchor),
            forgot.centerYAnchor.constraint(equalTo: linkRow.centerYAnchor),
            forgot.widthAnchor.constraint(equalToConstant: 80),
            forgot.heightAnchor.constraint(equalToConstant: 24),
        ])
        // 间距必须挂在 linkRow 上：switcher 是 linkRow 的子视图，
        // 传给 NSStackView.setCustomSpacing 会让 AppKit 在布局里死循环（实测卡死）
        stack.setCustomSpacing(5, after: linkRow)

        let note = text("登录后，这台电脑上的壁纸会并入这个账号", size: 10.5, color: Ink.tertiary)
        note.isHidden = false
        fullWidth(note, in: stack)

        DispatchQueue.main.async { self.authEmail?.field.window?.makeFirstResponder(self.authEmail?.field) }
    }

    @objc private func toggleRegister() {
        isRegister.toggle()
        render()
    }

    @objc private func doAuth() {
        let email = (authEmail?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = authPassword?.text ?? ""
        guard email.contains("@"), email.count >= 5 else {
            showAuthError("邮箱格式不对")
            return
        }
        guard pw.count >= 8 else {
            showAuthError("密码至少 8 位")
            return
        }
        if isRegister, (authConfirm?.text ?? "") != pw {
            showAuthError("两次输入的密码不一样")
            return
        }

        authStatus?.isHidden = true
        authButton?.setEnabled(false)
        authButton?.updateTitle(isRegister ? "注册中…" : "登录中…")
        let reg = isRegister

        var code = ""
        if isRegister && !mailUnavailable {
            code = (authCode?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.count >= 4 else {
                authButton?.setEnabled(true)
                authButton?.updateTitle("注册并开始同步")
                showAuthError("先点右边「发送验证码」，把收到的 6 位数字填进来")
                return
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let r = reg ? AccountAPI.register(email: email, password: pw, code: code)
                        : AccountAPI.login(email: email, password: pw)
            DispatchQueue.main.async {
                self.authButton?.setEnabled(true)
                self.authButton?.updateTitle(reg ? "注册并开始同步" : "登录")
                switch r {
                case let .success(session):
                    SyncCenter.shared.signIn(session)
                    self.page = .profile
                    self.render()
                case let .failure(e):
                    self.showAuthError(e.localizedDescription)
                }
            }
        }
    }

    // MARK: 注册验证码

    @objc private func sendEmailCode() {
        let email = (authEmail?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { showAuthError("先填邮箱，再发验证码"); return }
        authSend?.setEnabled(false)
        authSend?.updateTitle("发送中…")
        showAuthStatus("正在发送…", color: Ink.tertiary)

        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.sendEmailCode(email: email, purpose: "register")
            DispatchQueue.main.async {
                switch r {
                case .success:
                    self.codeLeft = 60
                    self.startCodeTimer()
                    self.showAuthStatus("验证码已发到 \(email)，10 分钟内有效", color: .systemGreen)
                    self.authCode?.field.window?.makeFirstResponder(self.authCode?.field)
                case let .failure(e):
                    // 501 = 服务端还没配发信通道：这一行收起来，直接注册
                    if case let .http(code, _) = e, code == 501 {
                        self.mailUnavailable = true
                        self.authSend?.setEnabled(true)
                        self.render()
                        return
                    }
                    self.authSend?.setEnabled(true)
                    self.authSend?.updateTitle("发送验证码")
                    self.showAuthError(e.localizedDescription)
                }
            }
        }
    }

    /// 问服务端：发信通道开没开。没开就把验证码那行藏掉（只做域名真实性校验）。
    private func loadMailConfig() {
        DispatchQueue.global(qos: .utility).async {
            guard case let .success(cfg) = AccountAPI.authConfig() else { return }
            DispatchQueue.main.async {
                Self.mailKnown = true
                let unavailable = !cfg.mailCodeRequired
                guard unavailable != self.mailUnavailable else { return }
                self.mailUnavailable = unavailable
                if self.page == .auth, self.isRegister { self.render() }
            }
        }
    }

    private func startCodeTimer() {
        codeTimer?.invalidate()
        applyCodeCountdown()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.codeLeft = max(0, self.codeLeft - 1)
            self.applyCodeCountdown()
            if self.codeLeft == 0 { timer.invalidate(); self.codeTimer = nil }
        }
        RunLoop.main.add(t, forMode: .common)
        codeTimer = t
    }

    private func applyCodeCountdown() {
        guard let send = authSend else { return }
        if codeLeft > 0 {
            send.setEnabled(false)
            send.updateTitle("\(codeLeft) 秒后重发")
        } else {
            send.setEnabled(true)
            send.updateTitle("发送验证码")
        }
    }

    private func showAuthStatus(_ msg: String, color: NSColor) {
        authStatus?.stringValue = msg
        authStatus?.textColor = color
        authStatus?.isHidden = false
    }

    private func showAuthError(_ msg: String) {
        authStatus?.textColor = .systemRed
        authStatus?.stringValue = msg
        authStatus?.isHidden = false
    }

    // MARK: 已登录主页

    private func buildProfile(into stack: NSStackView) {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalToConstant: contentWidth),
            header.heightAnchor.constraint(equalToConstant: 46),
        ])
        stack.setCustomSpacing(14, after: header)

        let avatar = AvatarView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.onTap = { [weak self] in self?.openEdit() }
        header.addSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            avatar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
        ])
        profAvatar = avatar

        let name = text("", size: 14, weight: .medium)
        name.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(name)
        profName = name

        let status = text("", size: 10.5)
        status.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(status)
        profStatus = status

        let mail = text("", size: 11, color: Ink.tertiary)
        mail.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(mail)
        profEmail = mail

        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 11),
            name.topAnchor.constraint(equalTo: header.topAnchor, constant: 1),
            status.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 6),
            status.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),
            mail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            mail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3),
            mail.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),
        ])

        divider(in: stack)

        // 同步
        let syncHead = sectionLabel("同步")
        fullWidth(syncHead, in: stack)
        stack.setCustomSpacing(2, after: syncHead)

        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(line)
        line.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        line.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let summary = text("", size: 12)
        summary.translatesAutoresizingMaskIntoConstraints = false
        line.addSubview(summary)
        syncSummary = summary

        let quota = text("", size: 11, color: Ink.secondary, align: .right)
        quota.translatesAutoresizingMaskIntoConstraints = false
        line.addSubview(quota)
        syncQuota = quota

        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: line.leadingAnchor),
            summary.centerYAnchor.constraint(equalTo: line.centerYAnchor),
            quota.trailingAnchor.constraint(equalTo: line.trailingAnchor),
            quota.centerYAnchor.constraint(equalTo: line.centerYAnchor),
            quota.leadingAnchor.constraint(greaterThanOrEqualTo: summary.trailingAnchor, constant: 8),
        ])
        stack.setCustomSpacing(5, after: line)

        let bar = UsageBar()
        fullWidth(bar, in: stack)
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        syncBar = bar
        stack.setCustomSpacing(8, after: bar)

        let footRow = NSView()
        footRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(footRow)
        footRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        footRow.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let foot = text("", size: 10.5, color: Ink.tertiary)
        foot.translatesAutoresizingMaskIntoConstraints = false
        footRow.addSubview(foot)
        syncFoot = foot

        let sync = AccountButton(title: "立即同步", kind: .quiet)
        sync.target = self
        sync.action = #selector(doSync)
        sync.translatesAutoresizingMaskIntoConstraints = false
        footRow.addSubview(sync)
        syncButton = sync

        // 文字按钮手动描一圈边，让它看得出是可点的
        sync.wantsLayer = true
        sync.layer?.borderWidth = 1
        sync.layer?.borderColor = Ink.edge.cgColor
        sync.layer?.cornerRadius = 6

        NSLayoutConstraint.activate([
            foot.leadingAnchor.constraint(equalTo: footRow.leadingAnchor),
            foot.centerYAnchor.constraint(equalTo: footRow.centerYAnchor),
            sync.trailingAnchor.constraint(equalTo: footRow.trailingAnchor),
            sync.centerYAnchor.constraint(equalTo: footRow.centerYAnchor),
            sync.widthAnchor.constraint(equalToConstant: 74),
            sync.heightAnchor.constraint(equalToConstant: 24),
            foot.trailingAnchor.constraint(lessThanOrEqualTo: sync.leadingAnchor, constant: -8),
        ])
        stack.setCustomSpacing(10, after: footRow)

        divider(in: stack)

        // 账号安全
        let secHead = sectionLabel("账号安全")
        fullWidth(secHead, in: stack)
        stack.setCustomSpacing(2, after: secHead)

        let devices = AccountRow(title: "登录设备", value: "管理")
        devices.onTap = { [weak self] in self?.openDevices() }
        fullWidth(devices, in: stack)

        let pw = AccountRow(title: "修改密码")
        pw.onTap = { [weak self] in self?.openPassword() }
        fullWidth(pw, in: stack)

        let recovery = AccountRow(title: "恢复码", value: "检查中…", hairline: false)
        recovery.onTap = { [weak self] in self?.openRecovery() }
        recoveryRow = recovery
        fullWidth(recovery, in: stack)
        if !recoveryLoaded { loadRecovery() } else { refreshRecoveryRow() }

        let gap = NSView()
        gap.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(gap)
        gap.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        gap.heightAnchor.constraint(equalToConstant: 9).isActive = true

        divider(in: stack)

        // 账号
        let accHead = sectionLabel("账号")
        fullWidth(accHead, in: stack)
        stack.setCustomSpacing(2, after: accHead)

        let edit = AccountRow(title: "昵称与头像")
        edit.onTap = { [weak self] in self?.openEdit() }
        fullWidth(edit, in: stack)

        let out = AccountRow(title: "退出登录",
                             value: "壁纸留在账号里",
                             valueColor: Ink.tertiary,
                             titleColor: .systemRed,
                             showsChevron: false,
                             hairline: false)
        out.onTap = { [weak self] in self?.doSignOut() }
        fullWidth(out, in: stack)

        updateLive()
    }

    private func openEdit() {
        guard SyncCenter.shared.isLoggedIn else { return }
        page = .edit
        render()
    }

    private func openPassword() {
        guard SyncCenter.shared.isLoggedIn else { return }
        page = .password
        render()
    }

    /// 只刷新文字和进度，不重建视图——否则正在看的页面会闪、焦点会丢
    private func updateLive() {
        guard let s = SyncCenter.shared.session else { return }
        let nick = SyncCenter.shared.profile?.displayName ?? ""
        let seed = nick.isEmpty ? s.email : nick
        profName?.stringValue = seed
        profEmail?.stringValue = nick.isEmpty ? "" : s.email
        profAvatar?.initial = String(seed.first ?? "?").uppercased()
        if let d = SyncCenter.shared.avatarData, let img = NSImage(data: d) {
            profAvatar?.image = img
        } else {
            profAvatar?.image = nil
        }

        let st = SyncCenter.shared.status
        if SyncCenter.shared.isPreparing {
            profStatus?.stringValue = "正在准备同步…"
            profStatus?.textColor = Brand.accent
        } else {
            switch st {
        case .syncing:
            profStatus?.stringValue = "正在同步"
            profStatus?.textColor = Brand.accent
        case .failed:
            profStatus?.stringValue = "同步出错"
            profStatus?.textColor = .systemRed
        case .done:
            profStatus?.stringValue = "已同步"
            profStatus?.textColor = .systemGreen
            default:
                profStatus?.stringValue = "已登录"
                profStatus?.textColor = .systemGreen
            }
        }

        let quota = quotaBytes > 0 ? quotaBytes : s.quotaBytes
        syncSummary?.stringValue = "云端 \(Self.bytes(usedBytes))"
        syncQuota?.stringValue = "配额 \(Self.bytes(quota))"

        if let p = SyncCenter.shared.progress, st.isBusy {
            syncBar?.ratio = p.fraction
            let pct = Int((p.fraction * 100).rounded())
            syncFoot?.stringValue = "\(pct)% · \(Self.bytes(p.bytesDone)) / \(Self.bytes(p.bytesTotal)) · 第 \(max(p.done, 1))/\(p.total) 张"
            syncButton?.setEnabled(false)
            syncButton?.updateTitle("同步中…")
        } else {
            syncBar?.ratio = quota > 0 ? Double(usedBytes) / Double(quota) : 0
            switch st {
            case .done: syncFoot?.stringValue = "同步完成"
            case .idle: syncFoot?.stringValue = "已连接"
            default: syncFoot?.stringValue = st.text
            }
            syncButton?.setEnabled(true)
            syncButton?.updateTitle("立即同步")
        }
    }

    private func loadUsage() {
        guard let s = SyncCenter.shared.session else { return }
        DispatchQueue.global(qos: .utility).async {
            if case let .success(me) = AccountAPI.me(token: s.token) {
                DispatchQueue.main.async {
                    self.usedBytes = me.usedBytes
                    self.quotaBytes = me.quotaBytes
                    self.updateLive()
                }
            }
        }
    }

    @objc private func doSync() {
        SyncCenter.shared.syncNow()
        updateLive()
    }

    @objc private func doSignOut() {
        let a = NSAlert()
        a.messageText = "退出登录？"
        a.informativeText = "这台电脑将不再显示该账号的壁纸。壁纸都存在账号里，下次登录自动回来。"
        a.addButton(withTitle: "退出登录")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let note = SyncCenter.shared.signOut()
        page = .auth
        isRegister = false
        usedBytes = 0
        quotaBytes = 0
        render()

        if note.contains("没传完") {
            let b = NSAlert()
            b.messageText = "已退出登录"
            b.informativeText = note
            b.runModal()
        }
    }

    // MARK: 重设密码（用恢复码）

    @objc private func openReset() {
        pendingEmail = (authEmail?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        page = .reset
        render()
    }

    @objc private func goAuth() {
        page = .auth
        render()
    }

    private func buildReset(into stack: NSStackView) {
        backHeader("重设密码", in: stack, back: #selector(goAuth))

        let hint = text("输入邮箱和恢复码，换一个新密码。恢复码用一次就作废。",
                        size: 11, color: Ink.secondary)
        hint.maximumNumberOfLines = 0
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = contentWidth
        fullWidth(hint, in: stack, spacing: 14)

        let email = AccountFieldBox(placeholder: "邮箱")
        email.field.stringValue = pendingEmail
        fullWidth(email, in: stack, spacing: 8)
        resetEmail = email

        let code = AccountFieldBox(placeholder: "恢复码（XXXX-XXXX-XXXX-XXXX）")
        fullWidth(code, in: stack, spacing: 8)
        resetCode = code

        let pw = AccountFieldBox(placeholder: "新密码（至少 8 位）", secure: true)
        fullWidth(pw, in: stack, spacing: 8)
        resetPassword = pw

        let confirm = AccountFieldBox(placeholder: "再输一次新密码", secure: true)
        confirm.field.target = self
        confirm.field.action = #selector(doReset)
        fullWidth(confirm, in: stack, spacing: 8)
        resetConfirm = confirm

        let status = text("", size: 11, color: .systemRed)
        status.maximumNumberOfLines = 0
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = contentWidth
        status.isHidden = true
        fullWidth(status, in: stack, spacing: 4)
        resetStatus = status

        let save = AccountButton(title: "重设密码")
        save.target = self
        save.action = #selector(doReset)
        fullWidth(save, in: stack)
        save.heightAnchor.constraint(equalToConstant: 36).isActive = true
        resetButton = save

        DispatchQueue.main.async {
            if self.pendingEmail.isEmpty {
                self.resetEmail?.field.window?.makeFirstResponder(self.resetEmail?.field)
            } else {
                self.resetCode?.field.window?.makeFirstResponder(self.resetCode?.field)
            }
        }
    }

    @objc private func doReset() {
        let email = (resetEmail?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (resetCode?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = resetPassword?.text ?? ""
        resetStatus?.isHidden = true
        guard email.contains("@") else { showResetError("邮箱格式不对"); return }
        guard code.count >= 12 else { showResetError("恢复码看起来不完整"); return }
        guard pw.count >= 8 else { showResetError("新密码至少 8 位"); return }
        guard pw == (resetConfirm?.text ?? "") else {
            showResetError("两次输入的新密码不一样")
            return
        }

        resetButton?.setEnabled(false)
        resetButton?.updateTitle("重设中…")
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.resetPassword(email: email, code: code, newPassword: pw)
            DispatchQueue.main.async {
                self.resetButton?.setEnabled(true)
                self.resetButton?.updateTitle("重设密码")
                switch r {
                case .success:
                    let a = NSAlert()
                    a.messageText = "密码已重设"
                    a.informativeText = "所有设备都需要重新登录。恢复码已经用掉，登录后可以再生成一个。"
                    a.runModal()
                    self.pendingEmail = email
                    self.page = .auth
                    self.isRegister = false
                    self.render()
                    self.authEmail?.field.stringValue = email
                    self.authPassword?.field.window?.makeFirstResponder(self.authPassword?.field)
                case let .failure(e):
                    self.showResetError(e.localizedDescription)
                }
            }
        }
    }

    private func showResetError(_ msg: String) {
        resetStatus?.stringValue = msg
        resetStatus?.isHidden = false
    }

    // MARK: 登录设备

    private func openDevices() {
        guard SyncCenter.shared.isLoggedIn else { return }
        sessionsLoaded = false
        sessionsError = nil
        page = .devices
        render()
    }

    private func buildDevices(into stack: NSStackView) {
        backHeader("登录设备", in: stack)

        let hint = text("这些设备上都登录着这个账号", size: 10.5, color: Ink.tertiary)
        fullWidth(hint, in: stack, spacing: 10)

        if let err = sessionsError {
            let t = text("读不到设备列表：\(err)", size: 11, color: .systemOrange)
            t.maximumNumberOfLines = 0
            t.lineBreakMode = .byWordWrapping
            t.preferredMaxLayoutWidth = contentWidth
            fullWidth(t, in: stack)
        } else if !sessionsLoaded {
            fullWidth(text("正在读取…", size: 12, color: Ink.tertiary), in: stack)
            loadSessions()
        } else if sessions.isEmpty {
            fullWidth(text("除了这台，没有别的设备", size: 12, color: Ink.tertiary), in: stack)
        } else {
            for (i, item) in sessions.enumerated() {
                fullWidth(deviceRow(item, last: i == sessions.count - 1), in: stack)
            }
        }

        let gap = NSView()
        gap.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(gap)
        gap.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        gap.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let foot = text("看到不认识的设备？先退出它，再改一次密码。", size: 10.5, color: Ink.tertiary)
        foot.maximumNumberOfLines = 0
        foot.lineBreakMode = .byWordWrapping
        foot.preferredMaxLayoutWidth = contentWidth
        fullWidth(foot, in: stack, spacing: 10)

        let others = sessions.filter { !$0.current }.count
        let kick = AccountButton(title: others > 0 ? "退出所有其它设备" : "没有其它设备在线", kind: .quiet)
        kick.isEnabled = others > 0
        kick.target = self
        kick.action = #selector(kickOthers)
        // 文字按钮默认看不出可点，给一圈细边
        kick.wantsLayer = true
        kick.layer?.borderWidth = 1
        kick.layer?.borderColor = Ink.edge.cgColor
        kick.layer?.cornerRadius = 6
        fullWidth(kick, in: stack)
        kick.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func deviceRow(_ item: AccountAPI.SessionInfo, last: Bool) -> NSView {
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let name = text(item.device, size: 12.5)
        name.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(name)

        let sub = text(item.current ? "当前设备" : "最近活跃 " + Self.relative(item.lastSeen),
                       size: 10.5,
                       color: item.current ? .systemGreen : Ink.tertiary)
        sub.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(sub)

        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            name.topAnchor.constraint(equalTo: holder.topAnchor, constant: 5),
            name.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -56),
            sub.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            sub.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
        ])

        if !item.current {
            let kick = ClosureButton(title: "退出", onTap: { [weak self] in self?.kick(item) })
            kick.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(kick)
            NSLayoutConstraint.activate([
                kick.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                kick.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
                kick.widthAnchor.constraint(equalToConstant: 44),
                kick.heightAnchor.constraint(equalToConstant: 22),
            ])
        }

        if !last {
            let line = hairline()
            holder.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
                line.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                line.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
        }
        return holder
    }

    private func loadSessions() {
        guard let session = SyncCenter.shared.session, !sessionsLoading else { return }
        sessionsLoading = true
        DispatchQueue.global(qos: .utility).async {
            let r = AccountAPI.sessions(token: session.token)
            DispatchQueue.main.async {
                self.sessionsLoading = false
                self.sessionsLoaded = true
                switch r {
                case let .success(list): self.sessions = list; self.sessionsError = nil
                case let .failure(e): self.sessionsError = e.localizedDescription
                }
                if self.page == .devices { self.render() }
            }
        }
    }

    private func kick(_ item: AccountAPI.SessionInfo) {
        guard let session = SyncCenter.shared.session else { return }
        let a = NSAlert()
        a.messageText = "让这台设备退出登录？"
        a.informativeText = "「\(item.device)」下次打开 App 需要重新登录。"
        a.addButton(withTitle: "退出登录")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.revokeSession(token: session.token, id: item.id)
            DispatchQueue.main.async {
                if case let .failure(e) = r {
                    self.alert("没踢掉", e.localizedDescription)
                    return
                }
                self.sessionsLoaded = false
                self.render()
            }
        }
    }

    @objc private func kickOthers() {
        guard let session = SyncCenter.shared.session else { return }
        let n = sessions.filter { !$0.current }.count
        guard n > 0 else { return }
        let a = NSAlert()
        a.messageText = "退出其它 \(n) 台设备？"
        a.informativeText = "这台电脑不受影响。"
        a.addButton(withTitle: "全部退出")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.revokeSession(token: session.token, id: "others")
            DispatchQueue.main.async {
                if case let .failure(e) = r {
                    self.alert("没踢掉", e.localizedDescription)
                    return
                }
                self.sessionsLoaded = false
                self.render()
            }
        }
    }

    // MARK: 恢复码

    private func openRecovery() {
        guard SyncCenter.shared.isLoggedIn else { return }
        freshCode = nil
        recoveryLoaded = false
        page = .recovery
        render()
    }

    private func buildRecovery(into stack: NSStackView) {
        backHeader("恢复码", in: stack)
        // 调试用：摆拍「刚生成完」的界面（正常流程里只有点了生成才有）
        if freshCode == nil, let c = ProcessInfo.processInfo.environment["VW_ACCOUNT_FRESHCODE"] {
            freshCode = c
        }

        let intro = text("忘了密码时，用「邮箱 + 恢复码」重设。码只显示一次，请抄下来或存进密码管理器。",
                         size: 11, color: Ink.secondary)
        intro.maximumNumberOfLines = 0
        intro.lineBreakMode = .byWordWrapping
        intro.preferredMaxLayoutWidth = contentWidth
        fullWidth(intro, in: stack, spacing: 14)

        if let code = freshCode {
            let box = NSView()
            box.wantsLayer = true
            box.layer?.cornerRadius = 8
            box.layer?.backgroundColor = Ink.fill.cgColor
            box.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(box)
            box.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            box.heightAnchor.constraint(equalToConstant: 46).isActive = true

            let label = NSTextField(labelWithString: code)
            label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
            label.textColor = Ink.primary
            label.alignment = .center
            label.isSelectable = true
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            ])
            stack.setCustomSpacing(10, after: box)

            let copy = AccountButton(title: "复制恢复码")
            copy.target = self
            copy.action = #selector(copyCode)
            fullWidth(copy, in: stack)
            copy.heightAnchor.constraint(equalToConstant: 34).isActive = true
            stack.setCustomSpacing(8, after: copy)

            let warn = text("离开这个页面后就看不到了，只能重新生成。", size: 10.5, color: .systemOrange)
            warn.maximumNumberOfLines = 0
            warn.lineBreakMode = .byWordWrapping
            warn.preferredMaxLayoutWidth = contentWidth
            fullWidth(warn, in: stack)
            return
        }

        if !recoveryLoaded {
            fullWidth(text("正在读取…", size: 12, color: Ink.tertiary), in: stack)
            loadRecovery()
            return
        }

        let has = recovery?.hasRecovery ?? false
        let stateText: String
        if recovery == nil {
            stateText = "读不到恢复码状态，服务端可能还没更新"
        } else if has {
            stateText = "已生成于 " + Self.dateText(recovery?.createdAt ?? 0)
        } else {
            stateText = "还没有恢复码"
        }
        let state = text(stateText, size: 12, color: has ? Ink.primary : .systemOrange)
        fullWidth(state, in: stack, spacing: 12)

        let primary = AccountButton(title: has ? "重新生成" : "生成恢复码")
        primary.target = self
        primary.action = #selector(generateRecovery)
        fullWidth(primary, in: stack)
        primary.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.setCustomSpacing(8, after: primary)

        let note = text(has ? "重新生成会让旧码立刻失效。" : "建议现在就生成一个，忘密码时这是唯一出路。",
                        size: 10.5, color: Ink.tertiary)
        note.maximumNumberOfLines = 0
        note.lineBreakMode = .byWordWrapping
        note.preferredMaxLayoutWidth = contentWidth
        fullWidth(note, in: stack, spacing: 10)

        if has {
            let remove = AccountButton(title: "移除恢复码", kind: .quiet)
            remove.target = self
            remove.action = #selector(removeRecovery)
            remove.titleAlignment = .left
            fullWidth(remove, in: stack)
            remove.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
    }

    private func loadRecovery() {
        guard let session = SyncCenter.shared.session, !recoveryLoaded else { return }
        DispatchQueue.global(qos: .utility).async {
            let r = AccountAPI.recoveryStatus(token: session.token)
            DispatchQueue.main.async {
                self.recoveryLoaded = true
                if case let .success(st) = r { self.recovery = st }
                self.refreshRecoveryRow()
                if self.page == .recovery || self.page == .profile { self.render() }
            }
        }
    }

    private func refreshRecoveryRow() {
        guard let row = recoveryRow else { return }
        guard let r = recovery else { row.setValue("检查失败"); return }
        if r.hasRecovery {
            row.setValue("已生成")
        } else {
            row.setValue("未生成", color: .systemOrange)
        }
    }

    @objc private func generateRecovery() {
        guard let session = SyncCenter.shared.session else { return }
        if recovery?.hasRecovery == true {
            let a = NSAlert()
            a.messageText = "重新生成恢复码？"
            a.informativeText = "旧的那串会立刻失效。"
            a.addButton(withTitle: "重新生成")
            a.addButton(withTitle: "取消")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.createRecovery(token: session.token)
            DispatchQueue.main.async {
                switch r {
                case let .success(code):
                    self.freshCode = code
                    self.recovery = AccountAPI.RecoveryState(
                        hasRecovery: true,
                        createdAt: Int64(Date().timeIntervalSince1970 * 1000))
                    self.recoveryLoaded = true
                    self.refreshRecoveryRow()
                    self.render()
                case let .failure(e):
                    self.alert("生成失败", e.localizedDescription)
                }
            }
        }
    }

    @objc private func removeRecovery() {
        guard let session = SyncCenter.shared.session else { return }
        let a = NSAlert()
        a.messageText = "移除恢复码？"
        a.informativeText = "移除后忘记密码就没法自己重置了。"
        a.addButton(withTitle: "移除")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.removeRecovery(token: session.token)
            DispatchQueue.main.async {
                switch r {
                case .success:
                    self.recovery = AccountAPI.RecoveryState(hasRecovery: false, createdAt: 0)
                    self.freshCode = nil
                    self.refreshRecoveryRow()
                    self.render()
                case let .failure(e):
                    self.alert("移除失败", e.localizedDescription)
                }
            }
        }
    }

    @objc private func copyCode() {
        guard let code = freshCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    static func relative(_ ms: Int64) -> String {
        guard ms > 0 else { return "未知" }
        let sec = Date().timeIntervalSince1970 - Double(ms) / 1000
        if sec < 90 { return "刚刚" }
        if sec < 3600 { return "\(Int(sec / 60)) 分钟前" }
        if sec < 86400 { return "\(Int(sec / 3600)) 小时前" }
        return "\(Int(sec / 86400)) 天前"
    }

    static func dateText(_ ms: Int64) -> String {
        guard ms > 0 else { return "未知时间" }
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    // MARK: 编辑资料

    private func buildEdit(into stack: NSStackView) {
        backHeader("昵称与头像", in: stack)

        let avatar = AvatarView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.onTap = { [weak self] in self?.pickAvatar() }
        stack.addArrangedSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 76),
            avatar.heightAnchor.constraint(equalToConstant: 76),
        ])
        editAvatar = avatar
        stack.setCustomSpacing(6, after: avatar)

        let nick = SyncCenter.shared.profile?.displayName ?? ""
        let seed = nick.isEmpty ? (SyncCenter.shared.session?.email ?? "?") : nick
        avatar.initial = String(seed.first ?? "?").uppercased()
        if let d = SyncCenter.shared.avatarData, let img = NSImage(data: d) {
            avatar.image = img
        }

        let tip = text("点头像换一张", size: 10.5, color: Ink.tertiary)
        stack.addArrangedSubview(tip)
        stack.setCustomSpacing(14, after: tip)

        let name = AccountFieldBox(placeholder: "昵称（最多 20 个字）")
        name.field.stringValue = nick
        fullWidth(name, in: stack, spacing: 8)
        editName = name

        let status = text("", size: 11, color: .systemRed)
        status.maximumNumberOfLines = 0
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = contentWidth
        status.isHidden = true
        fullWidth(status, in: stack, spacing: 4)
        editStatus = status

        let save = AccountButton(title: "保存")
        save.target = self
        save.action = #selector(saveProfile)
        fullWidth(save, in: stack, spacing: 6)
        save.heightAnchor.constraint(equalToConstant: 34).isActive = true
        editSave = save

        let remove = AccountButton(title: "移除头像", kind: .quiet)
        remove.target = self
        remove.action = #selector(removeAvatar)
        fullWidth(remove, in: stack)
        remove.heightAnchor.constraint(equalToConstant: 26).isActive = true
        remove.isHidden = !(SyncCenter.shared.profile?.hasAvatar ?? false)
        editRemove = remove
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
            editStatus?.stringValue = "这张图片读不出来"
            editStatus?.isHidden = false
            return
        }
        pendingAvatar = data
        editAvatar?.image = NSImage(data: data)
        editStatus?.isHidden = true
        editRemove?.isHidden = false
    }

    /// 裁成正方形 + 缩到 256，避免把几 MB 的原图传上去
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
        let name = (editName?.text ?? "").trimmingCharacters(in: .whitespaces)
        if name.count > 20 {
            editStatus?.stringValue = "昵称最多 20 个字"
            editStatus?.isHidden = false
            return
        }
        editSave?.setEnabled(false)
        editSave?.updateTitle("保存中…")
        editStatus?.isHidden = true
        let avatar = pendingAvatar
        let old = SyncCenter.shared.profile?.displayName ?? ""

        DispatchQueue.global(qos: .userInitiated).async {
            var error: String?
            if let avatar {
                if case let .failure(e) = AccountAPI.uploadAvatar(token: session.token, png: avatar) {
                    error = "头像保存失败：\(e.localizedDescription)"
                }
            }
            if error == nil, name != old {
                if case let .failure(e) = AccountAPI.updateDisplayName(token: session.token, name: name) {
                    error = "昵称保存失败：\(e.localizedDescription)"
                }
            }
            DispatchQueue.main.async {
                self.editSave?.setEnabled(true)
                self.editSave?.updateTitle("保存")
                if let error {
                    self.editStatus?.stringValue = error
                    self.editStatus?.isHidden = false
                    return
                }
                self.pendingAvatar = nil
                SyncCenter.shared.refreshProfile { [weak self] in
                    self?.goProfile()
                }
            }
        }
    }

    @objc private func removeAvatar() {
        guard let session = SyncCenter.shared.session else { return }
        editRemove?.setEnabled(false)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.deleteAvatar(token: session.token)
            DispatchQueue.main.async {
                self.editRemove?.setEnabled(true)
                if case let .failure(e) = r {
                    self.editStatus?.stringValue = e.localizedDescription
                    self.editStatus?.isHidden = false
                    return
                }
                self.pendingAvatar = nil
                SyncCenter.shared.refreshProfile { [weak self] in
                    self?.goProfile()
                }
            }
        }
    }

    // MARK: 修改密码

    private func buildPassword(into stack: NSStackView) {
        backHeader("修改密码", in: stack)

        let hint = text("改完后其它设备需要重新登录，这台不用", size: 10.5, color: Ink.tertiary)
        hint.maximumNumberOfLines = 0
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = contentWidth
        fullWidth(hint, in: stack, spacing: 12)

        let old = AccountFieldBox(placeholder: "当前密码", secure: true)
        fullWidth(old, in: stack, spacing: 8)
        pwOld = old

        let new = AccountFieldBox(placeholder: "新密码（至少 8 位）", secure: true)
        fullWidth(new, in: stack, spacing: 8)
        pwNew = new

        let confirm = AccountFieldBox(placeholder: "再输一次新密码", secure: true)
        confirm.field.target = self
        confirm.field.action = #selector(savePassword)
        fullWidth(confirm, in: stack, spacing: 8)
        pwConfirm = confirm

        let status = text("", size: 11, color: .systemRed)
        status.maximumNumberOfLines = 0
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = contentWidth
        status.isHidden = true
        fullWidth(status, in: stack, spacing: 4)
        pwStatus = status

        let save = AccountButton(title: "保存")
        save.target = self
        save.action = #selector(savePassword)
        fullWidth(save, in: stack)
        save.heightAnchor.constraint(equalToConstant: 34).isActive = true
        pwSave = save
    }

    @objc private func savePassword() {
        guard let session = SyncCenter.shared.session else { return }
        let old = pwOld?.text ?? ""
        let new = pwNew?.text ?? ""
        pwStatus?.isHidden = true
        guard !old.isEmpty else { pwStatus?.stringValue = "请输入当前密码"; pwStatus?.isHidden = false; return }
        guard new.count >= 8 else { pwStatus?.stringValue = "新密码至少 8 位"; pwStatus?.isHidden = false; return }
        guard new == (pwConfirm?.text ?? "") else {
            pwStatus?.stringValue = "两次输入的新密码不一样"
            pwStatus?.isHidden = false
            return
        }

        pwSave?.setEnabled(false)
        pwSave?.updateTitle("保存中…")
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AccountAPI.changePassword(token: session.token, old: old, new: new)
            DispatchQueue.main.async {
                self.pwSave?.setEnabled(true)
                self.pwSave?.updateTitle("保存")
                switch r {
                case .success:
                    self.goProfile()
                    let a = NSAlert()
                    a.messageText = "密码已修改"
                    a.informativeText = "其它设备上的登录已失效，需要重新登录。这台电脑不用。"
                    a.runModal()
                case let .failure(e):
                    self.pwStatus?.stringValue = e.localizedDescription
                    self.pwStatus?.isHidden = false
                }
            }
        }
    }

    // MARK: 格式化

    static func bytes(_ v: Int64) -> String {
        if v >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", Double(v) / 1024 / 1024 / 1024)
        }
        if v >= 1024 * 1024 {
            return String(format: "%.0f MB", Double(v) / 1024 / 1024)
        }
        if v >= 1024 {
            return String(format: "%.0f KB", Double(v) / 1024)
        }
        return "\(v) B"
    }
}
