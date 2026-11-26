import Cocoa

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
            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
        ])
        chevron.isHidden = !(showsChevron && clickable)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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

    private enum Page { case auth, profile, edit, password }

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
            case "profile": page = .profile
            case "auth": page = .auth
            default: break
            }
            didForceDebugPage = true
        } else if !SyncCenter.shared.isLoggedIn {
            page = .auth
        } else if page == .auth {
            page = .profile
        }
        render()
    }

    /// 回到主页（子页面的「返回」和保存成功后都走这里）
    @objc private func goProfile() {
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
        case .auth: buildAuth(into: stack)
        case .profile: buildProfile(into: stack)
        case .edit: buildEdit(into: stack)
        case .password: buildPassword(into: stack)
        }

        if page == .profile { loadUsage() }
    }

    private func clearRefs() {
        authEmail = nil; authPassword = nil; authConfirm = nil; authStatus = nil
        authButton = nil; authSwitch = nil; authTitle = nil; authSubtitle = nil
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

    private func backHeader(_ title: String, in stack: NSStackView) {
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(holder)
        holder.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        holder.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.setCustomSpacing(12, after: holder)

        let back = AccountButton(title: "‹ 返回", kind: .quiet)
        back.target = self
        back.action = #selector(goProfile)
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

        let switcher = AccountButton(title: isRegister ? "已经有账号，去登录" : "没有账号？用邮箱注册",
                                     kind: .quiet)
        switcher.target = self
        switcher.action = #selector(toggleRegister)
        switcher.titleAlignment = .left
        fullWidth(switcher, in: stack)
        switcher.heightAnchor.constraint(equalToConstant: 24).isActive = true
        authSwitch = switcher
        stack.setCustomSpacing(5, after: switcher)
        stack.setCustomSpacing(5, after: switcher)

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

        DispatchQueue.global(qos: .userInitiated).async {
            let r = reg ? AccountAPI.register(email: email, password: pw)
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

    private func showAuthError(_ msg: String) {
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

        let devices = AccountRow(title: "登录设备", value: "即将支持", clickable: false)
        fullWidth(devices, in: stack)

        let pw = AccountRow(title: "修改密码")
        pw.onTap = { [weak self] in self?.openPassword() }
        fullWidth(pw, in: stack)

        let recovery = AccountRow(title: "恢复码", value: "即将支持", clickable: false, hairline: false)
        fullWidth(recovery, in: stack)

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
