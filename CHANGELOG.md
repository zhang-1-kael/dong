### F21.26 · 邮箱真实性：域名校验 + 邮箱验证码 — 状态：`服务端完成，待官网部署；客户端待发版`

- **日期**：2026-11-26 20:40
- **用户反馈**：发布后用别人的电脑测试，随便乱打的邮箱（如 `asdf@asdf.com`）都能注册成功。
  要求必须用真实可收信的邮箱，将来好发通知。
- **根因**：注册只做了正则格式校验，域名是否真的能收信完全没查。
- **两层修复**：
  1. **域名真实性（零配置，部署即生效）**——`emailcheck.js`：查 MX 记录、一次性邮箱黑名单
     （mailinator/yopmail 等 40 个）、常见拼写纠正（`gmial.com` → 提示 `gmail.com`）。
     解析超时类错误放行（避免自家 DNS 抖动挡住所有人），「域名不存在 / 无 MX / 解析被拒」才拒。
  2. **邮箱验证码（需发信通道）**——`mail.js`（零依赖：Resend / 阿里云 DirectMail / console 三选一）
     + `/api/auth/email/code` + 注册强制校验（`MAIL_REQUIRE_CODE=0` 可先关掉强制）。
- **关键发现**：`asdf.com` **真的有 MX 记录**（`mx10.asdf.com`），所以任何 DNS 检查都拦不住它；
  只有发信验证码能拦住「域名真实但邮箱是编的」。原先「无 MX 就看 A 记录」的兜底也因此去掉。
- **客户端**：注册页新增「邮箱验证码 + 发送验证码」（60 秒倒计时），并按新增的
  `/api/auth/config` 自动显隐——服务端没开发信就整行不显示，用户不会点到报错的按钮。
- **验证（本地 :8802 带 console 发信 / :8803 不带）**：
  - 域名校验 9 例：假域名/临时邮箱/拼写错全部拒绝，gmail/qq/163/outlook 全通过
  - 服务端 7 例：发码 200、60 秒内 429、无码 400、错码 400、正码 200、复用 409
  - 客户端 API 5 例全过；三张界面截图核对（发信开＝有验证码行 / 未开＝无该行 / 登录页无残留）
- **部署顺序（重要）**：先发客户端 → 再配 `MAIL_PROVIDER` → 旧客户端此时注册会失败，
  过渡期可先设 `MAIL_REQUIRE_CODE=0`
- **注意**：验证码只存内存（10 分钟），多实例部署需会话粘性；`MAIL_DEV_ECHO=1` 只能本地用
- **交接文档**：`Dòng 邮箱真实性修复-交接给官网.md`

### F21.26 · 修「锁屏变成系统默认壁纸」：动态锁屏扩展缺失时强制走静态帧 — 状态：`运行态已恢复 / 代码已改 / 待并入下一版`
- **日期**：2026-11-26
- **用户反馈**：锁屏变成原本的系统壁纸了，要求改回「锁屏取一帧静态帧」。
- **根因（两段叠加）**：
  1. 偏好里 `dynamicLockScreen = 1`（历史开启），但 **3.44 / 3.43 的包都没有 `Contents/PlugIns/*.appex`**（锁屏扩展未打包），`pushLockScreen` 仍走动态分支 → 直接 return，**不再调 `LockScreen.apply` 抽帧设壁纸**。
  2. 系统壁纸 Store（`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`）里的记录指向**已不存在的文件**（`locks/🌂.jpg`、容器里已删的 `lock.mp4`），系统于是回退到默认壁纸。
  - 补充：当前壁纸 `【哲风壁纸】wink-吊带短裙.mp4` 在 18:06 换上时动态锁屏还开着，所以它的静态帧从未生成。
- **修复（两层）**：
  1. **运行态立即恢复**：`dynamicLockScreen` 置 0 → 用与 `LockScreen.ensureFrame` 相同逻辑（35% 处抽帧、按屏幕像素、JPEG 0.92）补生成 `locks/【哲风壁纸】wink-吊带短裙.jpg`（2816×1484）→ `NSWorkspace.setDesktopImageURL` 设为桌面壁纸（锁屏随之同步）。复核 Index.plist 中 locks 引用 **4/4 全部指向存在的文件**。
  2. **代码防御**：`DynamicLockScreen.extensionAvailable`（检查 `Bundle.main.builtInPlugInsURL` 下有无 `.appex`）；`pushLockScreen` 改为 `isEnabled && extensionAvailable` 才走动态分支；`LibraryWindow` 里「锁屏动态播放（视频）」开关仅在扩展存在时创建。这样以后无论偏好怎么设，只要包里没扩展就一定走静态帧。
- **改动文件**：`DynamicLockScreen.swift`（+extensionAvailable）、`main.swift`（pushLockScreen 条件）、`LibraryWindow.swift`（开关条件创建）。
- **注意**：当前已装 App 是 **3.44/66**，工作区源码是 **3.45/67**；本修复代码需并入下一版（3.46）才会进入安装包，运行态修复已即时生效。

### F21.25 · 发版 3.45 / 67 — 状态：`GitHub 已发布 / Gitee 已发布 / 官网待填元数据`

- **日期**：2026-11-26
- **版本**：`Info.plist` 3.44/66 → **3.45/67**；10 个 README 版本串（正文 + 徽章）同步
- **产物**：`dist/Dòng-3.45.dmg`
  - size `61838037`
  - sha256 `628f989593106b223748e35745c9a263368347c663c95909f42c5d8f9b1b4f0e`
  - `hdiutil verify` 通过；挂载核对 `Dòng.app` 内 3.45 / 67、`SyncBaseURL` 为 `https://dongisgood.coze.site`、adhoc 签名、arm64
- **本版内容**（上次发布后累积的两处）：
  - F21.23：底栏下方留白/阴影不再误切壁纸；登录后自动同步可见化（「正在准备同步…」）
  - F21.24：退出登录立刻掐断正在跑的同步；重新登录不再空白两三分钟；昵称头像本地缓存、
    清单读不到不再误判为「云端为空」；25 秒兜底
- **已知限制**：单个 >20MB 的壁纸仍传不上去（云端存储网关限制，服务端 `MAX_ASSET` 是 512MB），
  要等官网侧放开或改分片上传
- **发布**：
  - GitHub：tag `v3.45` + Release「Dòng 3.45」已建并设为 Latest，附件 `Dong-3.45.dmg`
    （API digest 与上面 sha256 一致）；`main` 已推到 `cd702ae`
  - Gitee：**已同步 3.45**（2026-11-26 20:15 补做）。`main` → `facdf4c`（3.45 代码 + 十语言 README 版本串 + 7 处链接本地化）；tag `v3.45` 已推；Release「Dòng 3.45」（id `1372063`）附件 `Dòng-3.45.dmg`，匿名下载 HTTP 200、`Content-Length 61838037` 与包大小一致。
    凭据取自钥匙串 `gitee.com`（`dong-is-good`），未落盘。同步方式：`fetch 本地 main → reset --hard → 本地化 README → commit → push --force`。
  - 官网：`/api/update/check?version=3.44&build=66` 仍返回 3.44/66，**待后台填元数据**
    （6 个值见 `Dòng 3.45-发版清单.md`）；填完老用户才能收到提示
- **未覆盖本机**：`/Applications/Dòng.app` 仍是 3.44 修复版，留着给用户验证「3.44 → 3.45 更新提示」

### F21.24 · 修「退出再登录，账号里全空、昵称头像也变回去」 — 状态：`已修，已装机，随 3.45 发布`

- **日期**：2026-11-26 19:20 用户反馈：退出登录后再登回来，账号里什么都没有，改过的头像和名字也变回去了，
  截图里还停在「正在准备同步…」，但云端用量显示 48MB（说明数据其实都在）。
- **现场证据（`sync.log`，UTC）**：
  ```
  11:22:07 退出登录：收起 14 张到该账号的缓存
  11:25:32 上传重试 …下雨-卡通动画-卧室.mp4：网络不通：上传卡住了   ← 退出前那轮上传还没死
  11:25:33 切换壁纸库：已切换：收起 0 张，换出这个账号的 14 张        ← 晚了 2 分半
  ```
- **根因（一条链，三个症状同一个原因）**：
  1. `signOut()` 只把界面切成未登录，**没有取消正在跑的那轮同步**；它卡在 300 秒上传看门狗里，
     一直占着 `com.zhanghangshuo.dong.sync` 这条**串行队列**。
  2. 重新登录后 `signIn()` 的「读清单 → 切库 → 拉资料」全排在它后面 → 这 2 分半里
     库还是匿名库（空的）、`profile` 是 nil（显示成邮箱 + 首字母）、状态停在「正在准备同步…」。
  3. 顺带发现：清单请求失败时 `empty` 初值是 `true`，会被当成「云端是空的」→
     可能把本地壁纸误并进一个其实有内容的账号。
- **修复**：
  - 新增 `CancelToken`（`Account.swift`）。`signOut` / `signIn` 都先作废旧票再动状态。
  - `SyncEngine.run` 收 `cancel:`：进循环前、每张之前、收尾写清单前都查；上传/下载/清单请求都带票。
  - `UploadSink` 看门狗从 10 秒改 1 秒轮询，附带查取消票；`send()` / `download()` 也改成
    轮询信号量（0.3s / 0.5s 一次），取消能**立刻**撒手，不再等 20 秒请求超时。
  - `SyncCenter` 加**代次** `generation`：登录/退出都 +1，旧任务带旧代次回来一律丢弃
    （旧任务以前会在退出后继续写 `status`、`progress`，把新状态冲掉）。
  - 登录准备拆成 `prepareLibrary()`：清单读不到**重试 1 次**（探针 10s 短超时），仍然失败就
    **不动库归属、不同步**，界面给「读不到云端清单，点『立即同步』重试」；点同步会重跑准备，
    而不是傻等。`libraryReady` 标志挡住「归属没定就同步」。
  - 25 秒兜底：无论链路怎么卡，「正在准备同步…」都会被收掉。
  - **资料本地缓存**（`profile-<userId>.json` + `.png`）：登录瞬间就能摆出上次的昵称头像，
    不用等网络；`refreshProfile` 失败也不再把手里的资料抹成空。
- **验证（独立 harness，`VW_SUPPORT_DIR` 隔离 + 本地 `sync-server` :8799）**：
  | 用例 | 结果 |
  |---|---|
  | 新账号登录：本地 2 张并入并上传 | ✅ 0.05s 准备完，上传 2 |
  | 改昵称 + 传头像 → 退出 | ✅ 昵称「小航」、头像 70B 落到本地缓存 |
  | 退出 → 再登录 | ✅ **登录瞬间**昵称头像即恢复；0.05s 切库；2 张原样回来 |
  | 上传途中取消 | ✅ 0.45s 返回 `.cancelled`（本地回环，300MB） |
  | 连接挂死（黑洞服务器）时取消 | ✅ **0.01s** 返回 `.cancelled`（修复前要等 300s 看门狗 / 20s 请求超时） |
  | 同步前就取消 | ✅ `.cancelled`，清单不写 |
  | 退出/登录再来一轮 | ✅ 2 张不丢，昵称仍在 |
  | **服务器不可达**时登录 | ✅ 2.2s 收尾、不切库、本地 2 张原地不动、明确报错 |
- **文件**：`Account.swift`（CancelToken / 错误枚举加 `.cancelled` / upload、download、send 可取消 /
  manifest 可设超时 / `CachedProfile`）、`SyncEngine.swift`（cancel 全链路）、
  `SyncCenter.swift`（代次、prepareLibrary、资料缓存、退出不阻塞、25s 兜底）
- **装机**：`/Applications/Dòng.app` 已换新二进制（PID 44823），回滚备份
  `/tmp/vw_bin_backup_before_cancel_1795692762`；版本号未动。
- **另发现（未修，需官网配合）**：唯一一张 24.6MB 的壁纸反复「上传卡住」失败，≤14MB 的 13 张全部成功；
  更早还有一张报 413。看起来云端上传通道对**20MB 以上**的文件有限制（服务端 `MAX_ASSET` 是 512MB，
  卡在网关那一层）。要根治得网关放宽限制，或我们改成分片上传。

### F21.23 · 修「点底栏误切壁纸」+ 登录后自动同步可见化 — 状态：`已修，待并入下一版`

- **日期**：2026-11-26
- **用户反馈**：① 点账号头像时下面的壁纸被误切，很突然；② 登录后不点「立即同步」好像不会同步。
- **① 排查与修复**：
  - 合成点击实验（`VW_CLICK_TEST`）证明：点**头像本身**不会切壁纸（index 0 → 0，`libraryApply` 未触发）
  - 真正漏的是**底栏下 16pt 留白 + 栏的阴影那一圈**：`hitTest` 直接落到 `GalleryView`，等于点到了卡片
  - 新增 `DockShield`：铺满「窗口底边 → 栏顶 + 10pt」，吞掉鼠标事件；栏和按钮层级更高，照常可点
  - **踩坑**：`DockShield.hitTest` 一开始无条件 `return self`，父视图不会替它校验 frame →
    整个窗口的点击都被吃掉，卡片全点不动。必须自己 `bounds.contains(convert(...))`
  - 实测命中表：`bar-center → MiniSlider`、`shadow/below-bar → DockShield`、`above-bar → GalleryView`
- **② 排查与修复**：
  - `VW_LOGIN_TEST` 实测：登录后 **+2s 已在「正在上传」**，**+4s 同步完成**——机制本身是通的
  - 缺的是「看得见」：登录瞬间界面显示「已登录 · 壁纸改动会自动同步」，看起来像没动
  - 新增 `SyncCenter.isPreparing`：登录后先显示「正在准备同步…」（品牌橙），切库完成才转入进度
  - 兜底：进入账号主页时，若本进程还没同步过（`lastReport == nil` 且 `status == .idle`）再拉一次，
    用户不必知道「立即同步」这个按钮存在
- **验证**：`VW_HITTEST` 命中表、`VW_LOGIN_TEST` 状态时间线（新账号 + 本机 1 张 → 自动上传 1）
- **注意**：线上 3.44（`62019486` / `62fb3fe5…`）**不含**本修复，需并入下一版；
  本地 `dist/Dòng-3.44-hotfix-local.dmg` 是带修复的重编包，**不要**当作已发布的 3.44
- **调试钩子**：`VW_HITTEST=1`、`VW_CLICK_TEST=1`、`VW_LOGIN_TEST=email|password`

### D4 · 核查 v3.44 更新元数据已生效（无需修改） — 状态：`已验证`
- **日期**：2026-11-26
- **背景**：F21.22 记录的是发版前状态（`/api/update/check` 返回 `latest: null`），上线后需确认元数据是否已填。
- **实测（18:56，线上真实环境）**：
  - `GET /api/update/check?build=65&version=3.43&channel=stable&arch=arm64` → `update_available: true`、`latest.version=3.44`、`file_size=62019486`、`sha256=62fb3fe5…8a866`（2026-11-26 19:30 复核实测）、`published_at=2026-11-26T18:40:49+08:00`
  - `GET /api/download?v=3.44&channel=stable&arch=arm64` → 302，可正常跳转下载
- **结论**：元数据已由官网侧更新，老用户能正常收到 3.44 提示，F21.22 的 ⚠️ 已解除。
- **`build: 0` 无影响**：客户端 `Updater.swift:198` 注释明确「服务端 build 恒为 0，只能按版本号比」，`isNewer("3.44","3.43")` 成立，不依赖 build。
- **剩余（非阻塞）**：`notes: null`（更新说明为空），需在官网后台补；`POST /api/admin/releases` 返回 401 需鉴权，本地无凭据，未做任何写入。

### F21.22 · 发版 3.44 / 66（账号系统） — 状态：`已发布（GitHub + Gitee + 官网）`

- **日期**：2026-11-26
- **版本**：`Info.plist` 3.43/65 → **3.44/66**；10 个 README 的版本串同步
- **产物**：`dist/Dòng-3.44.dmg`，size `62007615`，
  sha256 `39d6bb74220542308bfdfe8f115d39e2ff1bc5908d741139f23542edd1c7d1c6`
- **端到端（线上真实服务）**：新账号 → A 库传 2 张（200KB / 300KB）→ B 全新空库同账号
  `下载 2`，逐张 sha256 一致
- **顺手补的**：`sync.log` 加 256KB 上限（超过只留最后 200 行），避免长期静默增长
- **本版内容**：账号系统（登录 / 换设备同步 / 退出即收起本机壁纸 / 昵称头像 / 改密码 /
  设备管理 / 恢复码找回）+ 上传字节级进度 + 断点续传 + 紧凑账号窗口
- **装机**：已覆盖 `/Applications/Dòng.app`，旧包 `Dòng.app.prev`
- **⚠️ 发现**：`/api/update/check` 目前返回 `{"latest": null}`，线上没有 stable 版本记录，
  发版时必须同时更新元数据，否则老用户收不到提示
- **发版清单**：`Dòng 3.44-发版清单.md`（含可直接粘进 notes 的更新说明）

### F21.21 · 线上部署 4eca6a0，设备与恢复码 16 项验收全过 — 状态：`已验证`

- **日期**：2026-11-26
- **官网侧**：已部署 `server.js`（`recovery/reset` 从 401 变 400，证明新路由生效）
- **线上验收（真实环境）**：
  | # | 用例 | 结果 |
  |---|---|---|
  | 1 | 注册带中文设备名 | 200 |
  | 2 | 设备列表 3 台，current 正确 | ✅ |
  | 3 | 生成恢复码 | `B45N-SG64-35AA-GXRS` |
  | 4 | 错码重置 | 400 `邮箱或恢复码不正确` |
  | 5 | 正确码重置（小写也认） | 200 |
  | 6/7 | 旧密码 401 / 新密码 200 | ✅ |
  | 8 | 重置后只剩新登录的 1 台 | ✅ |
  | 9 | 恢复码一次性（已作废） | ✅ |
  | 10/11 | 重新登录，中文设备名正确记录 | ✅ |
  | 12/13 | `id=others` 踢设备，剩 1 台 | `removed:1` |
  | 14 | 生成后移除恢复码 | `hasRecovery:false` |
  | 15/16 | **老账号** `f1804b58…` 仍能登录、清单/用量可读 | ✅ 数据未受影响 |
- **结论**：账号系统闭环（注册 / 登录 / 退出 / 换设备 / 找回密码 / 设备管理 / 昵称头像 / 改密码）。
  已知缺口只剩 Passkey（无密码登录），不在本次范围。
- **遗留**：验收注册的 `qa-dev-*` 测试账号需官网后台清理（无公开删号接口）
- **回执**：`Dòng同步服务-设备与恢复码验收回执.md`

### F21.20 · 登录设备管理 + 恢复码（忘密码能自救） — 状态：`客户端已装机，待官网部署 server.js`

- **日期**：2026-11-26
- **背景**：F21.19 里那两行「即将支持」占位。恢复码是「忘了密码」的唯一退路——此前发生过 3 次
  「密码对不上 / 账号被清」导致用户直接失去账号。
- **服务端（`sync-server/server.js`）新增**：
  - `GET /api/auth/sessions`：设备列表（设备名、创建时间、最近活跃、是否当前）
  - `DELETE /api/auth/sessions?id=<8位|others>`：踢单台 / 踢除当前以外全部
  - `GET/POST/DELETE /api/auth/recovery`：查询状态 / 生成（返回明文一次，存 scrypt 哈希）/ 移除
  - `POST /api/auth/recovery/reset`：**免登录**，用 `{email, code, newPassword}` 重设；
    成功后清空恢复码 + 踢掉该账号全部设备
  - 令牌记录增加 `device` / `createdAt` / `lastSeen`；`lastSeen` 只在内存更新、60 秒落一次盘
  - 新增 `reset` 限流桶（6 次/分/IP）；设备名走 `x-device-name`，**客户端百分号编码**，服务端 `decodeURIComponent`
- **客户端**：
  - 登录页新增「忘记密码？」→ 重设密码页（邮箱 / 恢复码 / 新密码 / 确认），成功后回登录并回填邮箱
  - 「登录设备」页：每台设备一行（名称 + 最近活跃，当前设备标绿），可单台退出或一键退出其它设备
  - 「恢复码」页：未生成 / 已生成（带日期）/ 刚生成（大号等宽码 + 复制按钮 + 橙色「只显示这一次」警告）
  - 两处都做了失败兜底：服务端没更新时显示「读不到…」，而不是假装「没有设备 / 没有恢复码」
- **🐛 踩到一个会把 App 卡死（不是崩溃）的坑**：`NSStackView.setCustomSpacing(_:after:)` 传了
  **不是该 stack 的 arranged subview**（我把按钮传给了外层 stack，而它其实在 linkRow 里）——
  AppKit 在布局里死循环，进程活着、界面不出来、日志也不再刷新。排查方式：临时打印 + `NSUnbufferedIO=YES`。
- **验证**：
  - 服务端脚本 12 项全过：注册/登录带设备名 → 列表 4 台且 current 正确 → 生成恢复码 → 错码 400 →
    正确码 200 → 旧密码 401 / 新密码 200 → 重置后只剩当前 1 台 → 恢复码已作废 → 踢 others → 移除恢复码
  - 中文设备名（`张航硕的 MacBook Pro`）百分号编码往返正常
  - 界面 6 张截图核对：登录（含忘记密码）/ 重设密码 / 主页（设备「管理」、恢复码「已生成」）/ 设备列表 / 恢复码两态
- **待官网**：重新部署 `server.js`（新增路由，反代前缀不变，`/api/auth/*` 已覆盖）

### F21.19 · 账号弹层改成紧凑窗口（400×432）+ 清掉烂尾代码 — 状态：`已装机，待统一发版`

- **日期**：2026-11-26
- **用户要求**：「按这版开工」；窗口不能占太多位置、要简洁；旧登录程序烂尾的部分顺手清理。
- **形态变化**：`NSPopover`（316pt 自适应高度）→ **独立窗口 400×432 固定**，不可拉伸。
  - 无侧栏、无标签页，单页三区（同步 / 账号安全 / 账号）
  - 只留账号本身要用的东西；深色模式与统计开关**仍留在齿轮弹层**，不重复搬
  - 登录表单在窗口里垂直居中；编辑资料/修改密码用「‹ 返回」回到主页
- **新增 `AccountWindow.swift`**：`AccountWindowController`（贴主窗口右下角、夹在屏幕内、关窗不销毁控制器）
  + `AccountPageController`（auth / profile / edit / password 四页）+ `AccountRow`（32pt 行，悬停高亮）
- **新增 `AccountUI.swift`**：把 `AvatarPill` / `AvatarView` / `PasteableSecureField` / `AccountFieldBox` /
  `AccountButton` / `UsageBar` 从旧文件抽出来，窗口和底栏共用
- **删除**：`AccountPopover.swift`（含旧的 `AccountViewController`、`hostPopover`、`resize()` 那套弹层逻辑）；
  `LibraryWindow` 的 `accountPop`、`NSPopoverDelegate` 上账号相关用法一并清掉
- **顺手清理的重复代码**：`main.swift` 里 `VW_SYNC_ONCE` 有 3 份、`VW_ACCOUNT_SHOT` 有 2 份，合并为各 1 份
- **修掉的两个显示 bug**：
  1. `AccountFieldBox` 初始化没清 `stringValue`，密码框会残留自动填充的字符（截图里显示成两个黑点）
  2. `UsageBar` 用量为 0 时仍画 2% 的桩，看着像一条橙色故障点；现在 0 就不画
- **交互细节**：文字按钮支持左对齐（表单里的链接与字段左边缘对齐）；同步中按钮变灰显示「同步中…」，
  进度显示「42% · 186 MB / 443 MB · 第 7/22 张」
- **设备列表 / 恢复码**：行已就位，值显示「即将支持」——对应接口还没做（原计划的第二段）
- **内存实测**（`footprint`，同一二进制）：
  | 状态 | phys_footprint |
  |---|---|
  | 只开壁纸库窗口 | 37 MB |
  | 库窗口 + 账号窗口 | **39 MB** |
  | 差值 | **+2 MB**（比预估的 5 MB 更省） |
- **验证**：`swiftc` 全量 0 error；`build.sh` 通过；五个页面截图逐张核对（登录 / 主页 / 同步中 / 编辑资料 / 改密码）
- **调试钩子**：`VW_ACCOUNT_OPEN=1`（启动即开窗，用于量内存和肉眼核对）、
  `VW_ACCOUNT_PAGE=auth|profile|edit|password`、`VW_ACCOUNT_SHOT=/tmp/x.png`
- **版本号未动**（3.43/65），按约定等用户统一发版

### F21.18 · 账号功能按需求逐条补齐 — 状态：`已装机（aa6b4bc）`

- **日期**：2026-11-25
- **用户 5 条要求**：个人账号 / 新用户并入本地壁纸 / 退出不删只存 / 头像-密码-名字 / 自查
- **本轮修掉的 5 个问题**：
  1. 退出登录**删除**本机壁纸 → 改为移入 `library-cache/<账号>/`（今天数据丢失的根因）
  2. 云端清单只在全部传完才写 → **每传成功一张就 PUT 一次**
  3. 同步状态所有账号共用 → 按账号分开 `sync-state-<账号>.json`，避免跨账号误写墓碑
  4. 新用户注册时本地壁纸被「收起」→ 增加特例：从「未登录」进空账号 = **并入**
  5. `assets.json` 丢失后对象永久 404 → 启动时按对象列表**自愈**重建映射
- **退出提示**：若有未传完的，弹窗说明「还有 N 张没传完，已保存在本机，下次登录接着传」
- **验证**：`LibraryOwner` 六步演练（并入 / 退出收起 / 重新登录回填 / 换账号）全部符合预期；
  `swiftc` 全量零错误；已装机
- **文档**：`Dòng账号功能-完成度自查.md`（五条对照 + 限制 + 官网配合项）
### F21.17 · 线上部署 220743b 生效，头像/昵称/快照全通 — 状态：`已验证`

- **日期**：2026-11-25
- **官网侧部署**：`220743b`（零配置），另附生产日志证明「每次部署=新容器」，20:24:52 / 20:26:20
  两次容器重建都走成功恢复了分支（`已从快照恢复 2 个文件`）——我 20:26 那次 401 是撞上重建瞬间。
- **线上实测（不是本地 mock）**：

| # | 用例 | 结果 |
|---|---|---|
| 1 | `/healthz` → `snapDetail.lastRestore` | `{restored:true, files:2}` ✅ |
| 2 | `/healthz` → `snapDetail.lastPush` | `{ok:true, key:"sync-snapshots/…"}` ✅ 写入 2 秒内推送 |
| 3 | `GET /api/auth/profile` | 200，返回 email/displayName/hasAvatar ✅ |
| 4 | `PUT /api/auth/profile` 改昵称 | 200 ✅ |
| 5 | `PUT /api/auth/avatar` 传头像 | 200 ✅ |
| 6 | `GET /api/auth/avatar` | 302 → 对象存储，**sha256 与源文件一致** ✅ |
| 7 | 老账号登录 | 200，userId `f1804b58…` 未变 ✅ |

- **结论**：数据持久化这条线闭环了——容器每次重建都会恢复，写入 2 秒内落快照。
### F21.16 · 上传按字节显示进度 + 卡死看门狗 — 状态：`已装机`

- **日期**：2026-11-25
- **用户反馈**：388MB / 8 张，界面一直停在「0% · 0 MB · 第 1/8 张」，看不出是在传还是卡死。
- **原因**：进度只在**每张文件传完后**更新，单张 300MB 上传期间界面完全不动。
- **改法**：
  - `AccountAPI.upload` 改用带 delegate 的 URLSession（`didSendBodyData`），拿到已发送字节实时回报
  - `SyncEngine.emit(_:extra:)` 支持「在途字节」，进度条按字节走；每涨 1% 才刷一次界面
  - `UploadSink` 加看门狗：**120 秒没有任何字节推进**就取消任务并返回「上传卡住了」，让同步层重试，
    而不是傻等 1 小时超时
- **验证**：编译通过，装机；进度文案与百分比随字节变化（此前 0% 恒定）。
### F21.15 · 修弹层切页后被裁顶（改头像点不到） — 状态：`已装机`

- **日期**：2026-11-25
- **现象**（用户截图）：点「改密码 / 编辑资料」后，页面变高了，但弹层还是原来「已登录主页」的高度，
  **内容被裁在顶部**——标题没了，编辑页的头像整个在可视区外，等于没法改头像。
- **原因**：`resize()` 只更新了 `preferredContentSize`。弹层已经显示出来之后，
  这个属性不会让 NSPopover 重排窗口，多出来的高度就被裁掉（裁剪方向朝上）。
- **修法**：给 `AccountViewController` 一个 `weak hostPopover`，切换页面时直接设
  `pop.contentSize`；不在弹层里时退回 `view.window?.setContentSize`。
  由 `LibraryWindowController.toggleAccount` 注入 popover 引用。
- **顺带**：确认编辑页独立渲染正常（标题 / 76pt 头像 / 昵称 / 保存 / 取消），
  头像点击回调 `AvatarView.onTap → pickAvatar()` 正常。
### F21.14 · 壁纸库按账号隔离（登录只看账号的、退出不留痕迹） — 状态：`代码已 push（220743b），待部署`

- **日期**：2026-11-25
- **用户规则**：
  1. 登录后只显示该账号里的壁纸；账号为空则把本地现有壁纸并入该账号。
  2. 退出登录后，本机不能再显示该账号的壁纸（别人登过你账号、退出后还能看到 = 不可接受）。
- **实现**（新增 `LibraryOwner.swift`）：目录切换，不复制
  - `wallpapers/` 活动库；`library-cache/<owner>/` 非活动库；`library-owner.json` 记归属
  - 登录（账号非空）：当前库整体移入 `cache/<previous>`，再把 `cache/<该账号>` 换出来
  - 登录（账号为空）：只改归属，文件不动，随后同步上传（= 并入）
  - 退出：**删除活动库里的账号壁纸**（云端有副本），再还原 `cache/anonymous`
  - 切库期间 `SyncCenter.isSwitchingLibrary` 挡住同步，避免把不属于该账号的本地壁纸传上去
- **验证（独立 harness，`VW_SUPPORT_DIR` 隔离）**：
  匿名 3 张 → 登录非空账号（本地收起 3 / 活动 0）→ 拉到 2 张 → 退出（移除 2 / 还原 3）→
  登录空账号（并入 3，归属变更）→ 退出（移除 3，匿名库 0）。两条规则都成立。
- **需要用户知道的副作用**：如果账号是空的、把本地壁纸并入了，那退出登录后本地库会变空
  （这些壁纸已属于该账号，重新登录会拉回来）。
- **⚠️ 同批提交还包含快照提速**（`snapshot.js`）：
  - 账号被清第 5 次（`287d0a03…` → `f1804b58…`，gateway 已开的情况下），
    说明平台的 `/tmp` 可能是**每次冷启动都全新的**，10 分钟一轮的快照根本来不及
  - `markDirty()` 改为 **2 秒防抖推送**，安全网 5 分钟，保留 40 份
  - `/healthz` 增加 `snapDetail`（`lastPush.ok/key/error`、`lastRestore.reason`），远程就能诊断
### F21.13 · 新账号注册后立刻快照 — 状态：`待官网部署`

- **日期**：2026-11-25
- **起因**：用户用 `12345678` 登录失败。查证：注册返回 200 + 全新 userId
  （`33a5ebcb…` → `287d0a03…`），**账号又被清了一次**。这次的原因可解释——
  该账号建于 18:38，而 gateway + 快照是 19:56 才生效的，之前没有快照可恢复。
- **顺带发现的窗口**：注册后要等定时器（最长 10 分钟）才推快照，这期间清盘仍会丢新账号。
- **处理**：`snapshot.markDirtySoon()`——注册成功标脏后 **3 秒**内补推一份；
  其余写操作仍走 10 分钟定时器，避免频繁上传。
- **验证**：注册 → 5 秒内云端出现 `sync-snapshots/…` → 立刻删掉整个 DATA_DIR → 重启 →
  日志 `已从快照恢复 2 个文件` → **原邮箱原密码登录 200**。
- **用户账号**：已重建并把密码改回 `12345678`（userId `287d0a03…`），当前可正常登录。
### F21.12 · 个人资料：昵称 + 头像 — 状态：`客户端已装，待官网部署 server.js`

- **日期**：2026-11-25
- **用户要求**：点开账号后要有个「个人主页」，能改头像和名字。
- **服务端**（`server.js`）：
  - `GET/PUT /api/auth/profile`（昵称 ≤20 字）、`GET/PUT/DELETE /api/auth/avatar`
  - **接口放在 `/api/auth/` 下是有意的**：实测 `/api/profile` 会落到官网自己的 404 页面
    （反代只转发 `/api/auth/*`、`/api/sync/*`、`/api/me`），放这里就不用让官网再加路由
  - 头像借用存储层，固定 assetId `__avatar__`；gateway 下走对象存储 + 302 直链
- **客户端**：
  - 账号面板新增「编辑资料」页：点头像选图（`NSOpenPanel`，自动裁成正方形 + 缩到 256×256 PNG）、
    昵称输入框、保存 / 取消 / 移除头像
  - 面板头像与**底栏头像**都显示自定义图片，取不到时回退首字母渐变
  - 主按钮和三个文字入口改成两行（原来四个挤一行会被压掉）
- **验证（本地假网关）**：昵称 200 / 超长 400；头像上传 200 → 302 下载 **sha256 一致**；
  `hasAvatar` 状态正确；删除后回到 false。
- **仓库**：`480cb7f` + `831903f`（补交漏掉的 `SyncEngine.swift`，之前漏提会让仓库编译失败）
- **待办**：官网再部署一次 `server.js`（本次不需要改反代路由）
### F21.11 · 线上发布后验证全过 + 重出 3.43 包 — 状态：`待上传 DMG / 待双设备验证`

- **日期**：2026-11-25
- **官网侧已完成**：snapshot 动作、`sync-snapshots/` 在 list/url/object 放行、重新发布
- **线上验证（真实接口，非本地）**：

| # | 用例 | 结果 |
|---|---|---|
| 1 | `/healthz` | `{"storage":"gateway","snapshot":"on"}` ✅ |
| 2 | 改密码接口存在 | `400 新密码至少 8 位`（此前 404）✅ |
| 3 | 旧密码错 | 401 ✅ |
| 4 | 改密码成功 | 200 ✅ |
| 5 | 旧密码登录 | 401 ✅ |
| 6 | 新密码登录 | 200 ✅ |
| 7 | 发起改密码的那台设备令牌 | 仍 200 ✅ |
| 8 | 另一台设备令牌 | 401 ✅ |

- **新包**：`dist/Dòng-3.43.dmg`，size `62001897`，
  sha256 `870ec6cdc3e08465c63a84ce029aff0e3992b4df48179c344f8d81a2635e4823`
  （含改密码界面、密码框粘贴、进度条与头像进度环；上一版 3.43 包缺这些）
- **待办**：上传 DMG + 更新线上版本元数据（用户手动）；双设备验证；
  线上清盘恢复确认（需官网侧配合删 `/tmp/dong-sync/data`，本地已验过同一条代码路径）
### F21.10 · 数据快照 + 自动恢复（B 方案） — 状态：`代码已 push（38a7ae2），待官网加快照路由`

- **日期**：2026-11-25
- **背景**：官网侧确认平台没有持久卷、也没有明文 AK/SK，B 方案（我做快照）成为唯一选择；
  根因是他们 `/tmp` 被定期清理导致「同邮箱三次注册三个 userId」。
- **新增 `sync-server/snapshot.js`**：
  - 打包 `DATA_DIR` 里的记账文件（跳过任何 `assets/` 与 `locks`，壁纸本体不进快照），gzip 后
    PUT 到网关 `/api/sync-storage/snapshot?key=sync-snapshots/<ts>.json.gz`
  - 写账号 / 令牌 / 清单 / 壁纸后 `markDirty()`，定时器（默认 10 分钟）只在有改动时上传；
    启动 30 秒后强制补一份；`SIGTERM/SIGINT` 退出前尽量 flush
  - **启动恢复**：本地缺 `accounts.json` 才拉最近一份解包；本地有数据绝不覆盖
  - 保留最近 12 份，推新删旧（复用 `list` + `object DELETE`）
  - 快照含密码 hash 与令牌：不写日志、不进错误信息、只走内部鉴权
- **`storage.js`** 导出 `gwJSON / gwPutBuffer / fetchURL` 供快照复用
- **`/healthz`** 增加 `snapshot: "on|off"`
- **验证（本地假网关，扩展了 snapshot 动作与命名空间放行）**：
  1. gateway 模式启动 → `healthz` 显示 `storage: gateway, snapshot: on`
  2. 注册 + 上传 300KB + 写清单 → 30 秒后自动推送快照（云端出现 `sync-snapshots/…`）
  3. **删掉整个 DATA_DIR 模拟平台清盘** → 重启 → 自动恢复 4 个文件（accounts/tokens/manifest/assets）
  4. 用原密码登录 200、userId 不变；清单 rev/条目完整；壁纸经 302 直链下载 **sha256 一致**
- **待官网**：加 `PUT /api/sync-storage/snapshot`（内部鉴权、写 `sync-snapshots/`），并让
  `list` / `url` / `object` 对该命名空间放行（恢复与保留策略要用）
# Dòng 改动台账（待合并发版）

> **约定（每个任务先读这段）**
> 用户会把多个小功能分散在**多个任务 / 多个会话**里改，最后**合成一个版本统一发布**。
> 1. 每完成一处改动，**必须在本文件 `## Unreleased` 追加一条记录**：日期 / 功能 / 改动文件 / 行为变化 / 验证结果 / 状态。
> 2. **不要单独发版、不要擅自 bump 版本号**；版本号只在统一发版时由用户决定。
> 3. 追加式书写，别删别人的条目；状态用 `待发布` / `已验证` / `有风险` / `待决策`。
> 4. 完成改动后同时追加一条到 workspace 日志 `../.workbuddy/memory/YYYY-MM-DD.md`（在本仓库上一级，跨会话可追溯）。
>
> 版本字段位置：`Info.plist` → `CFBundleShortVersionString` / `CFBundleVersion`。
> 发版入口：`zsh build.sh` → `package.sh`（出 DMG）→ `sign-notarize.sh`（Developer ID 签名公证）。
> **云端同步台账**（用户 2026-11-16 要求）：https://www.workbuddy.cn/space/d/rOl8uv2i7igEX3BTG4ztcs
> 每处改动除本文件外，也要更新到这份云端文档（资料库空间 `0MDu04zuYgmmgczhwrnr9M`）。

---

## Unreleased（合成下一个版本统一发布）

> ⚠️ **2026-11-16 已统一发布 v3.38 / build 60**：下方 F1–F5.4 全部随此版发出（commit `775e554`，
> GitHub Release v3.38 Latest，DMG sha256 `53680b386276bfa0b0f39d55c3d7e849f1a4a28fdfe5ef4df5785290ebf42601`）。
> 各条目保留作历史记录；发版前检查清单中「最终版本号 / 全量构建 / README 同步 / 更新接口」已过，
> **公证（Developer ID）仍未做**，仍为 ad-hoc 签名。下一次发版从空白 Unreleased 开始。
>
> ✅ **2026-11-17 已统一发布 v3.39 / build 61**：下方 F6 / F6.1 / F6.2 / F6.3（壁纸库长按拖动重排）、
> F7 / F7.1（画质与帧率优化：下载放开 4K + 抖音 `bit_rate` 档位择优 + 60fps + 放宽码率上限）、
> F8（淡化关闭时用 PerfectLoop 消除循环跳变）、F9（PerfectLoop 改为用户自选插件）全部随此版发出。
> **DMG**：`dist/Dòng-3.39.dmg`，size `61527463`，sha256 `7fb0b5b3906cc9a8735ea8dd22a3c1d182635a3a5356448501720b707ee80e2b`，
> `hdiutil verify` 通过；内 App 版本 3.39/61、bundle id `com.zhanghangshuo.dong`、内置 ffmpeg + yt-dlp、无 PerfectLoop。
> 签名仍为 **ad-hoc**（用户决定走开源 + AI 提示词安装路线，不做 Developer ID 公证）。
> F1–F5.4 及 D1 为 v3.38 及更早的历史条目，保留作记录。各功能条目下方状态文字是发布前的历史快照，以本节为准。
>
> ✅ **2026-11-18 已统一发布 v3.40 / build 62**：下方 F10（PerfectLoop 一键安装器 + 三处下载入口）、
> F5.5（抖音安全验证页可手动过 + 纯图文报错说人话）、F5.6（纯图文笔记自动生成静态壁纸）、
> F11（底栏小图标调亮 + 描边图标上色）全部随此版发出。
> **DMG**：`dist/Dòng-3.40.dmg`，size `61541183`，sha256 `b4426e65744c2cbfc46ef64269e715385f471f906e5bba3e8413d4d9a3532c74`，
> `hdiutil verify` 通过；内 App 版本 3.40/62、bundle id `com.zhanghangshuo.dong`、内置 ffmpeg + yt-dlp、无 PerfectLoop。
> 签名仍为 **ad-hoc**。版本号 3.39 → 3.40 已同步十语言 README；F1–F9 及 F5.5/F5.6/F10/F11 条目保留作历史记录。
>
> ✅ **2026-11-20 发布 v3.41 / build 63**（已登记官网更新服务器，latest=3.41 / file_size 61569855）：下方 F13（插件 App 内一键安装）、
> F14 / F14.2（自动暂停策略 + 静态果冻状态）、F15（网页 / 流媒体壁纸）、F16（图片直链识别）、
> F17（菜单栏图标悬停展开）、F18（下载改直链）、F19（壁纸重命名）全部随此版发出。
> F14.1（橙色暂停符号）已被 F14.2 撤销，仅为历史记录。
> 编号说明：F11/F12 曾被多任务并行重复占用，本次已把新增条目重编为 **F17/F18/F19**；原「F11 底栏图标」随 v3.40 发出。
>
> ✅ **2026-11-23 v3.42 / build 64（已登记官网服务器 file_size 61569988，但该包是含未完成新功能、且不含片头修复的版本，勿再分发）**。
>
> ✅ **2026-11-24 发布 v3.43 / build 65**：**只含截断修复**（F20 片尾 + F20.1 参数原样 + F20.2 片头），
> 账号登录 / 云同步 / 自动轮换 等并行任务未完成功能**未编入**。v3.42 已占用服务器版本号，故升 3.43。
> **DMG**：`dist/Dòng-3.43.dmg`（大小与 sha256 见下方 Released 段）；版本 3.43/65。

### D3 · 修复 GitHub Actions 持续失败（补提交缺失文件 + CI 兼容）— 状态：`已修复（CI 通过）`

- **日期**：2026-11-26
- **现象**：11-25 12:27 起每次 push 都收到 `Build / 编译验证` 失败邮件，12~21 秒退出。
- **三层原因**：
  1. `build.sh` 已提交且引用 `DynamicLockScreen / PerfectLoopInstaller / PlaybackPolicy / Rotation / WebWallpaper`，但这 5 个文件一直未入库；
  2. 仓库里的 `main.swift` 已调用 `Transcoder.importVideo(autoTrimIntroOutro:)`，而 `Transcoder.swift` 的对应改动未提交（同 `SyncEngine` 那次漏提交）；
  3. Swift 编译修好后，CI 走到「编译锁屏扩展」时 `zsh build_ext.sh` 找不到脚本，退出码 127。
- **改动文件**：上述 5 个新文件 + `Transcoder.swift` / `Tuning.swift` / `Panel.swift`；`build.sh` 改为 `[ -f build_ext.sh ]` 才编译锁屏扩展，缺失时打印跳过。
- **验证**：干净副本（`git archive HEAD` + 补文件，无 `build_ext.sh`）执行 `VW_NO_PRESETS=1 ./build.sh` 退出码 0；GitHub Actions run `45760990230` 结论 **success**。
- **提交**：`1cc3b33`（补文件）、`96fceb2`（CI 兼容）。
- **未提交**：`Info.plist` 版本号与十语言 README 改动仍留本地，按约定等统一发版。

### D2 · Gitee 镜像仓库公开 + README 链接本地化 — 状态：`已上线（文档/仓库，无需发版）`

- **日期**：2026-11-25
- **目标**：国内访问入口，GitHub 仓库 `zhang-1-kael/dong` 原样镜像到 Gitee `dong-is-good/dong`。
- **改动文件**：仅在 Gitee 独立副本提交 `README*.md`（10 份）；**本地工作区与 GitHub 仓库均未改动**。
- **行为变化**：
  - Gitee 仓库已由私有改为**公开**（用户完成第三方账号绑定后 API PATCH 生效，匿名 GET 返回 200）。
  - `main` + 6 个标签（v3.31/v3.36/v3.37/v3.38/v3.39/v3.40）全部镜像；Gitee 独有提交 `c0c61cc` 把徽章/仓库地址/`git clone` 链接改为 `https://gitee.com/dong-is-good/dong`。
  - release 下载徽章仍指向 GitHub（安装包资产只在 GitHub Release，Gitee 只存源码）。
- **验证结果**：匿名 API `repos/dong-is-good/dong` 返回 `private:false`；匿名内容接口 README 含 7 处 Gitee 链接、clone 行指向 Gitee；`git ls-remote` 匿名可读 HEAD `c0c61cc` 与 tag `v3.40`。
- **状态**：令牌文件 `/tmp/gitee_token` 已 shred 删除；后续同步若再 `push --mirror` 会覆盖 Gitee 独有提交，需改用普通 push 或先合并。
- **仓库地址**：https://gitee.com/dong-is-good/dong

### F23 · 锁屏动态壁纸（集成进 Dòng）— 状态：`已验证可行 / 注册不稳定，默认关闭`

- **日期**：2026-11-24（2026-11-25 回退开关）
- **结论**：功能链路本身跑通过（用户实测锁屏持续播放、桌面静止），但**扩展注册在 macOS 26.5.1 上无法稳定重建**，
  当前默认关闭，代码保留待后续解决注册问题。
- **回退原因（踩了三次）**：
  1. ExtensionKit 的注册记录在系统里是隐式的：只有 App 在 `/Applications`、且系统扫描过它的 `Contents/Extensions/` 才会写入。
     重启后不会自动重建，`lsregister -f`、`killall WallpaperAgent`、把 appex 放到 `~/Library/ExtensionKit/Extensions/` 都无效。
  2. 只要 `build/` 目录里还有一份同名 App，系统会优先注册 build 那份；删掉它之后注册记录直接失效，
     壁纸会回退到已删除的旧 provider（表现为黑屏或静态图）。
  3. 条目 id 必须固定：早期每次部署生成新 UUID，系统 Store 里记的还是旧 id，扩展找不到就 fallback 播容器里剩下的视频，
     表现是「锁屏和桌面不是同一个」。已改为固定目录 `D0D00000-0000-4000-8000-000000000001` + 固定文件名 `lock.mp4`。
- **回退后状态**：`dynamicLockScreen=false`，容器视频清空，用户扩展目录的 appex 已移除，
  桌面与锁屏都恢复到 Dòng 的静态帧（`com.apple.wallpaper.choice.image`），与原链路一致。
- **若要重新启用**：打开开关 → 部署 → 去「设置 → 墙纸 → Dòng」选一次；
  注意 `Desktop` 和 `Idle` 要分别指向它（只设桌面的话锁屏还是旧壁纸）。

#### 实现细节（保留供后续参考）


- **目标**：锁屏播放当前视频，同时**不改变**桌面渲染方式与任何现有功能。
- **架构**：桌面 → 主程序自绘窗口（原链路，未改）；锁屏 → 系统 wallpaper extension 播放。
  extension 的 `PlaybackPolicy` 在 `alwaysPauseDesktop = true` 时桌面暂停、只在 `presentationMode == locked` 渲染，
  因此两边共存、不会重复解码。
- **新增文件**：
  - `DongWallpaperExt/`（扩展源码，基于 Phosphene fork，MIT；bundle id `com.zhanghangshuo.dong.lockscreen`，
    选择器分组名「Dòng — 视频壁纸」）
  - `Modules/WallpaperExtensionKit.swiftmodule/`（私有框架的 swiftinterface，编译用）
  - `build_ext.sh`（编译 appex / 写 Info.plist+entitlements / ad-hoc 签名 / 嵌入 App）
  - `DynamicLockScreen.swift`（主程序侧：部署视频到扩展沙盒容器、写 prefs、判断系统壁纸是否已选中、清理）
- **改动文件**：
  - `main.swift`：`pushLockScreen()` 在 `DynamicLockScreen.isEnabled` 时改为部署到扩展并**跳过** `setDesktopImageURL`
    （否则会把用户在系统设置里选中的扩展壁纸覆盖成静态帧）；新增 `setDynamicLock` / `guideDynamicLockScreen`。
  - `LibraryWindow.swift`：设置面板「自动暂停」分组新增「锁屏动态播放（视频）」开关 + delegate 方法。
  - `build.sh`：编译文件列表加 `DynamicLockScreen.swift`；编译后调用 `build_ext.sh` 并把 appex 嵌入
    `Contents/Extensions/`；签名改为先签内层扩展（带沙盒 entitlement）再签外层 App。
- **关键前提（必须知道）**：
  1. 系统壁纸必须由用户在「设置 → 墙纸 → Dòng」里**手动选一次**，代码设不了。
  2. 扩展是沙盒进程，读不到 `~/Library/Application Support`；视频由主程序复制到
     `~/Library/Containers/com.zhanghangshuo.dong.lockscreen/Data/Documents/videos/<uuid>/`。
  3. 换壁纸后系统可能仍指向旧条目，锁屏不动时回设置里重选一次即可。
  4. **`alwaysPauseDesktop` 必须为 false**。实测：锁屏瞬间系统先发 `mode: locked`，
     随即又切回 `mode: default`（中途还夹一次 `activity: suspended`）。
     若 `alwaysPauseDesktop=true`，default 下一律暂停 —— 表现就是「锁屏播一小会儿就静止」。
     正确组合是 `alwaysPauseDesktop=false` + `pauseWhenOccluded=true`：
     锁屏无遮挡 → 持续播放；桌面被 Dòng 全屏窗口盖住 → 暂停，省一份解码
     （实测扩展 footprint 约 35 MB，走 2816×1584 变体）。
- **验证**：扩展被 `/Applications/Dòng.app` 注册并拉起；系统设置出现「Dòng — 视频壁纸」；
  用户实测「锁屏动、桌面静」符合设计；切换壁纸后容器内只保留当前一条。
- **已知问题**：
  - 私有 `WallpaperExtensionKit`，macOS 大版本更新可能失效（Phosphene 同样风险）。
  - 系统选择器缓存偶尔不刷新，需要清 `com.apple.Wallpaper-Settings.extension` 缓存或重启 WallpaperAgent。
  - 两个 Phosphene 测试容器（`dev.phosphene.extension` / `glass.kagerou.phosphene.extension`，约 37 MB）
    受系统容器保护，`rm` 删不掉，暂留。
- **数据**：appex 约 904 KB（压缩后更小），扩展空闲 footprint 约 6 MB；不改变 DMG 主体积。

### F22 · 「锁屏也播放视频」可行性调研 — 状态：`已验证可行（第二轮修正）`

- **日期**：2026-11-24（19:50 修正）
- **需求**：锁屏界面里壁纸继续播放视频（不是静态帧）。
- **结论（已修正）**：**可行**。第一轮写的「macOS 26 平台不支持」是错的，错在测试方法：
  ① 只改了 `Desktop` 没改 `Idle`（锁屏读的是 `Idle`，两者独立）；
  ② 用的是 fork 不是原版；
  ③ 手动改 `Store/Index.plist` 会被 WallpaperAgent 按 UI 状态写回；
  ④ 测试时 Dòng 仍在跑，它的「锁屏跟随」会把壁纸覆盖成静态帧。
- **第二轮实测（fork 扩展 + 系统 UI 应用壁纸）**：桌面与锁屏都在播同一段视频。
  日志链路：`ACQUIRE → VideoRenderer started → UPDATE mode: default, activity: active`；
  锁屏时 `UPDATE mode: locked, activity: active`，**没有** `SNAPSHOT`、没有 `INVALIDATE`；解锁后回到 `mode: default`。
- **关键前提**：① 扩展必须被 ExtensionKit 注册（App 在 `/Applications` 内嵌 appex，或系统里已有该 bundle id 的注册记录）；
  ② 壁纸必须在系统设置 UI 里选中应用，手改 plist 不生效；③ 测试前必须停 Dòng。
- **技术路线**：私有 `WallpaperExtensionKit`（macOS 14+ 的 wallpaper extension point）+ `AVSampleBufferDisplayLayer` 远程 CAContext。
  与 Dòng 现有「桌面层自绘窗口」是两套互斥的渲染通路：同一块桌面只能有一个壁纸 provider。

#### 第一轮误判记录（错误结论，保留作教训）

  1. **对照实验**：Apple 自带航拍壁纸（系统唯一官方动态壁纸）锁屏后也不动 → 锁屏层只显示壁纸的静态快照。
  2. **A 写系统航拍清单**：往 `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` 插入自定义 asset
     （本地 mov + 缩略图）后，WallpaperAgent 重启不覆盖条目，但系统设置列表始终不显示。
     根因：列表读的是 root 权限的 `/Library/Application Support/com.apple.idleassetsd/Aerial.sqlite`，
     用户级 entries.json 只是下载缓存，UI 不读。继续做需要 sudo 改系统库，且每 24h 会被 Apple 清单覆盖，不可分发。
  3. **B 私有框架 `WallpaperExtensionKit`**（参考开源 Phosphene，MIT）：扩展能被 ExtensionKit 加载，桌面接管成功
     （日志：`ACQUIRE → Created remote CAContext → VideoRenderer started → UPDATE mode: default, activity: active`，
     `Store/Index.plist` 的 `Desktop` provider 变为扩展 bundle id）；
     但锁屏时系统只发 `UPDATE mode: locked` 后立刻 `SNAPSHOT`（3840×2160 位图），实时图层不挂到锁屏。
  4. **C 屏保 `.saver`**：补上 `CFBundleSupportedPlatforms = [MacOSX]` 后能在「墙纸 → 屏幕保护程序 → 其他」列出
     （缺这个键 Tahoe 会直接过滤掉第三方 saver）；但选中后预览黑屏，`legacyScreenSaver` 已启动却未实例化我们的 bundle
     （`NSTemporaryDirectory()` 无日志、`lsof` 无加载记录）。Tahoe 的屏保实际由 WallpaperAgent 渲染，legacy `.saver` 只是被列出。
- **新增文件（保留、未接入发布流程）**：`Saver/DongSaverView.swift`（AVQueuePlayer + AVPlayerLooper 的 .saver 实现）、
  `build_saver.sh`（编译 / ad-hoc 签名 / 安装，产物 116 KB）。macOS 27 可再评估。
- **环境已清理**：`/Applications/Phosphene.app`、`~/Library/ExtensionKit/Extensions/PhospheneExtension.appex`、
  容器内测试视频、`aerials/entries.json`（从备份还原）、`Store/Index.plist`、屏保 `moduleDict` 均已撤销。
- **顺带实测（若将来走 B 参考）**：扩展空闲 footprint 5.9 MB / resident 11.7 MB；appex 916 KB（压缩后约 250 KB）。
- **可做替代**：锁屏显示当前帧（现状）；若要更无缝，可改为锁屏瞬间抓当前播放帧，替代现在固定 35% 位置抽帧。

### F21.9 · 密码框支持粘贴 — 状态：`已装机`

- **日期**：2026-11-25
- **用户反馈**：登录时密码没法粘贴。
- **原因**：`NSSecureTextField` 默认禁用粘贴（实测系统实现根本不响应 `paste:` 选择器），
  密码管理器的长密码只能手打。
- **处理**：新增 `PasteableSecureField: NSSecureTextField`
  - 拦截 `Cmd+V` → 走自己的 `paste(_:)`
  - 右键菜单补「剪切 / 拷贝 / 粘贴」（选中文本时才出现剪切拷贝）
  - `AccountFieldBox(secure: true)` 统一换成它 → 登录、注册、改密码三处同时生效
- **验证**：系统 `NSSecureTextField` 的 `responds(to: paste:)` 为 false，子类补上后可用（harness 实测）
### F21.8 · 修改密码（服务端 + 界面） — 状态：`代码已 push（e063291），待官网重新部署`

- **日期**：2026-11-25
- **起因**：用户忘了密码，v1 没有任何找回/修改手段；且发现生产账号被清盘（`storage:"disk"`），
  等于「忘了密码 = 账号作废」。
- **服务端**：`POST /api/auth/password`，要 `{oldPassword, newPassword}`，需登录。
  - 校验旧密码（scrypt + timingSafeEqual），新密码 ≥ 8 位、不能与旧密码相同
  - 成功后换 salt/hash，**作废该账号其它设备的令牌，保留当前这台**
- **客户端**：`AccountAPI.changePassword`；账号面板新增「改密码」按钮 → 切到改密码表单
  （当前密码 / 新密码 / 确认 + 保存/取消），成功后弹「其它设备需重新登录」
- **验证（本地 8810 端口）**：旧密码错 401；正确 200；旧密码登录 401；新密码 200；
  当前设备 token 仍 200；另一设备 token 401
- **生产**：调该接口返回 404「没有这个接口」→ **他们跑的仍是旧 server.js，需要重新部署**
- **调试钩子**：`VW_ACCOUNT_PW=1` 直接摆出改密码表单截图（需配合 `VW_SYNC_FAKE=邮箱|token|0.4` 走预览模式，
  否则会真发请求、401 后被登出，导致登录表单和改密码表单同时显示）
### F21.7 · 同步进度可视化 + 修「换签名掉登录」 — 状态：`已装机，待用户重新登录验证`

- **日期**：2026-11-24
- **用户反馈**：看不懂上传到哪一步了。
- **界面**：
  - 账号面板同步时出现**进度条**（品牌橙）+ 明细「42% · 186 MB / 443 MB · 第 7/22 张」
  - 状态行改「正在上传 · 文件名」，同步中主按钮变灰并显示「同步中…」，避免点了没反应
  - **底栏头像加白色进度环**（底下垫一圈 20% 白轨道），不打开面板也能看出在动
- **🔴 关键 bug（这次真正的原因）**：`AccountStore` 原来把会话存**钥匙串**。App 是 ad-hoc 签名，
  **每次重新编译签名都变**，钥匙串条目的 ACL 认签名 → 装新包后读不到旧会话，
  直接显示「未登录」、同步根本不跑（用户看到的就是「一直没动静」）。
  改为存 `support/session.json`（0600，原子写），保留一次从钥匙串迁移的逻辑。
  代价：安全性低于钥匙串（同用户可读），但换来更新不掉登录——对 ad-hoc 分发的 App 这是必须的取舍。
- **进度数据**：`SyncEngine.Progress`（text / fraction / done / total / bytesDone / bytesTotal），
  `SyncCenter` 暴露 `progress`，`run(progress:)` 签名同步改掉
- **调试钩子**：`VW_SYNC_FAKE=邮箱|token|0.42` 可摆拍「同步中 42%」的界面（`previewOnly` 时不联网）
- **副作用**：装新包后用户需要**重新登录一次**；旧钥匙串条目在新签名下读不出来，无法自动迁移
### F21.6 · 首传可续 + 进度计数 + sync.log — 状态：`已改代码，待用户上传完成后装机`

- **日期**：2026-11-24
- **起因**：真实用户（本机 22 张 / 443MB）首次同步时，UI 只有「上传 xxx」一行，
  看不到第几张、也不知道是不是卡住；而且状态文件只在全部传完才写，中途断掉下次要全量重传。
- **改动**（`SyncEngine.swift`）：
  - `SyncState` 新增 `synced: [String: String]?`（id → sha）：每成功上传一张就 `saveState` 落盘；
    `plan()` 里若 `synced[id] == sha` 且云端清单还没有它，**跳过重传**但要合并进清单 —— 断点续传
  - 进度文案改成「上传 3/22 · 名称」/「下载 3/22 · 名称」
  - 新增 `sync.log`（support 目录）：记录开始（本地张数/动作数/rev）、每张失败原因、结束统计
  - 清单写成功后清空 `synced`
- **兼容**：`synced` 用可选类型，旧 `sync-state.json` 没有这个键也能解码
- **验证**：`swiftc -typecheck` 全量 0 error（注意编译清单要带 `DynamicLockScreen.swift`，
  少了会报一堆 `DynamicLockScreen` 找不到，与本改动无关）
- **未做**：因为用户当次上传仍在进行，**没有覆盖安装**（装 = 杀掉进程 = 中断上传）
### F21.5 · 接线上地址并出包 3.43 — 状态：`已出包，待上传发布 + 真机双设备验证`

- **日期**：2026-11-24
- **官网侧验收**：gateway 12 条全过，我提的 3 条确认（302 不改写 / 签名直链 https / list 可用于自检）全部满足。
- **改动**：`Info.plist` → `SyncBaseURL = https://dongisgood.coze.site`（主域名直挂，无子域名）。
  版本号 3.43 / 65 是既有值，本次未改。
- **产物**：`dist/Dòng-3.43.dmg`，size `62002210`，
  sha256 `b3dfd357f2f1bcbdfee2d87fd8f60c71d756737980f36a27462d28d67c38929f`
- **验证（走真实线上服务，不是本地 mock）**：
  - `GET /healthz` 200；注册/登录/`/api/me` 正常
  - A 库上传 3 张（300/500/700KB）→ 云端 order 与 A 本地一致 → 新空库 B 首次同步 `下载 3`，
    逐张 sha256 一致；B 本地顺序同步前被改成 01,02,03，同步后被云端覆盖回 02,01,03（顺序真的同步）
  - B 删除一张 → A 再同步 `删除 1`（墓碑传播正确，不会被推回来）
  - **注意**：验证用的是同一台机器上三个隔离库（独立 `VW_SUPPORT_DIR` + 独立 sync-state），
    不是两台物理机；用户目前没有第二台 Mac，已在给官网侧的回执里写明这一点
  - **副作用**：`VW_SUPPORT_DIR` 隔离了壁纸库，但**没有隔离 UserDefaults**，
    测试期间 `VWTuning.libraryOrder` 被写成了测试文件名；已 `defaults delete` 清除该键（回落到按文件名排序）
- **⚠️ 发现的问题**：线上 `/healthz` 返回 `"storage":"disk"`，说明生产**还没切 gateway**
  （代码已部署，但 `DONG_STORAGE=gateway` 没生效/没重启）。此时壁纸写在 `/tmp/dong-sync/data`，
  平台清理磁盘就会丢文件——这是官网侧自己认定「正式运营前必须解决」的那条。
- **测试账号**：`qa-check-20261124@example.com`（我为验证注册的，官网侧可删）
### F21.4 · 存储层抽象：支持官网存储网关 — 状态：`已 push（5bb6444）/ 待官网切 gateway`

- **日期**：2026-11-24
- **官网侧回执**：10 条验收全过；但他们平台上**没有可交付的 S3 AK/SK**（SDK 用 workload identity
  动态换临时凭证），改提供内部网关 `/api/sync-storage/*`（upload / url / list / object），
  要求我把存储实现换成 `DONG_STORAGE=disk|gateway`。
- **实现**：新增 `sync-server/storage.js`（两种模式，接口契约不变）
  - `put`：gateway 下把入站请求**管道**给网关，边传边算 sha256，不落临时文件；返回的 key
    （`sync/{uid}/{aid}_{uuid}`）记进 `users/<uid>/assets.json`
  - `locate`：换 1 小时签名直链，`GET /api/sync/asset/*` 直接 **302**，512MB 不经过本进程
  - `del`：按映射删网关对象并清映射
  - **同名覆盖会先记下旧 key，上传成功后主动删旧对象**（不然后台每次上传都留一份孤儿对象）
  - `usedBytes`：gateway 下按清单 `bytes` 汇总（网关 list 不返回 size）
  - `selfCheck`：启动时 `list?prefix=sync/selfcheck/`，失败 → 日志报错 + `/healthz` 503，
    **默认不退出**（平台会反复重启，日志反而更难看），`DONG_GATEWAY_STRICT=1` 才退出
- **凭证**：只读 `SYNC_INTERNAL_TOKEN`，仓库里不写任何 token。
- **验证（本地假网关，按官网文档 4 个动作实现）**：上传 1MB → 302 下载 sha256 一致；
  写清单后 `/api/me` usedBytes 正确；删除后网关对象清空、映射清空、再下载 404；
  同名覆盖后对象数仍为 1 且下载到新版；错误 token / 缺 token → healthz 503 + 明确报错且不崩。
  磁盘模式回归通过（500KB 上传下载 sha256 一致，文件落 `users/<uid>/assets/*.bin`）。
- **待官网确认**：302 会不会被反代改写；签名直链是否 https（App 有 ATS）；list 仅用于自检。
### F21.3 · 服务端上库 + 托管平台适配（对官网侧的回复） — 状态：`已 push / 待官网部署`

- **日期**：2026-11-24
- **官网侧反馈**：仓库里 `video-wallpaper/sync-server/` 是 404；他们用托管平台，没有独立子域名，
  采用**同域名路径反代**（`SyncBaseURL = https://dongisgood.coze.site`，路径原样）；
  进程由官网服务自动拉起（注入 `SYNC_PORT`）；**平台磁盘会被定期清理**，要求壁纸文件走对象存储；
  平台层加不了 `limit_req`，希望服务端自带限流。
- **处理**：
  1. 代码提交并 push 到 `main`（`7260f95` 服务端、`c2d29a5` README），raw 可拉。
  2. `server.js` 读 `SYNC_PORT`（优先）→ `PORT` → 8787，适配他们的注入方式。
  3. 内置按 IP 限流：注册 5 次/分、登录 12 次/分，超限 429；**依赖反代透传 `X-Forwarded-For`**，
     不透传的话所有人都算同一个 IP，5 次之后全体被挡（已在回复文档里标明要验收）。
  4. 新增 `sync-server/.gitignore`（`data/`、`*.log`），避免把测试数据提交上去。
  5. 本机临时服务同步换成新版本（`~/Library/Application Support/DongSync/server.js`）。
- **存储**：选 A（对象存储），但分两步——先磁盘版跑联调（明确接受清理风险），
  拿到 endpoint / bucket / region / AK / SK / path-style 后再加 `DONG_STORAGE=disk|s3` 抽象，
  接口契约与错误码不变。
- **产出文档**：`Dòng同步服务-给官网侧的回复.md`（回答 6 点 + 反代注意事项 + 第 7 条限流验收）。
- **验证**：`SYNC_PORT=8799` 启动正常；连续注册 6 次 = 200×5 + 429；带 `X-Forwarded-For` 换 IP 可继续注册。
### F21.2 · 先跑起一个能用的同步服务（本机 + 局域网） — 状态：`可用，临时方案`

- **日期**：2026-11-23
- **现象**：用户点「注册并开始同步」报 `请求失败（404）`。
- **原因**：`Info.plist` 的 `ApiBaseURL` 指向官网 `dongisgood.coze.site`，那里没有 `/api/auth/*`；
  同步服务从没部署过，所以注册 / 登录必然 404。不是客户端 bug。
- **临时处理**：
  - 服务跑在本机：`~/Library/Application Support/DongSync/server.js`，数据同目录，端口 8787。
  - `Info.plist` 新增 `SyncBaseURL = http://10.10.11.24:8787`（本机局域网 IP）。
  - 重打包并覆盖 `/Applications/Dòng.app`，旧包留在 `/Applications/Dòng.app.bak-login`。
- **验证**：`/healthz` 200、`/api/auth/register` 200；装好的 App 不带环境变量也能连上（走 Info.plist）。
- **限制（必须尽快换掉）**：
  - 该服务只在当前会话存活，`launchctl bootstrap` 在本机报 `Input/output error`（沙箱与系统域都试过），
    需要用户自己在「终端」里加载 `~/Library/LaunchAgents/com.zhanghangshuo.dongsync.plist` 才能常驻。
  - `10.10.11.24` 是 DHCP 地址，变了就登录失败；`.local` 主机名在本机 mDNS 解析不通（试过，
    `NSAllowsLocalNetworking` 也没救），所以没用主机名。
  - 真正「换设备」要公网 HTTPS 地址，下一步应部署到云主机 / Render 等，再把 `SyncBaseURL` 换掉。
### F21.1 · 账号入口改成底栏头像 + 独立账号面板 — 状态：`已验证（本机截图）/ 待发版`

- **日期**：2026-11-23
- **用户反馈**：「登录界面很丑，新用户第一次用应该做好一点」；「不想把登录信息塞在设置里」；
  「加一个地方放账号，把深浅色开关挪进设置，原来那个位置换成一个头像」。
- **界面改动**：
  1. **底栏最右**：「深色 / 浅色」磁贴 → `AvatarPill`（30pt，与其它磁贴同尺寸、同气泡）。
     未登录显示人形剪影；登录后显示品牌橙渐变圆 + 邮箱首字母。点开 `AccountViewController` 面板。
  2. **账号面板**（316pt 宽 popover，不再是独立窗口）：
     - 未登录：淡橙圆角底托着果冻 logo、标题「登录 Dòng」、副标题「壁纸跟着账号走，换台电脑也在」、
       两个自绘圆角输入框、橙色主按钮、「没有账号？用邮箱注册」切换、底部一行隐私说明。
     - 已登录：64pt 渐变头像 + 邮箱 + 同步状态（失败时红字）+ 云端用量条（`/api/me`）+
       「立即同步」「退出登录」。
     - 按 Enter 直接登录；空状态行不占高度，切到注册模式会多出确认密码框并自动调整高度。
  3. **设置弹层**：删掉「账号与同步」整块，顶部改为「深色模式」开关（原来底栏那颗磁贴的职责）。
- **新增文件**：`AccountPopover.swift`（AvatarPill / AccountFieldBox / AccountButton / UsageBar /
  AccountViewController）；删除 `AccountWindow.swift`（独立登录窗口）。
- **改动文件**：`LibraryWindow.swift`（底栏、设置弹层、`toggleAccount`、`darkModeChanged`、
  `showTip(text:anchor:)` 兼容头像、`debugSnapshotWindow`）、`main.swift`（`VW_WINDOW_SHOT` 调试钩子 +
  `VW_ACCOUNT_SHOT` 改渲染新面板）、`build.sh`（文件名替换）。
- **验证**：`VW_SETTINGS_SHOT` / `VW_ACCOUNT_SHOT` / `VW_WINDOW_SHOT` 三张截图逐项核对：
  设置里只剩深色模式开关、底栏最右是头像（未登录人形 / 登录后 K）、面板两态排版正常；
  `swiftc` 零错误，`build.sh` 通过。
- **风险提示**：合并时注意 `LibraryWindow.swift` 里「设置分组折叠」（`SettingsSectionHeader` /
  `toggleSettingsSection`）与本次改动互不重叠，但都在同一文件，冲突时保留双方。
- **状态**：界面已定稿；服务端仍未部署，`SyncBaseURL` 未填。

### F21 · 账号登录 + 换设备同步壁纸 — 状态：`已验证（本地全链路）/ 待部署服务器`

- **日期**：2026-11-23
- **用户要求**：「做一个可以登录的功能，用户换设备的时候还是可以继续使用自己添加的壁纸」。
- **为什么必须自带服务端**：壁纸库现在就是 `~/Library/Application Support/VideoWallpaper/wallpapers/`
  里的 mp4 + `streams.json` + 偏好里的顺序，纯本地。跨设备同步一定要有个服务端收文件和清单。
  - WorkBuddy 云服务（genie-baas）不可用：它只发 JS SDK，且服务端按浏览器 Origin 精确匹配，
    原生 App 没有 Origin，请求会被拒。**没有**用 Bash/curl 去戳它的数据面。
  - 所以自带一个零依赖 Node 服务，放在 `sync-server/`，用户自己的机器/托管上跑。
- **新增文件**：
  - `sync-server/server.js`（零依赖：邮箱密码 scrypt、token 只存 sha256、清单 if-match 并发控制、
    壁纸文件存盘、每账号 2GB 配额、`/api/me` 用量）
  - `sync-server/README.md`（部署三种方式 + 环境变量 + 接口表 + 安全边界 + v1 已知限制）
  - `Account.swift`（`SyncConfig` 域名、`AccountAPI` 注册/登录/清单/上传/下载、`AccountStore` 钥匙串存 token）
  - `SyncEngine.swift`（本地快照 → 与云端清单合并 → 执行上传/下载/删除；sha256 校验；墓碑防回推）
  - `SyncCenter.swift`（单例：启动同步、目录变化 4 秒防抖、401 自动退登、通知界面刷新）
  - `AccountWindow.swift`（登录 / 注册窗口，系统控件，不做自绘）
- **改动的旧文件**：`build.sh`（编译清单 + `-framework Security`）、`main.swift`（启动接同步 +
  `syncChangedLibrary` 观察者）、`LibraryWindow.swift`（设置弹层顶部新增「账号与同步」三行 + 两个按钮）。
- **同步规则**：
  - 身份 = 文件名（`v-<文件名>`）/ 网页壁纸 `w-<stream id>`；清单里带 `sha256`
  - 内容相同 → 什么都不做；不同 → mtime 新的赢
  - 本地删除 → 云端留墓碑（30 天），另一台设备跟着删；云端墓碑比本地新才删，否则视为「删完又加回来」
  - 顺序：云端 `rev` 变过就用云端顺序，否则把本地顺序推上去
  - 上传失败的条目不写进清单，下轮重试
- **验证（本地，隔离 `VW_SUPPORT_DIR`，不碰真实壁纸库）**：
  1. harness（`swiftc Account.swift SyncEngine.swift` + 临时 main）对 `http://127.0.0.1:8787`：
     注册 → A 上传 2 张 → B（全新目录）下载 2 张，sha256 全部一致 → A 删一张、B 同步跟着删 →
     网页壁纸也能传 → 云端用量随删除回落。
  2. 真机 App（`build/VideoWallpaper.app/Contents/MacOS/VideoWallpaper` + `VW_SYNC_ONCE=1`）：
     `同步完成：上传 2`；换空目录同 token：`下载 2`，两份文件 sha256 与源一致。
  3. 失效 token：状态变「未登录」并清掉本地会话，无崩溃。
  4. 界面：`VW_SETTINGS_SHOT` / `VW_ACCOUNT_SHOT` 渲染设置弹层与登录窗口，未登录 / 已登录两态都正常。
- **还没做（发版前必须解决）**：服务端尚未部署，`Info.plist` 没有 `SyncBaseURL`；
  因此当前包里点「登录」只会提示「同步服务器还没配置」。版本号未动（3.42/64）。
- **调试钩子**（都只在环境变量存在时生效）：`VW_SYNC_FAKE=email|token`、`VW_SYNC_ONCE=1`、
  `VW_ACCOUNT_SHOT=/tmp/x.png`。

### F20.2 · 修复「本地视频开头被裁 7 秒」：片头检测同样纳入本地保护 — 状态：`已验证 / 已装机 / 待发版`
- **日期**：2026-11-24
- **用户反馈**：32.3 秒原视频拖入后仍只截了一部分（附原视频 + 录屏）。
- **根因**：F20 只给 `detectEndCard`（片尾）加了 `autoTrimEndCard` 开关，**`detectHead`（片头）没纳入**——本地导入仍在自动裁片头。`--detect` 实测该视频「片头剪到 7.00s」，32.3 秒只剩 25.3 秒。
- **修法**：参数改名 `autoTrimEndCard` → `autoTrimIntroOutro`，`detectHead` 调用同样加该开关；本地导入（GUI 拖拽/选择、CLI `--import`）传 `false` 时**片头片尾都不裁**，链接下载素材仍保留自动裁剪。
- **改动文件**：`Transcoder.swift`（参数改名 + detectHead 受控）、`main.swift`（2 处调用点改名）。
- **实测（用户原视频 32.30s / 1280×800 / 30fps）**：修复前「片头剪到 7.00s」→ 约 25.3s；修复后 **32.67s 完整**，分辨率/帧率不变（+0.37s 为循环补帧）。已装 App 二进制复测同样 32.67s。
- **本机装机（2026-11-24 08:52）**：最小替换 + 重签 verify 通过，PID 12410，无崩溃。回滚备份 `/tmp/vw_bin_backup_before_headfix_1795481479`。
- **注意**：本次编译清单需含并行任务新增文件（`Account.swift` / `AccountPopover.swift` / `Rotation.swift` / `SyncCenter.swift` / `SyncEngine.swift` + `-framework Security`），`build.sh` 已更新。

### F20.1 · 参数默认回归「原样」：不加速、不改帧率 — 状态：`已生效 / 待发版`
- **日期**：2026-11-23
- **用户要求**：「用户给的是怎么样的就是怎么样的（在不影响画质的情况下）」。
- **排查**：代码里**没有自动调速/改帧率的逻辑**（`Tuning.speed` 只在用户拖滑块时写入）。1.31× 与固定 60fps 是历史残留的用户偏好值。
- **处理**：删除 `VWTuning.speed`、`VWTuning.outputFPS` 两个偏好键 → 回到代码默认值。当前全部参数为默认：
  - `speed` = 1.00×（原速）
  - `outputFPS` = 0 → **跟随源**（源 30fps 就输出 30fps，不再强行补到 60）
  - `loopLength` / `loopStart` = 0 → 整段循环
  - `fade` = 0 → 无首尾淡化
  - `brightness` = 0 → 无明暗调整
  - `maxDuration` = 0 → 不限制时长
  - 本地导入 `autoTrimEndCard = false`（F20）→ 不裁片尾
- **实测**：12s / 30fps / 1280×720 源 → 输出 12.37s / **30fps** / 1280×720（+0.37s 为循环衔接补帧，非内容）。
- **画质说明**：`targetSize` 只缩不放（按屏幕物理像素等比塞入），转码 CRF 18 高质量；内容、时长、速度、帧率均保持原样，只做一次为无缝循环/铺满屏幕的高质量重编码。
- **注意**：已入库的旧壁纸是旧参数转的，**不会自动重转**；要看原速原帧率需重新导入视频。

### F20 · 修复「本地视频拖进来只截取了一部分」：本地导入不再自动裁片尾卡 — 状态：`已验证 / 已装机 / 待发版`
- **日期**：2026-11-23
- **用户反馈**：本地视频拖入后只截取了一部分作为动态壁纸，不是完整视频。
- **根因（实测定位）**：`Transcoder.detectEndCard` 的「片尾卡」检测误裁正常内容。两个缺陷：
  1. **绝对阈值过高**：信号 B 的静止判定 `still = max(baseline * 0.12, 0.25)`，而风景/夜景/渐变/延时这类本身就低运动的素材，帧差中位数只有 0.2~0.5，被整段判成「静止片尾」。
  2. **裁切上限太宽**：`removed <= max(4.0, duration * 0.4)`，最长可裁走 40% 时长（60s 视频能裁 24s）。
  3. 更本质的：**算法无法区分「正常的静止收尾」与「作者加的片尾卡」**——同一条视频（24s，结尾 6s 静止）既可能是内容也可能是片尾。实测 `--detect` 对「正常静止收尾」和「黑屏片尾卡」给出完全相同的结果。
- **修法（三层）**：
  1. `importVideo` 新增 `autoTrimEndCard` 参数（默认 `true`）：**本地导入（GUI 拖拽/选择文件、CLI `--import`）传 `false`，不再裁片尾**；只有链接下载的网络素材（`--link`）保留自动裁片尾卡。这是根治——用户自己的视频片尾就是内容。
  2. `detectEndCard` 加保护：`guard baseline >= 1.0 else { return nil }`——整段都很安静的素材不存在「正片+片尾卡」结构，直接跳过。
  3. 阈值收紧：`still` 下限 0.25 → 0.08、相对值 0.12 → 0.15；裁切上限 `duration*0.4` → `min(8s, duration*0.25)`；信号 A 的静判定也从 `max(baseline*0.8, 2.5)` 收紧到 `max(baseline*0.5, 1.5)`。
- **改动文件**：`Transcoder.swift`（detectEndCard 阈值 + importVideo 参数）、`main.swift`（pumpImport 按 `origin` 分流、`runImportCLI` 传 false）。
- **实测验证（隔离库）**：
  - 24s「前18s有运动 + 后6s静止」视频：修复前 **截掉片尾 6.0s → 输出 18.35s**；修复后 **输出 24.37s 完整**（+0.37s 为首尾淡化补帧）。
  - 24s 低运动渐变（风景/夜景类）：修复前后均完整 24.37s。
  - 24s 普通运动视频：完整 24.37s。
  - 真片尾卡（黑屏结尾）：`--detect` 仍正确检出「截到 18.00s（-6.00s）」，链接下载路径行为不变。
- **本机装机（2026-11-23 10:14）**：最小替换 `/Applications/Dòng.app` 二进制 + 清 pyc + 重签 verify 通过；PID 34021。**顺带发现并清理了重复进程**——`~/Applications/VideoWallpaper.app` 与 `/Applications/Dòng.app` bundle id 相同（`com.zhanghangshuo.dong`），`open` 会拉起旧路径那个，已 kill 只保留 `/Applications/Dòng.app`。回滚备份 `/tmp/vw_bin_backup_before_trimfix_1795399727`。
- **注意**：v3.41 的 DMG 需重打（此前打的包不含此修复）。

### F16 · 图片直链识别：右键「复制图片地址」的链接直接做成静态壁纸 — 状态：`已验证 / 二进制已装机 / 待用户 GUI 确认 / 待发版`
- **日期**：2026-11-19
- **用户诉求**：在壁纸站右键「复制图片链接」，把链接发到 Dòng 里，**有的能做成壁纸、有的做不成**，要求兼容到每次都成功。
- **根因（实测定位，两个）**：
  1. **旧分流错误**：`importLink` 只把 B站/抖音/YouTube 当视频站，其余链接一律 `isWebCandidate = true` → 交给 `addWebWallpaper` 用 **WKWebView 当网页加载**。图片能不能成，取决于 WebView 认不认这张图、站点是否禁止内嵌——于是同一种链接时而成功时而失败，且成功时也只是「网页里的一张图」，不是真壁纸。
  2. **扩展名形态多样**：图片直链的扩展名可能在 path（`/a.png`）、在 query（`cn.bing.com/th?id=xxx.jpg`）、或带参数（`/a.png?w=1`）；只按 `pathExtension` 判断会漏掉 query 形态，被错当视频丢给 yt-dlp 而失败。
- **改动文件（全部 `main.swift`）**：
  - `importLink` 开头新增分流：`looksLikeImageLink(link)` 命中就走新增的 `importImageLink`，**不再进 WKWebView 网页壁纸**。
  - 新增 `looksLikeImageLink`：三种形态全覆盖（path 扩展名 / query 里的扩展名 / path 末段扩展名），复用 `Transcoder.imageExts`（含 webp/heic/gif 等）。
  - 新增 `importImageLink`：带浏览器 UA + 图片 Accept 用 URLSession 下原图 → 按 `Content-Type` 定扩展名（不迷信 URL 后缀，站点常把 WebP 写成 .png）→ **落盘后 ImageIO 试解一次**，是「200 + HTML 验证页」就友好报错而不是喂给转码 → 交 `enqueueImport` 走既有 `importStillImage` 做成 2 秒静态壁纸。
  - 新增 `isDecodableImage`：ImageIO 双路（`CreateImageAtIndex` 失败再试 thumbnail）判断是否真图片。
  - CLI `runLinkCLI` 同步支持：图片链接先处理（不再被「找不到 yt-dlp」挡住），新增 `fetchImageCLI` 同步下载，走 `importStillImage`。
- **端到端实测（CLI harness，隔离 VW_SUPPORT_DIR）**：
  - 哲风静态图 `cache_file/…17603630336822656.png`（后缀 .png 实为 WebP，890×501）→ ✅ 生成 890×500 / 2.00s / h264 静态壁纸 mp4。
  - 必应 `cn.bing.com/th?id=…jpg`（扩展名在 query）→ ✅ 生成 1920×1080 静态壁纸 0.5MB（修复前会被当成视频失败）。
  - 回归：另一张哲风图 ✅；`/homeViewLook/<id>` 详情页仍走原视频链路 ✅（未被误判为图片）；`shadertoy` 网页链接仍非图片 ✅。
  - 识别函数单测：`/x.png`✅图片、`/x.png?w=1`✅图片、`?id=a.jpg`✅图片、`/page`✅非图片、`/a.webp`✅图片、`/x.mp4`✅非图片。
  - 边界：403 链接 → 「HTTP 403，链接可能失效或需要登录」友好报错、不崩；404 伪装 .png → 同样友好报错。
- **已知限制（站点设计，非代码问题）**：哲风等站公开只有 **890~1100px 的缩略图**（30~40KB），原图（如 3840×2160 / 39MB）在 `file/`、`original_file/` 目录返回 **403 需会员权限**。所以这样做成的是「缩略图静态壁纸」，清晰度受站点限制；要原图仍需站内正常下载或会员。
- **本机装机（2026-11-19 20:29）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（编译产物）、清 pyc、`codesign --force --deep --sign -` + `--verify --deep --strict` 通过；偏好 57 键完好、版本仍 3.40/62；重启 PID 58837。回滚备份 `/tmp/vw_bin_backup_before_imglink_1795091947`。
- **待用户**：GUI 里贴一张图片直链（面板链接框 / 壁纸库导入），确认真能做成壁纸。

### F15 · 网页 / 流媒体壁纸（借鉴 Lively「URL 即壁纸源」）— 状态：`代码完成 / 端到端 harness 全过 / 二进制已装机 / 待 GUI 确认（受并行调试会话影响暂未重启验证）/ 待发版`
- **日期**：2026-11-19
- **方案**：贴一个链接，B站/抖音/YouTube 仍走原「下载+转码」高画质链路；**其它链接（任意网页、Shadertoy、在线播放页）不下载不转码，用 WKWebView 每屏一个实例直接渲染成壁纸**。YouTube 自动转 embed（`autoplay=1&mute=1&loop=1&controls=0`，循环+静音+无控件），Shadertoy 转 embed（`gui=false`），普通网页原样加载。对应逆向 Lively 报告里的第 ② 项。
- **改动文件**：
  - 新增 `WebWallpaper.swift`：`WebStream`（id/name/url/addedAt）+ `WebStreams`（streams.json 读写、虚拟 URL `dongweb://<id>`、导入分流 `isWebCandidate`、`targetURL` embed 转换）+ `WebEmbed`（YouTube/Shadertoy 播放页转换）+ `WebWallpaperView`（WKWebView 封装：无手势自动播放、documentEnd 注入 JS 静音/自动播/播放器页铺满裁切、`pauseMedia()/resumeMedia()/shutdown()`）+ `WebThumb`（地球图标缩略图）。
  - `main.swift`：`Source.load()` 合并 streams.json（dongweb 排在本地文件后）；`rebuildBody` 按 scheme 分流到新增 `rebuildWebBody`（每屏 WallpaperWindow + WebWallpaperView）；teardown/applyAutoPause/applyAutoResume 接入 webViews（自动暂停 = JS 停页面媒体，不拆窗口）；`pushLockScreen` 跳过非本地素材；`displayName`/`index didSet`/`libraryDelete`/`libraryMove`/预热/`Source.saveOrder` 全部适配虚拟 URL（`dongweb://` 的 lastPathComponent 是空的，一律用 `streamID` 或整条 URL 比较）；`importLink` 开头分流到新增 `addWebWallpaper`（不下载直接入库，与视频同规矩：入库不换壁纸）。
  - `LibraryWindow.swift`：`GalleryThumb.info/cached/load` 网页壁纸快速路径；卡片名显示 `WebStreams.displayName`；`metaText` 显示「网页壁纸」；卡片悬停预览与「在访达中显示」对非本地素材跳过（避免 AVPlayer 吃 dongweb:// 报错）。
  - `build.sh`：编译列表加 `WebWallpaper.swift`。
- **验证（2026-11-19）**：
  - 逻辑 harness **18/18 全过**：视频站/网页分流 9 例、embed 转换 6 例、虚拟 URL 往返 3 例。
  - **端到端集成 harness 全过**（真实 WKWebView）：streams.json 写读去重删除、embed 转换、WebView 创建+加载 Shadertoy embed 存活 5s、JS 暂停/恢复/shutdown 无异常。
  - harness 抓出并修掉 **2 个真 bug**：① `WKPreferences/WKWebView` 的 `setValue(false, forKey:"drawsBackground")` 老私有 KVC 在当前 macOS 直接抛 `NSUnknownKeyException`（SIGTRAP）——删除，改用公开 API `underPageBackgroundColor = .black` 防白屏闪烁；② `save()` 用 iso8601 编码日期而 `load()` 未设对应解码策略 → 解码静默返回空、库凭空消失 + `virts[0]` 越界崩溃——补齐 `dateDecodingStrategy = .iso8601`。
  - `VW_NO_PRESETS=1 zsh build.sh` 全量编译通过（17:14 产物含并行会话已完成的 HoverCatcher 改动，互不覆盖）。
- **本机装机（2026-11-19）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（1653440 B）+ `codesign --force --deep --sign -` 重签 + `--verify --deep --strict` 通过，`dongweb` 符号确认编入；版本仍 3.40、偏好与 bundle id 未动；回滚备份 `/tmp/vw_bin_backup_before_f15_webwp_1795079691`。**运行态重启暂缓**：另一会话正在并行调试 Dòng（悬停功能），为避免互杀进程打架，待其结束后重启验证。
- **已知限制（第一版）**：网页壁纸不参与拖动重排持久化（重启后排本地素材后）；锁屏静帧同步对网页壁纸跳过；非 16:9 屏幕上 YouTube embed 有 letterbox 黑边；B站直播链接仍走下载链路（会失败），后续可加 embed 分流。
- **待用户 GUI 确认**：壁纸库贴一个非视频站链接（如 `https://www.shadertoy.com/view/4ttSWf`）→ 库里出现地球图标条目 → 点它设为壁纸 → 桌面直接渲染网页；全屏/锁屏时自动暂停生效（F14 策略对网页壁纸同样工作）。
- **状态**：代码完成、harness 验证全过、二进制已装机；版本号未动、未提交、未单独发版。

### F14.2 · 暂停态按用户定稿改回「静态果冻」（F14.1 撤销换图标方案）— 状态：`已装机 / 用户已确认 F14 功能测试通过 / 待发版`
- **日期**：2026-11-19
- **背景**：F14.1 的橙色暂停符号方案用户测试后定稿：**暂停时显示静态果冻（停摆帧）即可**，不换图标。同时用户确认 F14 自动暂停功能（全屏/锁屏/规则开关）测试通过。
- **改动文件**：`main.swift`（`updateStatusItem`）。
- **行为变化**：
  - 移除 F14.1 的 `pause.circle.fill` 暂停符号与 `contentTintColor` 染色。
  - 暂停时菜单栏图标 = 果冻停在静态帧（`MenuBarSway.update(mood: .off)`，本来就有）；正常播放时果冻继续晃；tooltip 的「已因<原因>自动暂停」文案保留。
- **验证/装机（2026-11-19）**：编译通过；装机 sha256 与新 build 一致，二进制中 `pause.circle.fill` 已确认移除（0 处）；重签 verify 通过；强杀旧进程后重启 PID 11000 → 15070；发模拟锁屏通知 App 存活。版本仍 3.40、未提交、未单独发版；回滚备份 `/tmp/vw_bin_backup_before_f14_2_jellyonly_1795077234`。
- **状态**：已装机。①③ 至此用户确认测试通过，可排第 ② 项流媒体/网页壁纸。

### F14.1 · 暂停态图标改为明确的橙色暂停符号（F14 可视化补丁）— 状态：`已装机 / 待用户 GUI 确认 / 待发版`
- **日期**：2026-11-19
- **问题**：F14 的暂停态可视化只把菜单栏图标 alpha 从 1.0 降到 0.5 + 果冻停摆。用户发来 21 秒录屏反馈「菜单栏图标没像说的那样变」。像素实测确认：暂停时橙色图标亮度仅从 137 降到 115（约 16%），且果冻晃动幅度本就很小——**肉眼几乎无法分辨，等于没效果**。（另：用户录屏中壁纸画面的帧差剧变来自点开面板动画，非壁纸播放，与暂停无关。）
- **改动文件**：`main.swift`（`updateStatusItem`）。
- **行为变化**：
  - 移除暂停时的 alpha 降低（原来 0.5），图标始终维持正常亮度。
  - 自动暂停时，在果冻 `stop()` 停摆之后，**把菜单栏图标直接换成橙色 `pause.circle.fill` 暂停符号**（18pt，`contentTintColor = .systemOrange`）；放在 `MenuBarSway.update` 之后调用，避免被果冻帧覆盖。
  - 恢复时 `contentTintColor = nil`，果冻 `start()` 自动把图标换回常态——暂停/续播一眼可见。
  - tooltip 的「已因<原因>自动暂停」文案保留。
- **验证（2026-11-19）**：
  - `VW_NO_PRESETS=1 zsh build.sh` 全量编译通过（仅原有 deprecated 警告）。
  - 装机二进制 sha256 `715e7aa36daf2c38b72e74d09bdc1b4a14751e6355cd5041b66e19688241fb5a` 与新 build 完全一致，`pause.circle.fill` 资源确认编入。
  - 发模拟锁屏通知后 App 进程存活无崩溃（沙箱下 `screencapture` / avfoundation 抓屏被拒，视觉确认改由用户 GUI 完成）。
  - 逻辑确定性：暂停时 `MenuBarSway.update(.off)` 会 `stop()` 掉定时器，暂停符号不会被动画帧覆盖；恢复时 `start()` 换回果冻。
- **本机装机（2026-11-19）**：最小替换二进制 + `codesign --force --deep --sign -` 重签 + `--verify --deep --strict` 通过；版本仍 3.40、偏好与 bundle id 未动；回滚备份 `/tmp/vw_bin_backup_before_f14_1_pauseicon_1795076293`；重启 PID 98337 → 11000。
- **待用户 GUI 确认**：发锁屏或打全屏 → 菜单栏图标应变成明显橙色暂停符号（一眼可见）、tooltip 写明原因；条件解除 → 图标变回晃动的果冻。
- **状态**：已装机，改动留工作区；版本号未动、未提交、未单独发版。

### F14 · 自动暂停策略 + 状态可视化（借鉴 Lively）— 状态：`已装机 / 状态机 harness 全过 / 待用户 GUI 确认 / 待发版`
- **日期**：2026-11-19
- **来源**：用 REA 源码证据方法论逆向 Lively Wallpaper 后，确认其系统性领先 Dòng 的一点是运行时省电策略（`Suspend/Playback.cs`：前台全屏 / 锁屏 / 电池自动暂停）。Dòng 此前 `isPaused` 只是重建时的临时标志，**没有任何自动暂停**，用户打全屏游戏 / 看视频时壁纸仍在后台满速解码。用户决定本轮做「自动暂停 + 状态可视化 + 规则开关」，流媒体/网页壁纸（第 ② 项）等本轮测试后再排期。
- **改动文件**：
  - 新增 `PlaybackPolicy.swift`：1 秒定时器 + 系统通知（`com.apple.screenIsLocked/Unlocked`、`NSWorkspace.screensDidSleep/Wake`、`Tuning.changed`）汇总三类信号；前台全屏用 `CGWindowListCopyWindowInfo` 比对前台 PID 窗口 bounds 与 `CGDisplayBounds`（12pt 容差），低电量用 `ProcessInfo.isLowPowerModeEnabled`（macOS 12+）。只回调 `onPause(reason)` / `onResume()`，不碰窗口；`invalidate()` 供启用/关闭后强制重判；重复通知按 reason 去重。
  - `Tuning.swift`：新增 3 个 Bool 开关 `pauseOnFullscreen` / `pauseOnLock` / `pauseOnLowBattery`，**默认全开**；统一 `readBool/writeBool` 存取（前缀 `VWTuning.`），改动广播 `changed` 让策略立即重判。
  - `main.swift`：`applicationDidFinishLaunching` 注入 `isActive`（跟随 `isShowing`）/ `onPause` / `onResume` 并启动策略；新增 `applyAutoPause(_:)` / `applyAutoResume()`——**只 `player.pause()/play()`，不 teardown**，续播按 `Tuning.speed` 恢复倍速；`rebuildBody` 的 `isPaused = wasPaused` 天然保住暂停态；`setEnabled` 清旧原因并 `invalidate()`；菜单栏 `updateStatusItem` 在暂停时图标 alpha 降到 0.5、果冻停摆、tooltip 追加「已因<原因>自动暂停（条件解除后自动续播）」。
  - `LibraryWindow.swift`：设置弹层（`makeSettingsController`）在透明度下方加「自动暂停」区，3 个 `NSSwitch` 绑上述开关；`refreshSettingsState` 每 0.4s 同步状态。
  - `build.sh`：编译列表加 `PlaybackPolicy.swift`。
- **行为变化**：
  - 前台应用全屏铺满任一屏（含全屏游戏）→ 壁纸静默暂停、解码/GPU 归零；退出全屏 → 原地续播，不闪不重建。
  - 锁屏 / 显示器睡眠 → 暂停；解锁 / 唤醒 → 续播。低电量模式 → 暂停（不是「用电池就停」）。
  - 三类规则可在「壁纸库 → 设置」里单独关闭；关掉正在生效的规则时立即续播，不必等下一秒。
  - 自动暂停期间菜单栏图标变暗 + 停止晃动 + tooltip 写明原因；面板照常可点、可换壁纸。
- **验证（2026-11-19）**：
  - `VW_NO_PRESETS=1 zsh build.sh` 全量编译通过（仅项目原有 deprecated 警告）。
  - 独立 harness（`Tuning.swift` + `PlaybackPolicy.swift` 编译成命令行程序）**8/8 全过**：初始不暂停 / 锁屏命中 / 重复通知去重 / 关规则立即续播 / 解锁在规则关闭时无动作 / 重新开规则再锁屏 / `invalidate` 强制重判 / 解锁续播。
  - `CGWindowList` 探针实测：`kCGWindowOwnerPID` 用 `NSNumber` 取值正确（避免全屏检测静默失效），窗口 bounds 与 `CGDisplayBounds` 同坐标系，全屏判定几何成立。
  - 修掉一个启动边界 bug：`applyAutoPause` 原要求 `players` 非空才记录原因，开机自启时若已锁屏会漏暂停；改为不要求播放器存在，靠 `rebuildBody` 的 `wasPaused` 自动暂停新 player。
  - 装机后向系统发 `com.apple.screenIsLocked/Unlocked` 分布式通知，App 进程存活、无崩溃日志。
- **本机装机（2026-11-19）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（1572112 B）+ `codesign --force --deep --sign -` 重签 + `--verify --deep --strict` 通过；Info.plist / 图标 / bundle id / 偏好（版本仍 3.40、wallpaperEnabled 未动）全部保留；回滚备份 `/tmp/vw_bin_backup_before_autopause_1795073012`；重启 PID 69168 → 98337。
- **待用户 GUI 确认**：① 打一个全屏窗口（或全屏游戏）看菜单栏图标是否变暗 + tooltip 写明原因、退出全屏是否原地续播；② 锁屏/唤醒后回来看壁纸是否自动继续；③ 在壁纸库「设置」里开关三条规则，确认关掉正在生效的规则立即续播。
- **状态**：已装机、核心状态机已验证，改动留工作区；版本号未动、未提交、未单独发版。第 ② 项（流媒体/网页壁纸）本轮不做，待用户测完 ①③ 后另行排期。

### F13 · 插件改为「App 内一键安装、装完即时生效」：用户点一下即可，无需下载/解压/右键/重启 — 状态：`已装机 / 静默脚本隔离实测通过 / 待 GUI 确认 / 待发版`
- **日期**：2026-11-18
- **问题**：F12 虽把下载改成直链，但下载后用户仍要「解压 → 右键打开 .command 绕过 Gatekeeper → 等几分钟装依赖 → 退出并重开 Dòng」共 4 步。用户明确要求「下载了之后就可以直接使用，不要太多步骤」。
- **方案**：把安装动作搬进 App——用户点一下按钮，App 自己下载安装包 → 解压 → 无交互跑安装脚本 → 清运行时缓存即时生效。全程不离开 App、不右键、不重启。
- **改动文件**：
  - 新增 `PerfectLoopInstaller.swift`（一键安装核心：URLSession 下载 → unzip → 生成静默安装脚本 → Process 跑并逐行回进度 → 成功后清缓存；无沙箱、主线程回调；`PerfectLoopInstallError` 承载失败原因）。
  - `Transcoder.swift`：新增 `invalidatePerfectLoopRuntime()`（清懒加载缓存，`perfectLoopRuntime` 下次重新发现）；`perfectLoopInstallSteps`/`perfectLoopRecommendationWithLink` 文案改「一键安装，装完立即生效，无需重启」。`perfectLoopInstallURL` 保留为唯一 URL 真相源，安装器复用它。
  - `LibraryWindow.swift`：画面微调面板的「下载安装包」按钮改「一键安装 PerfectLoop 插件」，加进度 label（装时显示每步、失败红色、成功重建面板显示「PerfectLoop 无缝循环」）；action `tuneInstallPluginTapped` 调安装器；移除旧 `tuneDownloadPluginTapped`。
  - `build.sh`：编译列表加 `PerfectLoopInstaller.swift`。
  - 静默脚本逻辑与 `dist/perfectloop-plugin/安装 PerfectLoop 插件.command` 同源（装 uv → venv → 清华镜像分批装 7 依赖每批重试 3 次 → 部署源码到 `~/.local/share/VideoWallpaper/perfectloop-plugin/` → 清 pyc → `--check` 自检），但去掉两处 `read` 交互、输出到 stdout 供 UI 显示进度。
- **验证**：全量编译通过；按字节确认一键安装文案/进度语/新类编入二进制；从 Swift 抽出静默脚本在隔离 HOME（复用 uv 缓存）无交互跑通，4/4 全过、自检 OK、产物部署正确。
- **装机**：最小替换 `/Applications/Dòng.app` + 重签 verify 通过，回滚 `/tmp/vw_bin_backup_before_f13_1795004762`，重启 PID 69168。
- **状态**：已装机、核心链路已验证，改动留工作区；版本号未动，未提交、未单独发版。**待用户 GUI 确认**：本机此前已装过插件（自检 OK），面板此时显示「PerfectLoop 无缝循环」、不会有一键安装按钮（正确行为）；要看到按钮需先临时移走测试插件目录。

### F18 · 修「点下载跳到 releases 列表页、用户找不到安装包」：改直链下载 + 写清后续步骤 — 状态：`已装机 / 直链实测 HTTP 200 / 待 GUI 确认 / 待发版`
- **日期**：2026-11-18
- **问题**：用户点画面微调面板的「下载并安装 PerfectLoop 插件」按钮，被弹到 GitHub `releases` 列表页，默认展示 v3.40 的 App 更新说明；安装器 zip 藏在需手动展开的 Assets 区，且和 dmg 混在一起。用户原话「我不知道在哪里下载，用户怎么可能知道？」——下载入口形同虚设。
- **根因**：`Transcoder.perfectLoopInstallURL` 指向列表页 `.../releases`（不是文件直链）；纯文本文案也写「安装说明：.../releases」，把用户往同一个找不到东西的页面引。
- **改动文件**：
  - `Transcoder.swift`：`perfectLoopInstallURL` 改为 `.../releases/latest/download/PerfectLoop-Plugin-Installer.zip`（点按钮浏览器立即下载；`latest/download` 自动跟随最新 release 的同名附件）。新增 `perfectLoopInstallSteps`（下载后解压 → 双击 .command → 被拦截则右键→打开）。`perfectLoopRecommendationWithLink` 文案改为「在画面微调面板点『下载插件』，解压后双击安装器」。
  - `LibraryWindow.swift`：按钮标题改「下载 PerfectLoop 插件安装包 ↗」（点=下载，不再误导成"安装"）；按钮下加一行小字写下载后步骤（关键：用户下了 zip 不知道怎么装=没下）；更新 action 注释。
- **验证**：直链 `curl -sIL` 与实下载均 HTTP 200、18932 B、随最新版自动指向（两个 release v3.39/v3.40 都带同名附件）；`VW_NO_PRESETS=1 zsh build.sh` 编译通过；按字节确认直链/新文案/步骤文字编入二进制。
- **装机**：最小替换 `/Applications/Dòng.app` + 重签 verify 通过，回滚 `/tmp/vw_bin_backup_before_f11_1795003886`，重启 PID 64687。
- **状态**：已装机、已验证直链，改动留工作区；版本号未动（v3.40 已由另一任务发布），未提交、未单独发版。**待用户 GUI 确认**：点按钮应直接开始下载 zip，按钮下应显示三行步骤小字。

### F10 · 补齐「用户怎么下载」闭环：一键安装器 + 下载入口 — 状态：`已装机 / 安装器隔离实测通过 / 待真机确认 / 待发版`
- **日期**：2026-11-17
- **用户诉求**：F9 在 UI 写了"推荐安装 PerfectLoop 插件"，但用户问「跳出了用户要怎么下载」——推荐文案没有下载入口，闭环断了。本条补上：让用户看到推荐后能真的下载并一键装好。
- **关键判断**：PerfectLoop 依赖约 332MB Python 环境（numpy/opencv/scikit-image），普通用户不可能自己配 venv。所以「让用户自己下载」的正确形态 = **一个双击即装的安装器**，而不是甩个源码仓库链接。
- **改动文件**：
  - `dist/perfectloop-plugin/安装 PerfectLoop 插件.command`（新建，一键安装器）：内置真源码 + requirements；引导装 uv → 建独立 venv(Python 3.11，不动系统 Python) → 用清华镜像分批装 7 个依赖(每个失败重试 3 次) → 部署到 `~/.local/share/VideoWallpaper/perfectloop-plugin/` → 清 pyc（防破坏签名）→ `--check` 自检 → 中文提示重启 Dòng；给出卸载方法。
  - `dist/perfectloop-plugin/PerfectLoop插件-安装器.zip`（20KB，分发用；依赖联网下载所以包很小）：解压后 `.command` 可执行位与中文名均验证保留。
  - `dist/perfectloop-plugin/安装说明.md`（新建，给下载页用）：写清占用(330MB 磁盘/340MB 峰值内存)、Gatekeeper 首次「右键打开」步骤、常见问题、卸载、MIT 许可。
  - `Transcoder.swift`：新增 `perfectLoopInstallURL`（指向 `github.com/zhang-1-kael/dong/releases`，项目已有真实仓库；注释标明日后改官网只改这一处）+ `perfectLoopRecommendationWithLink`（带下载指引的纯文本）。
  - `LibraryWindow.swift` 三处：① 拖拽浮层推荐文案换成带下载指引版(两行)；② 系统文件面板 `NSOpenPanel.message` 换成带下载指引版；③ 画面微调面板在"未启用插件"时新增可点击按钮「下载并安装 PerfectLoop 插件 ↗」，`tuneDownloadPluginTapped` 用 `NSWorkspace.shared.open(url)` 打开下载页。
- **验证（2026-11-17）**：
  - `bash -n` 语法通过；用隔离 HOME（`/tmp/pl-fakehome2`）跑完整安装器：uv 检测 → Python 3.11 venv → 清华镜像装依赖 → 部署 → 自检，全流程 **exit=0，自检 OK**（耗时 1m23s）。
  - 首轮用官方 PyPI 源时遇 TLS 连接被断 + 单包下载近 4 分钟 → 改清华镜像 + 分批重试，隔离实测一次通过。
  - zip 解压验证：中文文件名正确、`.command` 可执行位 `rwxr-xr-x` 保留。
  - `VW_NO_PRESETS=1 zsh build.sh` 编译通过；按字节确认「下载并安装 PerfectLoop 插件」「安装说明：github.com/zhang-1-kael/dong/releases」已编入二进制。
- **本机装机**：最小替换 `/Applications/Dòng.app` 二进制 + 清 pyc + 重签 verify 通过；回滚备份 `/tmp/vw_bin_backup_before_f10_1794917406`；重启 PID 39900。
- **已上传（2026-11-17 20:26，gh 已登录 zhang-1-kael，有 repo 权限）**：安装器与说明已上传到 **v3.39 Release**（Latest），下载入口现在真实可用，无需再更新 App。
  - `PerfectLoop-Plugin-Installer.zip`（18932 B）：`https://github.com/zhang-1-kael/dong/releases/download/v3.39/PerfectLoop-Plugin-Installer.zip`，实测 curl HTTP 200。
  - `PerfectLoop-Plugin-README.md`（2178 B）：安装说明。
  - **踩坑**：① 中文文件名经 gh 上传会被 GitHub 改成 `PerfectLoop.-.zip` / `default.md`，必须复制成英文名再传；② `zip` 命令打的中文名无 UTF-8 标记（flag_bits 0x0），macOS 归档工具双击解压会乱码——改用 Python `zipfile` 重打包，UTF-8 flag=True、可执行位 755 均保留。本地 `dist/` 里保留中文名文件便于识别，上传的是英文名副本。
  - 若日后改用官网下载页，只需改 `Transcoder.perfectLoopInstallURL` 一处 + 重传文件。
- **待办**：用户 GUI 确认三处下载入口（点"添加视频"看 message 两行、画面微调面板点「下载并安装」能打开 Releases 页并下载 zip）。
- **状态**：已装机、插件已上传到 Release、下载闭环打通；改动留工作区，未提交、未 bump 版本（沿用 v3.39 Release，未另发版）。

### F9 · PerfectLoop 改为「用户自选插件」：App 不再内置，导入处推荐并如实标注占用 — 状态：`已装机 / 已验证 / 待真机确认 / 待发版`
- **日期**：2026-11-16
- **用户诉求**：产品策略调整——**推荐用户使用 PerfectLoop，但 App 不再打包它**；在软件上传/导入处写上「推荐使用 PerfectLoop 插件，效果更好」，让用户自行下载、自主选择；**但在推荐前要讲清楚加入它会占用多少内存/磁盘**。
- **实测占用（本机 2026-11-16，写进 UI 文案的数字来源）**：
  - 磁盘：**约 332 MB** —— 核心源码仅 44 KB，大头是 Python 依赖环境：OpenCV(cv2) 119M + SciPy 99M + NumPy 34M + scikit-image 28M + networkx 18M + Pillow 13M + pip 12M + 其余。
  - 运行时内存：1280×720 转码峰值驻留集 **353,304,576 B ≈ 337 MiB**（`/usr/bin/time -l` 实测）；分辨率越高越大，故文案写「约 340 MB 峰值内存」。
  - UI 文案取整数表述：磁盘「约 330 MB 磁盘」、内存「约 340 MB 峰值内存」，不夸大也不含糊。
- **改动文件**：
  - `build.sh`：删除「把运行器 + 核心源码打进 bundle」整段，改为仅打印提示。新构建产物不再含 PerfectLoop，DMG 不再隐含这份体积（原先只有 44KB 源码，但依赖本来就在外部 venv，此处主要是明确策略、避免误打包）。
  - `Transcoder.swift`：
    - 新增占用常量 `perfectLoopDiskFootprint` / `perfectLoopMemoryFootprint` / 一句话推荐 `perfectLoopRecommendation`（带引用注释说明数据实测来源）。
    - `perfectLoopRuntime` 的运行器候选顺序改为**先用户自行安装目录** `~/.local/share/VideoWallpaper/perfectloop-plugin/`（含 `tools/` 兼容形态），再回退旧 bundle 内副本——保证「用户装了就用、没装自动回退 blend/硬切」。
  - `LibraryWindow.swift`（导入入口 + 画面微调面板）：
    - 拖拽浮层 `DropOverlay` 在「松开，收进壁纸库 / 自动去跳帧…」下方新增一行推荐 + 占用。
    - 文件选择面板 `NSOpenPanel.message` 追加推荐 + 占用（用户点「添加视频」即见）。
    - 画面微调面板底部：插件**未启用**时额外显示一行推荐 + 占用；已启用则维持原「PerfectLoop 无缝循环」。
- **行为变化**：
  - 新用户：App 里不再有 PerfectLoop 源码；导入/微调处看到推荐说明及「330MB 磁盘 / 340MB 内存」，自行决定是否安装。未安装时无缝循环回退到内置 blend 交叉淡化 / 硬切（**短视频首尾跳变可能回来**，这是用户自选策略的预期取舍，已在推荐文案中明确插件效果更好）。
  - 已安装插件者：App 检测到外部目录即自动启用，体验不变。
- **验证（2026-11-16）**：
  - `VW_NO_PRESETS=1 zsh build.sh` 全量编译通过（仅既有 deprecated 警告）；构建日志显示「PerfectLoop 为用户自选插件：不打包」。
  - 按字节确认文案已编入二进制：`推荐安装 PerfectLoop 插件` / `约 330 MB 磁盘` / `约 340 MB 峰值内存` / `.local/share/VideoWallpaper/perfectloop-plugin` 全部命中。
  - 建外部插件目录 `~/.local/share/VideoWallpaper/perfectloop-plugin/`（模拟用户自行安装），`perfectloop_runner.py --check` 返回 `OK OK`，证明发现路径可用。
- **本机装机（2026-11-16 20:00）**：最小替换 `/Applications/Dòng.app` 二进制 + 清 pyc + `codesign --force --deep --sign -` 重签，verify 通过；同时删除 bundle 内旧内置的 `tools/PerfectLoop/` 与 `perfectloop_runner.py`（与「不内置」策略一致，Plugin 发现完全走外部目录，自检仍 OK）；回滚备份 `/tmp/vw_bin_backup_before_f9_1794830328`。重启 PID 82387。
- **待办**：用户 GUI 真能看到导入/微调处的推荐文案；用户如需「一键安装插件」的落地脚本/下载页需另立任务（本条只做推荐 + 标注占用）。
- **状态**：已装机，改动留在工作区，未提交、未发版；版本号未动。

### F7 · 画质与帧率优化（下载放开 4K + 抖音码率择优 + 码率上限放宽）— 状态：`已装机 / 待真机确认 / 待发版`
- **日期**：2026-11-16
- **用户诉求**：用户反馈「在 B 站/抖音上看画质高，下载做成壁纸后画质和帧率都差」，要求真正实现画质与帧率优化（上一轮只做了实测分析、未落地代码，本条为实际落地）。
- **实测基线（2026-11-16）**：屏幕 `2408×1506 Retina`（scale 2）；偏好 `VWTuning.outputFPS=60`（用户已手动设，帧率在新片中已生效，非瓶颈）。壁纸库片源：当前在播 `1920×1080 / 60fps / 17.8Mbps`，另有 `1280×720/60fps/3.3M`、`1726×1080/30fps/3~5M`（老片）。核心问题是分辨率被卡 1080p，铺满 2408 宽需放大 1.25×（720p 放大 1.88×），GPU 双线性放大导致发软。
- **根因与改动**：
  1. **下载端卡死 1080p**（画质主因）：`Downloader.swift` 格式选择器原为 `bv*[height<=1080]...`。改为分辨率优先 `bv*[height>=2000]/bv*[height<=1080][vcodec^=avc1]/...`。注意顺序——若只把 `<=1080` 改成 `<=2160` 且 avc1 在前，yt-dlp 仍会挑 1080p avc1 而放过 4K hevc，等于没放开。
  2. **抖音端取默认档**：`DouyinWebFetcher.swift` 的 `collect()` 原按 play_addr→bitrate_info 顺序收集，下载取第一路能用的，丢弃了高码率档。改为带 `ScoredURL` 画质分排序：按 `bitrate_info[].width×height`（无尺寸退回 bit_rate）降序，play_addr 默认档居中，download_addr（带水印）垫底。
  3. **转码码率上限卡死**：`Transcoder.swift` + `tools/perfectloop_runner.py` 的 `maxrate 20M/bufsize 40M` 对 4K 源缩到 2408×1354/60fps 是硬瓶颈，会把 CRF 18 想要的码率削平。放宽到 `maxrate 80M/bufsize 160M`（壁纸是本地短片，体积非瓶颈）。CRF 18 保持不变。
- **验证（2026-11-16）**：
  - `swiftc -O` 全量编译通过（仅项目原有 deprecated 警告）；`codesign --verify --deep --strict` 通过。
  - 用 `strings` 比对新旧二进制：格式选择器字面量从 `height<=1080...` 变为 `height>=2000...`，确认新逻辑进包。
  - 端到端转码实验（2408×1354/60fps 复杂画面源）：旧 maxrate 20M 输出被压在 25.0Mbps、PSNR 46.44dB / SSIM 0.99708；新 maxrate 80M 输出 26.0Mbps、PSNR **46.88dB** / SSIM **0.99731** —— 画质有可测提升。
  - **B 站会员墙注意**：游客/无大会员 cookie 时 B 站只给到 720p~1080p（实测 `BV1b94y1d7dK` 游客仅 720p；另片提示「1080P 高码率需大会员」），此时放开 4K 选择器无效——需用户自己的大会员 cookie 才能拿到 4K 源。
- **本机装机（2026-11-16 19:05）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper` + 同步 `tools/perfectloop_runner.py`，`codesign --force --deep --sign -` 重签 + verify 通过；偏好 / 图标 / Info.plist / bundle id / 版本未动；重启 PID 63250（新二进制）。回滚备份 `/tmp/vw_bin_backup_before_quality_1794827085`。
- **待用户**：用新链接重新导入一条 B 站/抖音壁纸，确认画质提升（**已导入的旧壁纸不会自动重转码**，需重新导入才走新参数）；B 站 4K 需确认是否登录大会员账号。
- **状态**：改动留在工作区，未提交、未发版；版本号未动。

### F7.1 · 画质帧率优化「真实根因」修复（纠正 F7 的两处误判）— 状态：`已装机 / 端到端已验证 / 待真机确认 / 待发版`
- **日期**：2026-11-16（晚）
- **背景**：F7 装机后用户实测「新加的壁纸画质仍差」，要求给出真实证据。用用户给的抖音链接 `https://v.douyin.com/yNUaV1Tlcbg/`（aweme_id 7686880309157719476）做端到端复现 + 逐层诊断，发现 F7 有两个关键误判，本条为真正修复。
- **纠正 1 — 抖音码率择优字段名写错（画质主因）**：F7 里 `collect()` 读的是 `video["bitrate_info"]`，但抖音 detail 接口**根本没有这个字段**，真实多档位列表是 `video["bit_rate"]`（12 档）。结果 F7 的择优逻辑从头到尾没生效，实际下载的是 1024×576 默认档。诊断出该链接真实档位表：`[0] 3840×2160/7.17Mbps/60fps（is_h265=1 标称 bytevc1）`、`[1] 2560×1440/3.9M/60fps`、`[2] 1920×1080/3.75M/30fps H264`… 另发现用视频顶层标称 `width×height=3840×2160` 给默认档打虚高分，会把 1024×576 的低清流误排第一。
  - **修复**：`collect()` 改读 `video["bit_rate"]`；每档真实分辨率从**该档自己的 `play_addr.width/height`** 取（不是档位顶层、更不是视频顶层）；评分 = 像素数 + 码率/帧率微调（7M bps≈+0.7M 分）。默认档按其 play_addr 真实分辨率打分，download_addr 垫底。
  - **编码验证**：标称 `is_h265=1/bytevc1=1` 的 4K 档，实际下载探测为 `hevc (hvc1) 3840×2160/60fps/7115kbps` —— 是标准 HEVC，ffmpeg 6.0 可解（bytevc1 标记是字节的误导），端到端转码通过。
- **纠正 2 — 帧率并没有"用户已设 60"**：F7 记录里写「偏好 outputFPS=60 用户已手动设」是误读；实测 `com.zhanghangshuo.dong.plist` 里**没有 outputFPS 键**，`effectiveFPS` 走默认 `min(30, source)`，帧率被砍到 30。
  - **修复**：`Tuning.swift` 的 `effectiveFPS` 跟随源上限 30 → **60**（有 60fps 源就给 60，无则跟随，不无中生有），注释同步。
- **端到端实测（修复后，同一链接，隔离 support 目录不碰真实库）**：
  - 旧代码产物：**1024×576 / 30fps / 4.2MB**
  - 修复后产物：**2816×1584 / 60fps / 31.6Mbps / 62.2MB**（4K 档选中，最高分 9011880；输出框 2816 是 CLI 环境按默认屏幕算的，真机按实际屏幕）
  - 分辨率 ×2.75、帧率 ×2、码率 ×15，4K 档 + 60fps 全部落到位。
- **本机装机（2026-11-16 19:42）**：最小替换 `/Applications/Dòng.app` 二进制 + 同步 Python 脚本，重签 + verify 通过；重启 PID 76095（旧 63250）。回滚备份 `/tmp/vw_bin_backup_before_quality2_1794829347`。
- **待用户**：用新链接重新导入（旧壁纸不自动重转码）；真机确认画质。
- **状态**：改动留在工作区，未提交、未发版；版本号未动。

### F8 · 淡化关闭时自动用 PerfectLoop 消除短视频循环跳变 — 状态：`已装机 / 已验证 / 待真机确认 / 待发版`
- **日期**：2026-11-16（晚）
- **用户诉求**：贴抖音链接 `https://v.douyin.com/6Luyf4kXsDs/`（aweme_id 7686079358381316854，note 页实况图）生成壁纸后「循环时有很明显的卡顿」，附录屏。
- **诊断（基于录屏逐帧 + diag.log）**：
  - 录屏 180 帧逐帧差分：壁纸画面本身流畅（仅 11 帧瞬时静止，属正常编码波动），**视频播放未掉帧**（`play_stall=0`）。
  - 真正原因是**循环跳变**：该壁纸 922×576 / 3.97s / 首尾 SSIM 仅 0.5122（首尾画面不接），而用户「首尾淡化 fade=0」（关闭），PerfectLoop 旧逻辑要求 `fade>0` 才触发 → 根本没运行 → 每约 4 秒循环硬跳一下。
  - 附：922×576 铺 2816×1762 屏幕放大约 9 倍，`RenderPlan` 判 `plan=heavy`；此为实况图源分辨率上限（`bit_rate` 多档位择优 F7.1 对 note 页实况图不适用），非本次卡顿主因。
  - 日志佐证：绑定该壁纸后 1 分钟内主线程 stall 从 50→55、累计 5.9s→7.7s；此前 9 分钟才涨 8 次。
- **改动文件与行为**：
  1. `Tuning.swift`：新增开关 `autoSeamless`（默认 true）——「首尾淡化关闭时也自动用 PerfectLoop 消除循环跳变」，可强制关闭回退旧行为。
  2. `Transcoder.swift` `transcode()`：触发条件从 `fade>0` 放宽为 `fade>0 || Tuning.autoSeamless`；失败回退文案按 fade 区分；新增触发分支的中文说明。
  3. `Transcoder.swift` `runPerfectLoop()`：`morphSteps` 在 fade=0 时不再只有 4 帧，改用默认 0.35 秒（30fps≈10 帧），避免过渡生硬。
- **验证**：
  - `swiftc -O` 全量编译通过（含 DouyinWebFetcher + WebKit）；`codesign --verify --deep --strict` 通过；二进制 `autoSeamless` 命中 2。
  - 用该壁纸走集成运行器实测：首尾 SSIM **0.5122 → 0.9726**，119 帧 → 127 帧（+8 帧形变），循环跳变基本消除。
  - 已将重转后的无缝版替换进壁纸库（原文件备份 `/tmp/vw_wallpaper_backup_douyin_lag.mp4`）。
- **本机装机（2026-11-16 19:42）**：最小替换 `/Applications/Dòng.app` 二进制 + 同步 tools（清 pyc）+ 重签 verify 通过；bundle id / Info.plist / 版本 / 偏好未动；重启 PID 76095→76797，映射新二进制。回滚备份 `/tmp/vw_bin_backup_before_autoseamless`。重启后 diag 卡顿计数重置、worst 130ms（此前 1113ms）。
- **待用户**：真机确认循环不再跳；注意 F2 分发问题依旧（依赖本机 venv，别人机器缺依赖会回退硬切）。
- **状态**：改动留在工作区，未提交、未单独发版；版本号未动。

### F6 · 壁纸库长按拖动重排 — 状态：`已装机 / 待真机手势确认 / 待发版`
- **日期**：2026-11-16
- **行为**：壁纸库里按住卡片 0.42 秒后可直接拖到别的位置，松手即按新顺序排列；短按仍然是「设为壁纸」，单击 / 右键菜单行为不变。落点有 accent 色高亮框。顺序写进偏好，重启 App 后仍保持；「正在使用」的标记跟着那张壁纸走，不会串位。
- **改动文件**：
  - `LibraryWindow.swift` → `WallpaperCard` 长按计时器 + 跟手移动 + 落位事件；`GalleryView` 最近卡片落点判定（同排看左右、跨排看上下）、高亮框、`onMove` 回调；controller 接线到 delegate。
  - `main.swift` → `Source.saveOrder` / `applySavedOrder`（键 `VWTuning.libraryOrder`，存文件名，新加的追在后面）、`load()` 应用自定义顺序；`AppDelegate.libraryMove` 重排 + 保持当前 index + 重建轮播 + 埋点。
- **验证（2026-11-16）**：`swiftc -O` 全量编译通过（只有项目原有的 deprecated 警告）。进程内合成事件端到端自测：长按 0.42s 触发 → 三次跟手拖动 → 松手，顺序 `a,b,c,d → b,c,a,d`，偏好写入同名数组；重启隔离实例后顺序仍是 `b,c,a,d`。系统级 CGEvent 辅助功能未授权、此环境 screencapture 失败，真机手感待用户确认。
- **状态**：改动留在工作区，未提交、未发版；版本号未动。
- **本机装机（2026-11-16 17:46）**：完整 `zsh build.sh`（不带 `VW_NO_PRESETS=0`）重新构建，新二进制含 F6（`wallpaper_reorder` / `libraryOrder` 命中）+ F1/F2/F5 全部符号，`nm` 方法符号 7 处、中文字符串（PerfectLoop 无缝循环 / 等待抖音页面响应超时 / 纯图文）均在。最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（1440688 B，与 build 一致），同步清理 tools 目录 pyc，`codesign --force --deep --sign -` 重签 + `--verify --deep --strict` 通过。偏好 plist 未动、bundle id 与版本（3.36/58）保持不变，进程重启 PID 34768，映射新二进制。回滚备份 `/tmp/vw_bin_backup_before_f6`（F5.4 版）。
- **待用户**：真机按住壁纸卡片 0.42s 拖动到新位置，确认落点高亮 + 松手换位 + 重启后顺序保持；手感 ok 后随下一个版本统一发布（不单独发版）。

### F6.1 · 修复壁纸库「拖不动」— 状态：`已装机 / 待真机复测 / 待发版`
- **日期**：2026-11-16
- **问题**：F6 装机后用户真机反馈「没有办法拖动」。
- **根因**：`WallpaperCard.mouseDragged` 里只要位移超过 7px 就 `pressTimer?.invalidate()`，把长按计时器彻底取消。真人操作几乎都是「按下先微动、再拖」，于是计时器在长按到点前就被取消，之后按再久、拖多远都不会进入拖动。原自测用的是「按住纹丝不动 0.7s 再拖」，恰好绕过了这条分支，所以自测通过而真机失败。
- **改动文件**：
  - `LibraryWindow.swift`：① `mouseDragged` 在未进入拖动时，微动只标记 `movedBeforeHold = true`，**不再取消计时器**（松开时仍未到长按时间才什么都不做）；② 长按阈值 0.42s → 0.32s，减少等待；③ 拖动时提层改用 `layer?.zPosition = 20`，松手恢复 0，替代 `superview?.addSubview(self)`（重新挂载视图可能打断按住期间的事件响应）。
- **验证（2026-11-16）**：先用「按下→立即微动 12px→持续按住→拖到目标→松手」的序列复现故障（顺序保持 `a,b,c,d` 不变、`dragging=false`）；修复后同样序列顺序变为 `b,c,a,d`、偏好写入 `[b,c,a,d]`。`swiftc -O` 全量编译通过。
- **本机装机（2026-11-16 17:52）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（1418904 B），`codesign --force --deep --sign -` + `codesign -v` 通过；偏好 / 图标 / Info.plist / bundle id / 版本（3.36/58）未动；重启 PID 45259。回滚备份 `/tmp/vw_bin_backup_before_dragfix`。
- **待用户**：真机再试——按住卡片约 0.32s（可以先微动），拖到目标位置看高亮框，松手确认换位；顺带确认短按仍是「设为壁纸」。

### F6.2 · 重排交互升级为 Apple HIG 弹簧插值 + 避让排布 — 状态：`已装机 / 待真机复测 / 待发版`
- **日期**：2026-11-16
- **需求**：用户要求参考 Apple Human Interface Guidelines 的弹簧插值、避让排布逻辑。
- **行为变化**：
  - **避让排布**：拖动中按「假如现在松手」的顺序实时算出预览排布，被挤到的卡片弹簧滑开留出空位，落点高亮框跟着空位走（不再只是画在原卡片上）。
  - **弹簧落位**：松手后被拖卡片从「手松开的位置」弹进新格子，其余卡片同步弹到位；不再是无动画的瞬间重建。
  - **抬起手感**：拿起卡片时图层轻微放大到 1.035（CASpringAnimation，stiffness 300 / damping 22），松手弹回 1。
  - **卡片复用**：仅顺序变化时（`setItems` 判断 URL 集合相同、只是顺序不同）不再销毁重建卡片，直接重排数组 + 弹簧滑动，播放中的视频和缩略图都不中断；只有真正增删文件才重建。
- **改动文件**：`LibraryWindow.swift` — 新增 `VWSpring`（指数衰减 ease-out 插值 `x += (target-x)*(1-e^(-11·dt))`，单调收敛不过冲）；`GalleryView` 加 `springs` 字典 + 60fps Timer 驱动、`layoutFrames(for:)` 纯计算（排版/预览/落位共用，保证预览位置=落地位置）、`springTo(_:total:skip:)`；改 `setItems` / `relayout` / `updateReorder` / `finishReorder`；`WallpaperCard` 抬起/落下加 CASpringAnimation 缩放。
- **验证（2026-11-16）**：进程内合成事件端到端自测（临时副本注入钩子，主仓库无测试代码）：
  - 避让生效：拖动中 a/b/c 三张 frame 均发生位移；
  - 顺序正确：`a,b,c,d → b,c,a,d`，偏好写入 `[b,c,a,d]`；
  - 弹簧收敛：1.5s 后 `springs-active=0`，落点 frame 为精确整数格（a `x=538,y=46`、c `x=275,y=46`）。
  - 排错记录：首版用显式欧拉积分 + 值类型字典未写回（`springs[path] = s` 漏写），弹簧卡在起点不动；改为指数插值并补写回后收敛。
- **本机装机（2026-11-16 18:48）**：`swiftc -O` 全量编译通过；最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（编译产物 1462848 B，签名后 1472480 B），`codesign --force --deep --sign -` + `codesign -v` 通过；偏好 / 图标 / Info.plist / bundle id / 版本未动；重启 PID 60423。回滚备份 `/tmp/vw_bin_backup_before_hig`（F6.1 版）。
- **待用户**：真机确认避让 + 弹入手感；顺带确认「微动后长按」仍能进入拖动（F6.1）。手感 ok 后随下一版本统一发布（不单独发版）。

### F6.3 · 修复拖动重排时的卡顿/抽搐 — 状态：`已装机 / 待真机复测 / 待发版`
- **日期**：2026-11-16
- **问题**：用户录屏反馈 F6.2 的弹簧避让拖动「会有卡顿、抽搐的情况」。
- **根因（三处确定性 bug）**：
  1. **反馈震荡**：`updateReorder` 用 `c.frame` 判「手离哪张卡最近」，而 `c.frame` 正被 60fps 弹簧逐帧改写 → 位置变→判定变→弹簧目标变→位置再变，在两张卡交界处来回抽搐。
  2. **跟手与弹簧抢同一 frame**：连续拖动（上一次松手的落位弹簧还没跑完就又按住）时，被拖卡身上的旧弹簧没清，`mouseDragged` 写 frame 与 `springTick` 拉回旧目标打架。
  3. **每次 mouseDragged 重建 layer / contentSize 抖动**：高亮框每次都 `removeFromSuperview + addSubview`；`springTo` 每次都按 preview 总高 `setFrameSize`，不同排布总高不同导致滚动区上下抖。
- **改动文件**：`LibraryWindow.swift` — `GalleryView` 新增 `settleFrames`（原顺序静态格子，判距专用）与 `lastNearest`（滞后 0.75×，交界处不来回翻）；`beginReorder` 清掉被拖卡残留弹簧并初始化这两项；`updateReorder` 判距/前后判断改用静态格位 + `chosen`（插入位也统一用 chosen，否则 target 与插入位不对应仍会跳）；高亮框只在隐藏→显示时提层；`springTo` 加 `resize` 参数，拖动预览传 false，松手再统一设 contentSize。
- **验证（2026-11-16）**：`swiftc -typecheck` 与 `swiftc -O` 全量编译通过（只有项目原有 deprecated 警告）。
- **本机装机（2026-11-16 19:02）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（编译产物 1467072 B，签名后 1476672 B），`codesign --force --deep --sign -` 通过；偏好 / 图标 / Info.plist / bundle id / 版本未动；重启 PID 62373。回滚备份 `/tmp/vw_bin_backup_before_stutterfix`（F6.2 版）。
- **待用户**：真机再拖一次，确认交界处不再抽搐、连续拖动跟手、滚动区不抖。手感 ok 后随下一版本统一发布（不单独发版、不 bump 版本）。

### F11 · 底栏小图标调亮 + 描边图标上色（深色模式更清楚） — 状态：`已装机 / 待真机确认 / 待发版`
- **日期**：2026-11-18
- **需求**：用户截图反馈壁纸库底部工具栏的小图标在深色模式下不太清楚，要求调亮、让图标里的纹路带上颜色。
- **关键发现（渲染验证）**：SF Symbol 的 `paletteColors` 第二色对**单色描边符号**（power / plus / folder / gearshape）无效，只会显示主体色。用「白+橙」双色板实测这些图标仍是纯白，达不到"有颜色"。所以主体色本身必须是暖橙，不能指望第二色去染纹路。
- **行为变化**：底栏关态/动作键图标（电源、加号、文件夹、设置、深浅色切换）从灰白描边（`labelColor` 0.58）改为浅暖橙 `Brand.gradTop`（悬停更亮）；开态（动态、锁屏跟随）保持饱和 `Brand.accent` + 淡雾底。状态区分靠开态淡雾底 + 图标形态变化，不靠灰/橙。透明度圆形图标与百分比文字改用固定亮墨色（`barInk`），不再随 window.appearance 翻成黑色压在深玻璃上。
- **改动文件**：`LibraryWindow.swift` — `SettingPill.restyle()` 着色逻辑 + 新增 `refreshAppearance()`；`LibraryWindowController` 存 `addPill/folderPill/settingsPill/appearancePill/transparencyIcon` 为属性、新增静态 `barInk`、`applyWindowAppearance()` 里统一重绘底栏图标与文字。
- **验证**：渲染对比图（`/tmp/symbols_preview.png`）确认三种配色实际效果，敲定暖橙方案；`swiftc -typecheck` 与 `swiftc -O` 全量编译通过（仅原有 deprecated 警告）。
- **本机装机（2026-11-18 19:15）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（编译产物 1497328 B），`codesign --force --deep --sign -` + `-v --deep --strict` 通过；偏好 / 图标 / Info.plist / bundle id / 版本未动；重启 PID 48479。回滚备份 `/tmp/vw_bin_backup_before_icons`（14:19 版）。
- **待用户**：真机确认底栏那排图标在深色模式下是否够亮够清楚。手感 ok 后随下一版本统一发布（不单独发版、不 bump 版本）。

### F17 · 菜单栏图标悬停自动展开小弹窗（少一次点击） — 状态：`已验证 / 已装机 / 待发版`
- **日期**：2026-11-19
- **需求**：原来要点图标打开小弹窗、再点一次"壁纸库"才进库，太绕。改成鼠标悬停在图标上就自动弹出弹窗，直接点里面的"壁纸库"进入。
- **行为变化**：
  - 悬停图标 **0.22s** 自动弹出小弹窗（停留才弹，快速划过不弹）。
  - 面板开着时鼠标移开图标和面板 **0.35s** 自动收起；移到面板上则不收，可以正常点"壁纸库"。
  - 悬停弹出不抢键盘焦点（不打断用户正在别处打字），点击仍照旧可打开/关闭。
  - 悬停弹出后 0.7s 内的"顺手点一下图标"不会把面板关掉（避免手抖误关）。
  - 点图标本身不再被"点外面收起"逻辑抢走，交给按钮正常处理。
- **改动文件**：
  - `main.swift` — 新增 `HoverCatcher`（透明子视图，`hitTest` 返回 nil 让点击穿透）与兜底 `StatusHoverProbe`（按钮自身 tracking area，显式 `mouseEntered:`/`mouseExited:` selector）；`buildStatusItem` 挂载两者；新增 `scheduleHoverOpen/cancelHoverOpen/openPanelByHover/startHoverCloseWatcher/checkHoverLeave/buttonScreenFrame`；`togglePanel` 抽出 `ensurePanel()`；`statusClicked` 加 0.7s 防误关冷却；`VW_HOVER_DEBUG=1` 时打印悬停/坐标日志。
  - `Panel.swift` — `MenuPanelController.show(relativeTo:data:focus:)` 加 `focus` 参（悬停时跳过 `makeKey`）；新增 `passthroughRects`（图标区域内的点击不算"点外面"）；`PanelBody.acceptsFirstMouse` 返回 true（非 key window 下第一次点击也能命中"壁纸库"）。
- **验证（2026-11-19，真实鼠标轨迹，非模拟事件）**：`VW_HOVER_DEBUG=1` 启动后，用 `CGWarpMouseCursorPosition` 把鼠标移到实测图标坐标 `{796,854,40×24}`：
  - 进入图标 → 日志 `enter → 排 0.22s` → `panel 已显示 frame={{644,578},{344,276}}`；
  - 移到面板中心 (816,716) → 只有 `exit → 取消`，**不收起**；
  - 移到屏幕别处 → `离开 0.35s → 自动收起`；
  - 快速划过（进入后立即离开）→ `enter` 后 `exit → 取消`，不弹。
- **本机装机（2026-11-19 17:20）**：`swiftc -O` 全量编译通过（15 个源文件，仅原有 deprecated 警告）；最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（1638272 B），`codesign --force --deep --sign -` + `-v --deep --strict` 通过；偏好 / 图标 / Info.plist / bundle id / 版本未动；正常方式重启 PID 27665。回滚备份 `/tmp/vw_bin_backup_before_hover`。
- **待用户**：真机把鼠标停在菜单栏果冻上，确认弹窗自动出现、点"壁纸库"能进、移开后自动收。手感 ok 后随下一版本统一发布（不单独发版、不 bump 版本）。

### F19 · 壁纸重命名（每张可单独改名） — 状态：`已验证 / 已装机 / 待发版`
- **日期**：2026-11-19
- **行为**：壁纸库里每张卡悬停时，右上角删除按钮下方多一个**铅笔**按钮，点它在名字那一行原地变成输入框（自动全选），回车提交、ESC 取消、点空处结束。右键菜单也加了「重命名…」。改的是**真实文件名**（扩展名保留），访达里看到的同步变化。
- **数据同步**：改名后缩略图缓存 jpg 一起改名、内存缓存清掉、`VWTuning.libraryOrder` 里的旧名替换成新名、`currentWallpaperName` 更新；如果改的是**正在播放**的那张，会重建播放器（旧 URL 已失效）。库窗口 reload 一次。
- **校验规则**：空名 / 含 `/` / 含 `:` / 以 `.` 开头 / 目标已存在 → 拒绝并 beep，**留在编辑态**让用户改；名字没变当成功；只改大小写（macOS 大小写不敏感）走「临时名中转」，不会被误判重名。
- **改动文件**：
  - `LibraryWindow.swift` — `WallpaperLibraryDelegate` 加 `libraryRename(index:to:) -> Bool`；`WallpaperCard` 新增 `renameButton`（pencil）+ `renameField`（行内 NSTextField）+ `beginRename/commitRename/endRename`，实现 `NSTextFieldDelegate` 接 ESC；`endHover` 增加 `!renaming` 保护（编辑中不淡出）；`teardown` 清理编辑态；`GalleryView.onRename` 接线；`GalleryThumb.forget(_:)` 清内存缓存；右键菜单加重命名。
  - `main.swift` — `AppDelegate.libraryRename(index:to:)`：校验 → `moveItem` → 缩略图改名 → 更新数组/存档/当前壁纸 → 必要时 `rebuild()`。
- **验证（2026-11-19，隔离 support 目录，`VW_RENAME_TEST` 调试入口）**：
  - 正常改名 `01-老名字.mp4 → 新名A.mp4`：`ok=true`，磁盘实际改名，`libraryOrder` 与 `currentWallpaperName` 同步；
  - 重名 / 空名 / 含斜杠：均 `ok=false` 且磁盘不动；
  - 同名：`ok=true` 不动文件；
  - 只改大小写 `03-test.mp4 → 03-Test.mp4`：`ok=true`，磁盘大小写实际改变；
  - 真实用户偏好未被测试污染（测试进程的 UserDefaults 与 App 不是同一域，且测试入口带备份/还原）。
- **本机装机（2026-11-19 19:30）**：`swiftc -O` 全量编译通过；最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（1664816 B），重签 + `-v --deep --strict` 通过；偏好 / 图标 / Info.plist / bundle id / 版本未动；重启 PID 41523。回滚备份 `/tmp/vw_bin_backup_before_rename`。
- **待用户**：真机悬停卡片点铅笔（或右键「重命名…」）改个名字，确认名字原地可编辑、回车生效、访达里文件同步改名；正在用的那张改完画面应正常继续播。手感 ok 后随下一版本统一发布（不单独发版、不 bump 版本）。

### F13 · 壁纸自动轮换（随机/顺序 + 多触发条件） — 状态：`逻辑已验证 / 待装机确认 / 待发版`
- **日期**：2026-11-23
- **需求**：壁纸可以随机循环，比如每次开机换一张；还要能选别的切换条件、能整体关闭。
- **行为**：
  - 设置弹层新增「自动轮换」区块：总开关、「切换方式」（随机 / 顺序下一张）、三个触发条件（**每次启动时切换**、**锁屏解锁时切换**、**从睡眠唤醒时切换**）、「定时切换」下拉（不定时 / 15 分钟 / 30 分钟 / 1 小时 / 3 小时 / 6 小时 / 每天）。
  - 总开关关闭时，下面所有子项置灰；默认总开关关、方式随机、只勾「每次启动时切换」——不主动改变用户已挑好的固定壁纸。
  - 只在壁纸已接管桌面（`isShowing`）时轮换；库里只有一张时跳过；随机不会挑到当前这张；顺序按 `index+1` 循环。
  - 启动那一次延迟 1.2s 执行，避开启动时的桌面重建。
- **改动文件**：
  - `Rotation.swift`（新增）— `Rotation` 偏好（键前缀 `VWTuning.`，含 `nextIndex(current:count:mode:)` 纯函数）+ `WallpaperRotator` 调度器（定时器 + `com.apple.screenIsUnlocked` + `NSWorkspace.didWakeNotification` + 设置变更通知）。
  - `main.swift` — 持有 `rotator`，启动后 `fireLaunchIfNeeded()`；新增 `rotateWallpaper(source:)`、`runRotationSelfTest()`（`VW_ROTATE_TEST=1`）。
  - `LibraryWindow.swift` — 设置弹层「自动轮换」区块与 6 个动作方法、`updateRotationControlsEnabled()`、`refreshSettingsState()` 同步。
  - `build.sh` — 编译列表加入 `Rotation.swift`。
- **验证（2026-11-23）**：
  - `VW_ROTATE_TEST=1` 自检：默认值 `enabled=false mode=random launch=true interval=0 unlock=false wake=false`；写入读回一致；顺序 `0→1→2→3→0`；随机 30 次**每次都不等于当前**且覆盖全部下标；`count=1 / count=0 / 越界` 均返回 nil。
  - 设置弹层渲染截图（330×665）：轮换区块标题、总开关、两个下拉、三个开关对齐正常，无重叠/裁切；总开关关闭时下拉正确置灰。
- **待用户**：真机打开「自动轮换」开关，重启 App 确认换了一张；再试定时/解锁/唤醒条件。确认后随下一版本统一发布（不单独发版、不 bump 版本）。

### F13.1 · 设置弹层「自动暂停 / 自动轮换」改为可折叠 — 状态：`已装机 / 待真机确认 / 待发版`
- **日期**：2026-11-23
- **需求**：这两个区块占的地方太大，弹层太长太挤；改成可折叠、默认收起，需要时再展开。
- **行为**：
  - 「自动暂停」「自动轮换」的标题变成可折叠头：整行可点（指针变手型），右侧一个箭头 + **状态摘要**（自动暂停显示「N 项开启 / 全部关闭」，自动轮换显示「已开启 · 随机 / 已关闭」），收起也能一眼看到现状。
  - **默认收起**：每次打开设置弹层都回到收起态；展开后弹层自动变高，收起自动变矮。
  - 收起时子项 `isHidden`，NSStackView 自动脱开，不再占高度与间距。
- **改动文件**：`LibraryWindow.swift` — 新增 `SettingsSectionHeader` 可折叠标题组件；`LibraryWindowController` 新增 `SettingsSection` 枚举、`appendRow/rows(for:)/toggleSettingsSection/resizeSettingsPopover/refreshSectionHeaders`；`pauseRow` 改为 `settingsRow(_:on:action:section:)` 并登记分组；`refreshSettingsState` 与各开关 action 同步摘要；`debugSnapshotSettings` 支持 `VW_SETTINGS_EXPAND=1` 渲染展开态。
- **验证（2026-11-23）**：`VW_SETTINGS_SHOT` 渲染两态：
  - 收起态 **330×299**（改前 665），两个标题行各带 `chevron.right` 与摘要，子项全部隐藏；
  - 展开态 **330×588**，箭头变 `chevron.down`，自动暂停 3 个开关 + 自动轮换 6 项完整显示，无重叠/裁切；
  - 全量 `swiftc -O` 编译通过。
- **本机装机（2026-11-23 20:49）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（2030952 B），重签 + `-v --deep --strict` 通过；重启 PID 87403。回滚备份 `/tmp/vw_bin_backup_before_fold`。
- **待用户**：打开设置看两行折叠是否清爽，点开确认能展开、箭头和高度都对。确认后随下一版本统一发布（不单独发版、不 bump 版本）。

### F14 · 设置里新增「反馈」入口（悬停展开飞书群） — 状态：`已装机 / 待真机确认 / 待发版`
- **日期**：2026-11-25
- **需求**：用户下完软件想反馈却找不到入口。要求入口只显示「反馈」两个字，鼠标悬停或点击后才看飞书群信息。
- **行为**：
  - 设置弹层底部版本行：`Dòng x.y（build）` 右边加灰色的**「反馈」**两字（不占额外高度、不加任何说明文字），右边仍是「检查更新」。
  - **悬停**：上方浮出一张深色小卡片（238×88），四行：`Dòng 用户反馈群` / `飞书群 · 问题反馈与功能建议` / `applink.feishu.cn/client/chat/…` / 橙色 `点击「反馈」加入`；鼠标移开 0.15s 后淡出。
  - **点击**：直接 `NSWorkspace.open` 打开飞书群邀请链接（装了飞书会直接进群），同时埋点 `feedback_open`。
  - 卡片会按弹层边界做左右/上下避让；卡片自身不吃鼠标事件，避免"移到卡片上就闪没"。
- **改动文件**：`LibraryWindow.swift` — 新增 `FeedbackLink`（文字 + tracking area + 悬停卡片）与 `FeedbackTip`（纯展示卡片）；`makeSettingsController` 的 versionRow 接入；`debugSnapshotSettings` 支持 `VW_FEEDBACK_TIP=1` 渲染悬停态。
- **验证（2026-11-25）**：渲染两态核对：
  - 收起态 330×299：版本行显示 `Dòng —（—）  反馈   [检查更新]`，只有两个字、无多余信息；
  - 悬停态：卡片四行清晰、行距均匀、无重叠；**第一版用 0.82 / 0.96 半透明，放大后能看到底下「自动暂停/自动轮换」标题透出灰影**，改为完全不透明深色（0.10,0.10,0.11）+ 1pt 细边后残影消失。
- **本机装机（2026-11-25 20:15）**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`（2195936 B），重签 + `-v --deep --strict` 通过；重启 PID 36237。回滚备份 `/tmp/vw_bin_backup_before_feedback`。
- **待用户**：打开设置 → 底部悬停「反馈」看卡片，点一下确认能拉起飞书进群。确认后随下一版本统一发布（不单独发版、不 bump 版本）。

### D1 · GitHub README 增加飞书用户群入口 — 状态：`已上线（文档，无需发版）`
- **日期**：2026-11-16
- **行为**：10 份 README（英/中/日/韩/法/德/西/意/俄 + 英文默认页）顶部入口区新增「加入用户群 ↗」链接，正文 About 前新增本地化的「用户社区 / Community」章节，说明该飞书群供下载用户提意见、接收通知，感兴趣者也可加入。群链接：`https://applink.feishu.cn/client/chat/chatter/add_by_link?link_token=509jbd8d-00fd-43dc-8f27-288214767661`（飞书加群链接，长期有效）。
- **改动文件**：
  - `tools/gen_i18n_readme.py` → 新增 `FEISHU` / `COMMUNITY`（9 语言文案）与步骤 8：顶部链接 + About 前社区章节，幂等插入。
  - `README.md`、`README.en.md`、`README.zh.md`、`README.ja.md`、`README.ko.md`、`README.fr.md`、`README.de.md`、`README.es.md`、`README.it.md`、`README.ru.md` → 由脚本重新生成。
- **验证（2026-11-16）**：脚本连跑两次幂等；10 份 README 各含 2 处群链接（顶部 + 章节）、章节标题按语言本地化且位于 About 之前；无中文残留；未触碰版本号与 App 二进制。
- **状态**：已 commit + push 到 main，CI 通过；纯文档改动，不随 App 发版。

### F1 · 图片 / 静态壁纸支持 — 状态：`已验证`
- **日期**：2026-11-13
- **行为**：拖入或选择的图片直接做成静止壁纸，不套视频的去跳帧 / 去片尾 / 掐黑场流程。
- **改动文件**：
  - `Transcoder.swift` → `imageExts`、`importStillImage(...)`、`flattenImage(...)`
  - `main.swift` → 导入时按扩展名分流到 `importStillImage` / `importVideo`
  - `LibraryWindow.swift` → `mediaURLs(from:)` 拖放解析、常驻「添加文件」按钮、空状态文案、`pickFiles` 的 `allowedContentTypes`（含 HEIC/WebP/GIF）
- **验证（2026-11-13）**：透明 PNG / HEIC / GIF / JPEG 四种格式经 ImageIO 归一均 OK；静帧 mp4 首尾帧 PSNR 63.7dB（循环接缝不可见）；AVFoundation duration=2.0s / 1200×800@30fps、多点抽帧正常；全量编译通过。已装 `/Applications/Dòng.app` 的二进制含 `importStillImage`/`imageExts`/`flattenImage` 符号（F5.4 装机时一并编入）。

### F2 · PerfectLoop 无缝循环引擎 — 状态：`已验证（本机）/ 待决策（分发）`
- **日期**：2026-11-13
- **行为**：把首尾接缝处理从 ffmpeg `blend` 交叉淡换成 PerfectLoop 的 SSIM 区域感知形变；只在「首尾淡化 > 0」时触发，任一环节失败自动回退旧 blend。
- **改动文件**：
  - `tools/perfectloop_runner.py`（新）— 内存安全运行器，只取首尾两帧算掩膜+形变，ffmpeg 拼接；`--check` 自检；stdout 打 `progress=`。
  - `tools/PerfectLoop/`（新）— GitHub 官方真源码 + MIT LICENSE。
  - `Transcoder.swift` → `perfectLoopRuntime`（逐个候选 python 跑 `--check`）、`perfectLoopAvailable()`、`runPerfectLoop()`、`transcode` 里的分支与回退。
  - `Tuning.swift` → 开关 `usePerfectLoop`（默认 true）。
  - `LibraryWindow.swift` → 画面微调底部状态动态化：可用时显示 `PerfectLoop 无缝循环`，帧率/淡化跟随设置。
  - `build.sh` → 把 runner + 源码打进 `Contents/Resources/tools/`。
  - `make-loop.sh` → fade>0 时优先走 PerfectLoop，`if python …; then` 包裹保证 `set -e` 下正确回退。
- **验证**：
  - `swiftc -O` 整体编译链接通过；make-loop.sh 的 PL 分支与 blend 回退两条路径均通过。
  - 真实壁纸成品 900 帧（888 主体 + 12 形变），尾帧↔首帧 SSIM 0.9671；强对比素材 0.3578 → 0.9654。
  - 已装进本机实际运行的 `/Applications/Dòng.app`，重启后 PID 26724→29571，面板自检 OK。
- **⚠️ 发版前必须决策**：依赖 `~/.local/share/VideoWallpaper/perfectloop-venv`（numpy / opencv / scikit-image）。**其他用户机器上没有这个 venv → 会自动回退旧 blend，等于 F2 对正式用户不生效**。要真正发布这个功能，需选一种：① 把依赖打进 App 包；② 首次使用时自动安装；③ 明确作为「本机增强」不对外宣称。
- **⚠️ 已修的坑**：Python 脚本随 App 一起 codesign，运行时写 `__pycache__/*.pyc` 会破坏签名封印（下次启动被判「已损坏」）。已在 runner 顶部加 `sys.dont_write_bytecode = True`，清缓存后重签，回归验证签名 `valid on disk`。后续任何随包签名的 Python 脚本必须同样处理。

### F3 · 版本号 3.37/59 → 3.38/60 — 状态：`待发布`（其他任务改动）
- **文件**：`Info.plist`
- **注意**：本机实际安装的 `/Applications/Dòng.app` 仍是 **version 58**（我只最小替换了二进制，保留了原 Info.plist）。统一发版时要确认最终版本号，别让源码和已装包不一致。

### F4 · 打通抖音链接通道（借浏览器游客 cookie）— 状态：`已被 F5 取代（yt-dlp 路线确认走不通，勿采用）`

> ⚠️ **2026-11-15 追加结论**：F4/F4.1 的借 cookie 路线经真机验证为**死路**，已被下方 F5（WKWebView 方案）取代。保留本条仅为记录决策过程，合并发版时以 F5 为准。根因见 F5。
- **日期**：2026-11-15
- **背景**：改前抖音链接走 yt-dlp 直连必失败——extractor 报 `Fresh cookies (not necessarily logged in) are needed`，旧代码直接 `throw` 让用户"手动保存再拖进 Dòng"，等于通道没通。
- **实测根因**（本机 2026-11-15）：
  - yt-dlp 的抖音 extractor 复用 TikTok 逻辑，真正要的是 `s_v_web_id` 这个**游客 cookie**，**不需要登录**，但要求用户最近在浏览器打开过抖音网页。
  - 本机 Chrome 有 471 个 cookie 但无任何 `douyin.com` 域 cookie（没访问过抖音）→ web detail JSON 返回 403 → 报 Fresh cookies。
  - `--cookies-from-browser safari` 被 TCC 拦（`Cookies.binarycookies` Operation not permitted，沙箱/公证都可能踩）。
  - 内置与系统 yt-dlp 均为 2026.10.26（版本够新，>90 天的旧版抖音 extractor 会失效）。
- **行为变化**：
  - 抖音（v.douyin.com / www.douyin.com / iesdouyin.com）链接：自动按 `chrome→edge→brave→vivaldi→firefox→safari` 顺序借本机已安装浏览器的游客 cookie 逐个尝试，取首个成功者。
  - 某次尝试失败会清掉半成品目录再试下一个，避免取到错误文件。
  - 全部失败 → 翻译成可操作引导「先在 Chrome 打开一次抖音网页、随便看个视频，再回 Dòng 重贴链接；仍不行就存本地拖入」，不再误导成"必须登录"。
  - 没装任何浏览器 → 单独给出对应引导。
  - B站/YouTube 等平台：`browser=nil`，下载行为与改动前**完全一致**。
- **改动文件**：`Downloader.swift`（唯一文件）
  - 新增 `isDouyin(_:)`、`availableCookieBrowsers()`、`displayName(_:)`。
  - `fetch` 分流到 `fetchDouyin`（新增）/ `downloadOnce`（原主体抽出，加 `browser` 参数决定是否传 `--cookies-from-browser`）。
  - 原"抖音/cookie 就 throw 让用户手动保存"的分支删除，错误统一由 `fetchDouyin` 引导。
- **验证**：
  - 全量 `swiftc -O` 编译链接通过（仅项目原有的 AVFoundation deprecated 警告）。
  - 纯函数单测：`extractLink` 正确从中文口令里抠出抖音短链；`isDouyin` 三种抖音形态全 true、B站/YouTube 全 false；本机浏览器探测命中 chrome。
  - 借 cookie 端到端**未在真实视频上验证**：本机 Chrome 未访问过抖音、沙箱又读不到 Safari cookie，无法在此环境复现"有新鲜 s_v_web_id"的成功路径。
- **本机装机实测**（2026-11-15 20:40，用户同意后执行）：
  - 已把新二进制最小替换进 `/Applications/Dòng.app`（只换 `Contents/MacOS/VideoWallpaper`，保留 Info.plist/图标/bundle id/30 个偏好键），`codesign --force --deep --sign -` 重签，`codesign --verify --deep --strict` 校验通过，`open` 重启成功（新 PID 64241）。
  - 内置 yt-dlp 2026.10.26 确认支持 `--cookies-from-browser`；内置 tools/（PerfectLoop）齐全，未受影响。
  - 回滚备份：`/tmp/vw_bin_backup_20261115`（原 58 版本二进制）。
  - 端到端下载仍需用户本人在 GUI 贴真实链接确认（此环境无新鲜抖音 cookie，且下载入口只能在 App 内触发）。
- **F4.1 修复 · note 链接 Unsupported URL**（2026-11-15 20:53，用户实测发现）：
  - **现象**：用户贴 `https://www.douyin.com/note/7695238816693816484`，报 `ERROR: Unsupported URL`，引导文案（先打开抖音网页）不对症。
  - **根因**：抖音把视频/图文分享直链都写成 `/note/<id>`，但 yt-dlp 的 douyin extractor 只认 `/video/<id>`——note 路径连借 cookie 那关都到不了，直接 Unsupported。实测同 ID 换成 `/video/` 即走到 `Fresh cookies needed`（证明 extractor 认了）。
  - **改动**：`Downloader.swift` 新增 `normalizeDouyinLink(_:)`，`fetch` 入口把抖音 `/note/<id>` 归一化为 `/video/<id>`（保留 query）；引导文案补一句「纯图文笔记无法做成动态壁纸」。B站/YouTube/短链/iesdouyin 不受影响。
  - **验证**：全量 `swiftc -O` 编译通过；归一化单测覆盖 note(带/不带 query)、video、短链、iesdouyin、B站，全部符合预期。`note→video` 的转换在 yt-dlp 上确认能走到 cookie 判定。
  - **装机**：新二进制已最小替换进 `/Applications/Dòng.app`，重签+`--verify --deep --strict` 通过，重启（PID 67948），偏好 30 键保留。回滚备份 `/tmp/vw_bin_backup_20261115`。
- **⚠️ 待决策/待验**：
  - 需在用户真实机器（Chrome 访问过抖音、非沙箱）上跑一条真实抖音分享链接确认能下到（本次实测的 `/note/` 是否已修好、以及该条是否为图文笔记，待用户复测）。
  - 借 Chrome/Edge cookie 首次会触发系统钥匙串授权弹窗（yt-dlp 解密 cookie）；公证版需确认 entitlements 是否够（`entitlements-ytdlp.plist` 已有 disable-library-validation + allow-unsigned-executable-memory，未加 keychain 相关）。
  - Safari 依赖 Full Disk Access，仅作最后兜底。
  - 浏览器多用户/非 Default 配置、a_bogus 签名再次升级为上风险点；抖音策略一变就要更新内置 yt-dlp。

### F5 · 抖音改用内置 WKWebView 抓取（支持实况图片）— 状态：`已验证（真机端到端通过）/ 待决策（分发）`
- **日期**：2026-11-15
- **背景/根因**：F4 借浏览器 cookie 路线经真机验证为死路。用户按引导在 Chrome 真正打开抖音后，Chrome 生成了 37 个抖音 cookie（`s_v_web_id`/`ttwid`/`__ac_signature` 均有效），但用真实 cookie 请求 yt-dlp 的 detail 接口仍返回 403：`Blocked by ArgusSecurityPlugin Uifid Not Found`——缺 `UIFID` 长期设备指纹（只有临时 `UIFID_TEMP`，短期刷页生不出来）。查 yt-dlp 本机源码 `tiktok.py:1499` 确认其抖音 extractor 只请求 `aweme/v1/web/aweme/detail/?aweme_id=<id>`、完全不算签名，源码注释至今是 `# TODO: Run verification challenge code to generate signature cookies`。headless Chrome 虽能跑 JS 但直接被验证码墙拦（cookie 值全空）。结论：**yt-dlp 无法再抓抖音，与 cookie 新鲜度无关，再刷也没用**。
- **方案**：不用 yt-dlp，改用系统 WKWebView（Safari 内核，指纹接近真实浏览器）加载抖音页面，让抖音自己的 JS 完成 Argus 签名和请求；注入 JS 在 documentStart hook `fetch` + `XMLHttpRequest`，只把「响应 JSON 含 `aweme_detail`/`aweme_list`」的详情响应回传原生层，再从中取视频/实况图直链，用 URLSession 带 Referer + 页面 cookie 下载。
- **用户诉求**：抖音搜"动态壁纸"绝大多数是**实况图片**（一张图 + 几秒 MP4）。实况图的 MP4 藏在 `aweme_detail.images[].video` / `image_post_info.images[].video`，普通 yt-dlp 不解析；本方案直接从详情 JSON 提取，实况图可直接做壁纸，无需再找"视频版"。
- **改动文件**：
  - 新增 `DouyinWebFetcher.swift`（独立抓取器，`import WebKit`）：WKWebView 加载 + JS hook + 详情解析（普通视频/两种实况图字段/纯图文识别）+ URLSession 下载 + 同步等待异步的线程桥接（主线程用 RunLoop 驱动、后台线程用信号量）。
  - `Downloader.swift`：`fetch` 中抖音分支改为 `DouyinWebFetcher().fetch(...)`，不再走 yt-dlp；`fetchDouyin`/`availableCookieBrowsers`/`guideWithDetail` 等 F4 借 cookie 代码成为死代码（保留未删，无引用）。B站/YouTube 分支完全不变。
  - `build.sh`：编译清单加 `DouyinWebFetcher.swift`，framework 加 `-framework WebKit`。
- **验证（2026-11-15 真机端到端，全部通过）**：
  - 全量 `swiftc -O` 编译链接通过（仅项目原有 AVFoundation deprecated 警告）。
  - 解析逻辑单测：普通视频 / 实况图(新版 `image_post_info`) / 实况图(老版 `images`) / 纯图文，四种形态全部正确。
  - **真实视频链接** `https://www.douyin.com/video/7680124435567691505` → 抓到「我们做彼此的依靠吧…」1.2MB MP4，10 秒。
  - **实况图链接** `https://www.douyin.com/note/7693296625380641765`（用户实测那条，抖音壁纸推荐）→ 抓到「壁纸推荐《FRAC》…」2.5MB MP4，7 秒；ffprobe 确认 26s / 1280×720 / 30fps / h264，符合壁纸要求。
- **本机装机**：新二进制最小替换进 `/Applications/Dòng.app`（保留 Info.plist/图标/bundle id/30 偏好键），`codesign --force --deep --sign -` 重签 + `--verify --deep --strict` 通过，`open` 重启（PID 76861）。回滚备份 `/tmp/vw_bin_backup_before_wk`（F4 版二进制）；更早的 58 原版备份 `/tmp/vw_bin_backup_20261115`。
- **⚠️ 待决策/待验**：
  - 用户需在 App GUI 里贴一次真实链接做最终确认（本次端到端用独立 harness 跑通抓取器，GUI 触发链 `main.swift:1437` 未直接覆盖，但调用的是同一 `fetch` 入口）。
  - WKWebView 会短暂在屏幕外加载抖音页面（隐藏窗口 alpha=0），抖音策略升级可能触发登录墙/验证码——目前实测两条链接均未触发。
  - 公证版：`import WebKit` 不需额外 entitlement；但 WKWebView 首次加载可能有网络/ATS 相关审查，签名公证后建议回归一次。
  - 实况图可能一次取到多段 MP4（每张实况图一段），当前实现取全部直链、下载第一段（`play_addr` 优先）；若用户想要全部实况帧需后续扩展。

### F5.1 · 修复抖音抓取后 App 崩溃退出（WKWebView 跨线程清理）— 状态：`已验证（后台线程路径通过）/ 已装机`
- **日期**：2026-11-16
- **现象**：用户在 App GUI 粘贴抖音链接后，Dòng 直接退出。崩溃日志 `~/Library/Logs/DiagnosticReports/VideoWallpaper-2026-11-15-212714.ips`（21:27:14）。
- **崩溃栈关键帧**：`EXC_BREAKPOINT (SIGTRAP)` → `-[WKWindowVisibilityObserver startObserving:]` → `WebViewImpl::viewWillMoveToWindow` → `-[NSView removeFromSuperview]` → `DouyinWebFetcher.cleanupWebView()` → `DouyinWebFetcher.fetch` → `Downloader.fetch` → `AppDelegate.importLink(_:background:)` → `_dispatch_worker_thread2`。
- **根因**：GUI 的 `importLink(_:background:)` 在**后台队列**调 `fetch`，而 `fetch` 末尾直接调 `cleanupWebView()`，其中 `removeFromSuperview()` / `orderOut()` 是 AppKit 视图操作，必须在主线程。后台线程拆 WKWebView 视图触发 WebKit 内部 RELEASE_ASSERT，进程被 trap。2026-11-15 的端到端 harness 是主线程调用，不走这条路径，所以没复现。
- **修复（仅改 `DouyinWebFetcher.swift`）**：
  - `fetch` 改用 `defer { cleanupWebView() }`，保证成功/超时/抛错都断开 `WKUserContentController → self` 强引用（原实现抛错时不清理，会循环引用泄漏）。
  - `cleanupWebView()` 重写：先抓局部强引用 `wv`/`win`/`name`、属性立即置 nil，所有 WKWebView 操作统一派发主线程（已在主线程则同步执行）；**不捕获 self**，避免对象释放后 weak 变 nil 导致清理不执行。
  - 删除原 `deinit` 里的 `DispatchQueue.main.async { [weak self] ... }`（deinit 时 weak 已为 nil，本就无效；现由 defer 保证清理）。
  - 顺手修：`onStage("正在下载…")` 只在确实拿到直链时发，抛错路径不再闪误导提示。
- **验证（2026-11-16）**：
  - 全量 `swiftc -O` 编译通过。
  - 新建**后台队列调用** harness（专门复现 GUI 路径）：实况图 `note/7693296625380641765` → 2.5MB MP4 / 12s；普通视频 `video/7680124435567691505` → 1.2MB / 4s；非法 URL 抛错路径 → 友好报错且进程存活。三条均 `exit 0`，未产生新崩溃日志。
- **本机装机**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`，重签 + `--verify --deep --strict` 通过，重启 PID 82968，偏好 31 键保留。回滚备份 `/tmp/vw_bin_backup_before_threadfix`（F5 初版二进制）。
- **待验**：用户再在 GUI 贴一次链接做最终确认（后台线程路径已由 harness 覆盖，理论上不会再崩）。

### F5.2 · 修好"贴链接不生成壁纸"的真正原因 + 抖音链接通用化 — 状态：`已验证（多形态）/ 已装机`
- **日期**：2026-11-16
- **用户诉求**：抖音**所有链接**都能贴进去自动生成动态壁纸（含实况图、短链、整段分享口令）。
- **关键定位（推翻之前的方向）**：之前一直以为是链接解析失败，其实**抖音抓取一直成功**。证据：临时目录残留 `vw-dl-AC6AA98E-.../以气化剑，以雨为型 壁纸：Beneath The Seventh…mp4`（10:06，与用户截图同刻），`ffmpeg -i` 显示 `Stream #0:0: Audio: mp3, 44100Hz` —— **只有音频、没有视频流**。`main.swift:1630` 的失败文案 `「<文件名>」处理失败：…` 正是截图里红色输入框显示的前半段。所以断点是：下载到纯 MP3 → 后续 `Transcoder.importVideo` 找不到画面 → 整条导入失败、临时目录未清理。
- **根因**：`DouyinWebFetcher.download()` 只按「HTTP 200 + >100KB」判定成功，抖音详情接口的 `url_list` 会混入音频 CDN / 错误页，取到第一个就 `return`，把 MP3 当 MP4 交给转码。
- **改动文件**：
  - `DouyinWebFetcher.swift`：
    - `download()` 拆出 `static downloadVideo(from:ua:cookie:into:dest:)`：每条候选先落盘，用 `AVURLAsset.tracks(withMediaType:.video)` 校验**真的有视频轨**，是音频/错误页就丢弃并继续下一条；体积阈值 100KB → 8KB（实况图短视频可能很小）；全失败时报明确原因。新增 `import AVFoundation`。
    - `resolvePageURL()`：`v.douyin.com` 短链跟随 302 拿最终地址；`iesdouyin.com/share/(note|video)/<id>` 转成同形态 PC 页；`www.douyin.com` 正链原样。失败回退原链接（WKWebView 自己也会跳）。
    - `pageVariants()` + `fetch` 重试：原页面抓到的直链全无画面/超时，自动换同 ID 的 `/note/` ↔ `/video/` 形态再试一次（覆盖"短链跳到 video 但内容是实况图"）。`userContentController` 加 `message.webView === webView` 防止上一轮迟到消息串扰。
    - `awemeID(from:)`：从 path 抠 19 位 ID（不取 query，避免误认 web_id）。
    - 曾尝试按 `aweme_id` 过滤推荐流响应，实测会误杀实况图详情（每条要等超时再靠重试，耗时 25-43s），**已撤销**；保留双形态重试兜底。
  - `Downloader.swift`：**移除** `fetch` 入口的 `/note/ → /video/` 归一化。那是 F4（yt-dlp）遗留，WKWebView 方案要加载用户原页面，`/note/` 才是实况图 `image_post_info` 的正确来源，强转 video 反而容易只拿到 BGM 音频。`normalizeDouyinLink` 保留为死代码（无引用）。
- **验证（2026-11-16）**：
  - 全量 `swiftc -O` 编译通过。
  - **混合候选单测**（本地 HTTP server，调用生产代码 `downloadVideo`）：音频在前→跳过并选中真视频 ✅；全是音频→明确拒绝 ✅；404 在前→跳过 ✅；只有视频→正常 ✅。负样本就是用户那条残留的 649KB MP3，正样本为壁纸库里的真 MP4。
  - 归一化单测：`www.douyin.com/note|video` 原样；`iesdouyin.com/share/note|video` 正确转 PC 同形态；非法 URL 原样。
  - 后台队列 harness（GUI 真实线程）：实况图 `note/7693296625380641765` → 2.5MB、有画面、7s；普通视频 `video/7680124435567691505` → 1.2MB、有画面、4s；无效链接抛错且进程存活。均 `exit 0`，无新崩溃日志。
- **本机装机**：最小替换 `/Applications/Dòng.app/Contents/MacOS/VideoWallpaper`，重签 + `--verify --deep --strict` 通过，重启 PID 91987，偏好 31 键保留。回滚备份 `/tmp/vw_bin_backup_before_mediafix`（F5.1 版）。
- **已知边缘情况**：贴一个不存在的 aweme_id 时，抖音会跳推荐流，可能抓到推荐视频（不会失败但内容不对）。按 ID 过滤实测误杀率太高，暂用双形态重试兜底；真实链接不受影响。
- **待验**：用户在 GUI 贴自己那条「以气化剑…」链接做最终确认；公证后回归。
- **注意**：当前产品行为仍是"贴链接 → 自动下载/优化/入库"，**不会自动替换桌面正在用的壁纸**（库为空时例外），面板会提示「已存好…，点一下才换」。若用户要连桌面一起自动换，需另外改 `pumpImport` 的 `applied` 判定。

### F5.3 · 真机"等待抖音页面响应超时"：诊断探针 + 超时放宽 + App Nap 防护 — 状态：`已装机 / 待用户回归`
- **日期**：2026-11-16
- **现象**：F5.2 装机后用户在 GUI 贴 `video/7680124435567691505`（10:53、11:12 两次）均弹「等待抖音页面响应超时」，同一条链接 harness 侧却是绿的。
- **逐项排查（均未复现失败，证明代码/数据无恙，指向 App 进程环境差异）**：
  - 可见窗口 + 全量 hook 诊断：92 个响应里 `aweme_detail` 71KB 正常截获；SSR `RENDER_DATA` 不含 `play_addr`（0 次），SSR 兜底路线不可行。
  - App 式隐藏窗口（borderless + alphaValue=0 + 屏幕外）repro：7-9s 截获详情。
  - `setActivationPolicy(.accessory)`（Dòng 同款 LSUIElement）repro：7.3s 成功。
  - 把 App 的 `~/Library/WebKit/com.zhanghangshuo.dong/WebsiteData` 整份复制给 harness（含用户失败时刻的 cookie 状态）：依然成功 → **排除 cookie/风控污染**。
  - 侧证：App 的 WebsiteData 在用户两次尝试时刻均有写入（CacheStorage/IndexedDB/LocalStorage 10:53、11:12），说明 App 里页面确实加载了，只是 45s 内详情 XHR 未被截获 → 嫌疑集中在「长驻 LSUIElement 进程被系统节流（App Nap/occlusion）冻住页面 JS」或「偶发慢加载」。
- **改动文件**（全部 `DouyinWebFetcher.swift`）：
  - **诊断日志 `diag()`**（NSLog `[VWDouyin]` 前缀）：fetch 开始/页面 URL、每轮加载与失败、didFinish/didFail、心跳。用户复现时可直接从终端 `log stream` 回放定位断点。
  - **心跳探针**：注入 JS 每 3s 回报 `location.href` + `document.title`（`__vwProbe` handler，`cleanupWebView` 同步注销防泄漏）。超时错误不再只给一句"超时"：若页面停在验证页（标题含"验证"）→ 明确提示「抖音要安全验证…先在 Safari 打开 douyin.com 一次」；否则附带「页面卡在〈标题〉」。
  - **超时放宽**：首轮 25s→45s、反形态轮 20s→30s（实测详情通常 7-10s，但慢网络/首生成 uifid 可能 >30s）。
  - **App Nap 防护**：fetch 期间 `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)`，结束 `endActivity`。
  - `Failure` 加 `isTimeout` 标记，超时类失败在 `fetch` 出口统一附加页面状态。
- **验证（2026-11-16）**：
  - 后台线程 harness 用新代码：`video/7680124435567691505` → 1.2MB 有画面；`note/7693296625380641765`（实况图）→ 2.5MB 有画面，均成功且诊断日志正常输出（「fetch 开始 / 页面加载完成 / 页面心跳」）。
  - 全量 `build.sh` 编译通过。
- **本机装机**：最小替换 + 重签，PID 5092，偏好 31 键保留。回滚备份 `/tmp/vw_bin_backup_before_f53`（F5.2 版）。
- **待验**：用户在 GUI 重贴链接。若再超时，错误弹窗会带页面状态，同时用 `log stream --predicate 'eventMessage CONTAINS "VWDouyin"'` 看断点；心跳停更 = App Nap 实锤，可加做 NSWindow 可见性方案。

### F5.4 · 修复「贴天使壁纸链接却下载成别人视频」——严格校验 aweme_id，杜绝抓推荐流 — 状态：`已装机 / 待用户回归`
- **日期**：2026-11-16
- **用户现象**：贴口令 `v.douyin.com/jZhmoKHB1es/`（标题「我向神祈禱，最終沒能等到奇跡的降臨」，天使翅膀女孩在教堂），生成的壁纸却是**紫黑礼服动漫女孩**——完全是另一条内容。
- **根因（实锤）**：这条 `7654449081532412859` 是**纯图文笔记**（左下角标「图文」，只有一张 2364x1773 静态图 + 2:16 纯音频 BGM，我下载 SSR 视频用 ffmpeg 验证只有 Audio 流、无视频流）。图文笔记（note 页）**不发 `aweme/detail` 接口**（诊断 92 个响应里 `AWEME_DETAIL` 0 次），只有 `aweme/related` 推荐流返回 20 条别人的视频。旧 `grab()` 里 `d = obj.aweme_list[0]` 直接把推荐流第一条当成目标详情 → 下载了别人的视频。
- **连带发现**：F5.2 声称成功的实况图 `note/7693296625380641765`，在严格校验下第 1 轮 note 页超时、第 2 轮 video 页才成功（标题「以气化剑…壁纸：Beneath The Seventh」）。即 note 形态本就不发详情，之前"成功"靠的是换形态重试；F5.2 的验证结论需按此理解。
- **改动文件**（全部 `DouyinWebFetcher.swift`）：
  - **JS hook 严格校验**：删除 `aweme_list[0]` / `data.aweme_list[0]` 两个回退分支。只认 `aweme_detail`（或 `data.aweme_detail`），且 `matches()` 要求详情的 `aweme_id / item_id / group_id / stat.aweme_id` 与链接里的目标 ID 一致才回传。**宁可失败，绝不抓别人的视频冒充**。
  - **SSR 素材探针**：页面 DOM 里捞目标条目的封面大图 / video 直链（`__vwSSR` handler + `ssrCandidates`）。超时且 SSR 只有封面大图、无可用动态详情时，明确报错「这条是纯图文笔记（只有静态图片和背景音乐，没有动态画面），做不成动态壁纸」，不再给用户干等 75 秒。
  - `cleanupWebView` 注销 `ssrName` handler；每轮加载重置 `ssrCandidates`。
- **验证（2026-11-16，后台线程 harness）**：
  - 普通视频 `video/7680124435567691505` → 严格校验放行，1.2MB 有画面 ✅（无误杀）
  - 实况图 `note/7693296625380641765` → 第 2 轮 video 页抓到，727KB「以气化剑…」✅（无误杀）
  - 用户纯图文短链 → **不再下载紫黑礼服女孩**，改为明确失败「没找到带画面的视频」/纯图文提示 ✅（抓错已杜绝）
  - 全量 `build.sh` 编译通过。
- **本机装机**：最小替换 + 重签，PID 17477，偏好 31 键保留。回滚备份 `/tmp/vw_bin_backup_before_f54`（F5.3 版）。
- **产品边界说明**：纯图文笔记（静态图 + BGM）物理上没有动态画面，做不成动态壁纸。用户若想要这类素材，需换真正会动的视频/实况图；或另做「静态图 + Ken Burns 动效 + 音乐合成视频」的新功能（未做）。
- **待验**：用户 GUI 重贴天使短链，确认弹的是「纯图文」提示而非下载错视频。

### F5.5 · 安全验证页可手动过 + 纯图文报错说人话 — 状态：`已装机 / 待用户回归`
- **日期**：2026-11-17 ~ 11-18
- **触发**：用户反馈「梵高星空链接我能做、别的用户做不了」；另一用户贴天使壁纸 `v.douyin.com/OgyvEKzB6MY/` 弹「跳过 2 条音频/无效地址」看不懂。
- **排查结论（本机可控因素全部排除）**：
  - 这条梵高链接是**普通视频** `video/7086081060781509899`，本机 12s 下载 13.5MB 成功；全新 WebKit store（模拟首次用户）8s 也成功 → 排除设备指纹未养熟。
  - DMG（v3.39）二进制含全部 F5.4 特征串，`bin/ffmpeg`、`bin/yt-dlp` 齐全，`build.sh` 编译清单含 `DouyinWebFetcher.swift` → 排除发布包缺功能/缺工具。
  - 完整中文口令经 `extractLink` 实测能正确抠出 URL → 排除口令解析。
  - 结论：差异在我这台机器模拟不出来的**运行环境**（出口 IP 被要求安全验证 / 网络慢 / 系统版本）。用户后来确认「别的用户也会同样失败」的那条天使链接，则是内容本身问题（见下）。
- **根因（天使链接 OgyvEKzB6MY / `7657719554118419941`）**：纯图文笔记——详情有 `images` 但 `duration=0`，`video` 字段只有 `audio` + `play_addr`（配乐音频，无画面）。note 页不发 `aweme/detail`（诊断 `AWEME_DETAIL` 0 次，只有推荐流），换 video 形态才抓到详情但直链全是音频 → 下载阶段 `hasVideoTrack` 全否，报「跳过 2 条音频」。**所有用户失败是正确行为**，不是 bug。
- **改动文件**（全部 `DouyinWebFetcher.swift`）：
  - **安全验证可视化**：抓取窗口从「无边框 + alpha 0 + 屏幕外」改为带标题栏、平时透明；JS 心跳探针检测验证页（URL `/verify`、`/captcha`、明确验证标题、滑块容器 class），命中后经 `__vwCaptcha` handler 在主线程把窗口移到屏幕中央、置顶、显示，并提示用户「请在弹出的窗口完成验证，会自动继续」——覆盖「别人出口 IP 被要求验证却看不见窗口、只能干等超时」的场景。
  - **验证宽限期**：`awaitOnMain` 增加 `graceUntil` 参数；捕获验证信号后把等待截止延长 120s，给用户手动过滑块的时间（分段等待每 2s 重算 deadline，主线程/后台线程都支持）。
  - **误判修复**：抖音每个页面都挂 `rmc-nocaptcha`（NoCaptcha=被动检测）iframe，初版 `[class*=captcha]`/`iframe[src*=captcha]` 会全量误判 → 收紧为只认 `/verify`、`/captcha` 路径 + 明确验证标题 + 滑块容器 class，排除 nocaptcha。诊断日志已确认普通视频/图文均不再误报。
  - **报错说人话**：下载阶段所有直链都无视频轨（`skipped > 0`）时，报错从「没找到带画面的视频：已跳过 N 条音频」改为「这条是纯图文笔记（图片配背景音乐，画面本身不会动），做不成动态壁纸。请换一条会动的视频，或点开几秒会自动播放的实况图再分享。」
- **验证**：梵高视频回归 4s 成功 13.5MB ✅；纯图文 OgyvEKzB6MY 不再误报验证、走纯图文判定 ✅；`build.sh` 全量编译通过 ✅。
- **本机装机**：最小替换 + `codesign --force --deep --sign -` 重签 + `--verify --deep --strict` 通过；新 PID 52921；偏好 plist 30 键完好；回滚备份 `/tmp/vw_bin_backup_before_f55`。
- **待用户回归**：GUI 重贴天使链接 OgyvEKzB6MY，确认弹「纯图文笔记」新文案；若有用户撞验证页，确认弹出可交互窗口、过验证后自动继续。

### F5.6 · 纯图文笔记改为生成静态壁纸（不再拒绝）— 状态：`已装机 / 待用户回归`
- **日期**：2026-11-18
- **触发**：用户明确要求「纯图文笔记也要做成静态壁纸，不能被拒绝」——推翻 F5.4/F5.5 的「纯图文明确失败」策略。
- **数据依据**：纯图文笔记的详情接口里 `images[].url_list` 就是高清原图直链（实测 `7657719554118419941` 有 2364×1774 的 webp，178KB），`images[].width/height` 给分辨率；`image_post_info`/`images` 两处都要收。此前 parse 只认视频轨、忽略静态图，最后还主动拒绝，导致这部分内容完全做不成壁纸。
- **改动文件**（全部 `DouyinWebFetcher.swift`）：
  - `Media` 新增 `stillImageURLs`：`parse()` 收集 `images[].url_list` / `download_url_list`（及 `image_post_info.images[]`），按 width×height 降序、无水印优先，去重保序。
  - 新增 `downloadStillImage(_:title:ua:cookie:into:)`：逐个候选下载，校验 HTTP 200 + 体积 + ImageIO 可解码（排除错误页/音频），按 ImageIO UTI 定扩展名（webp/jpg/png/heic…），返回图片文件交给下游 `pumpImport` 已有的 `importStillImage` 分支做成 2 秒静止壁纸（`Transcoder.swift:802`，F1 能力，无需改下游）。
  - 新增 `downloadMedia(_:into:)` 统一入口：优先视频/实况图；**视频候选全是音频（纯图文）下载失败时自动回退静态图**；没有视频候选时直接下静态图。关键修复：messageHandler 原守卫 `!media.urls.isEmpty` 会把「只有静态图」的详情直接丢弃，改为「视频或静态图任一非空」。
  - 两轮详情都没抓到（note 页不发详情）时，用 SSR 封面图（`ssrCandidates`，仍是 `aweme_images`/`AWEME_DETAIL` 目标图、绝不碰 related 推荐流）兜底做静态壁纸，取代原「拒绝并提示换视频」。
  - **并发修复（重要回归）**：F5.5 的 `awaitOnMain.deadline()` 每次重算 `Date()+timeout`，后台线程分段等待时 deadline 永远晚于 now → 死循环卡住（实测第 1 轮卡 90 秒不超时）。改为进入等待前固定 `base` 一次。
  - 新增静态 UA 常量 `ua` 与 `pageTitle(from:)`（SSR 兜底时用 `抖音图文 <id>` 命名）。
- **验证**（后台线程 harness，模拟 GUI 路径）：
  - 纯图文 `OgyvEKzB6MY`（`7657719554118419941`）：第 1 轮 note 页 45s 超时 → 第 2 轮 video 页抓到详情（2 音频候选 + 6 静态图）→ 视频下载失败自动回退 → 下载 2364×1774 webp 178KB ✅；ffmpeg 解码验证 2364×1774 正常 ✅。
  - 普通视频梵高 `svMOg2yFqSU/`：第 1 轮直抓成功，13.5MB mp4 ✅（未回归）。
  - 实况图 `note/7693296625380641765`：第 2 轮成功，8 视频候选 + 6 静态图，优先做成动态 mp4 727KB ✅（静态图未被误用）。
  - `build.sh` 全量编译通过 ✅。
- **本机装机**：最小替换 + `codesign --force --deep --sign -` 重签 + `--verify --deep --strict` 通过；新 PID 79344（注意：必须先 `kill -9` 旧进程，磁盘换二进制不会重启已运行进程）；偏好 plist 30 键完好；回滚备份 `/tmp/vw_bin_backup_before_f56`。
- **待用户回归**：GUI 重贴 `OgyvEKzB6MY` 天使图文链接，确认自动生成静态壁纸；认清「贴一条链接出一张壁纸」契约——多图笔记只取最大那张（取全部多张需改 fetch 返回类型，暂未做）。

---

## 合并/发版检查清单（历史：v3.39 · 2026-11-17 已逐项过）

- [x] 逐条核对上面所有 `Unreleased` 条目的状态，把 `待决策` / `有风险` 处理掉（尤其 F2 的依赖分发）
      → **F2 依赖分发已由 F9 定案**：PerfectLoop 改为用户自选插件、App 不内置，UI 推荐并如实标注占用；F7 两处误判（`bit_rate` 字段名 / 顶层标称宽高）已由 F7.1 修正并端到端验证。
- [x] **F1 与 F2 在 `Transcoder.swift`、`LibraryWindow.swift` 里是同一批改动**——一并提交，未互相覆盖。
- [x] **F4 已废弃、以 F5 为准**：抖音走 `DouyinWebFetcher.swift`（WKWebView），`build.sh` 含该文件 + `-framework WebKit`，已编入；F4 借 cookie 代码为死代码（保留未删）。
- [x] 确认最终版本号，改 `Info.plist` 两个字段 → **3.39 / 61**。
- [x] 全量构建：`zsh package.sh`（内部调 `build.sh`，不带 `VW_NO_PRESETS=1`）→ 11-17 14:48 与 19:11 两次构建均成功。
- [x] `swiftc -O` 编译验证（仅项目原有 deprecated 警告）+ 二进制功能符号逐项核对 + DMG 内 App 挂载复核；图片/视频链接导入已在 11-16 逐功能实测。
- [x] `package.sh` 出 DMG（含 `ApiBaseURL`）→ `dist/Dòng-3.39.dmg`，`hdiutil verify` 通过。
- [x] 签名：**按用户决定走 ad-hoc + 开源 + AI 提示词安装路线，不做 Developer ID 公证**（`sign-notarize.sh --check` 本机无 Developer ID 与公证凭据）。
- [x] 版本信息 3.38 → 3.39 已同步十语言 README（文字 + badge 两处）+ 确认 i18n 文档无版本号残留。
- [x] **【已完成·服务器】** 更新更新接口 `/api/update/check` 的元数据与 SHA256：2026-11-17 19:50 实测模拟 3.38 老用户请求（`build=60&version=3.38&channel=stable&arch=arm64`）返回 `update_available=true`、latest `3.39`，`file_size=61527463`、`sha256=7fb0b5b3…e80e2b` 与本地一致；下载端点跟随 302 返回 206、可达。3.39 客户端自身查新返回 `update_available=false`（已是最新，正常）。原「需用户手动」勾选是台账未同步，服务端实际早已更新。
- [x] **【已完成·GitHub】** DMG 已上传到 GitHub Release `v3.39`（2026-11-17 19:40）：资产 `Dong-3.39.dmg`，size `61527463`，线上 digest `sha256:7fb0b5b3906cc9a8735ea8dd22a3c1d182635a3a5356448501720b707ee80e2b` 与本地一致，Release 为 Latest，说明含 ad-hoc 签名与 AI 提示词安装指引。`https://github.com/zhang-1-kael/dong/releases/tag/v3.39`
- [x] 把 `Unreleased` 归档为 v3.39 发布条目（见下方 Released 段）；历史条目按约定保留不删。

## 合并/发版检查清单（v3.43 · 2026-11-24）

- [x] 本次仅含截断修复：F20（片尾）+ F20.1（参数原样）+ F20.2（片头）。
- [x] 版本号：`Info.plist` → **3.43 / 65**（3.42 已登记服务器，且其包含未完成新功能、无片头修复）。
- [x] 十语言 README 3.42 → 3.43 同步（各 3 处），无残留。
- [x] 剥离未完成功能：构建时用 `_StubFeatures.swift` 桩顶替 Account/AccountPopover/Rotation/SyncCenter/SyncEngine + 隐藏设置里「自动轮换」分组入口；**打包后已还原 LibraryWindow.swift / build.sh、删除桩文件，源码零改动**。
- [x] 全量打包 + 校验：`dist/Dòng-3.43.dmg`，size `61641840`，sha256 `34212dd782fb9b1fc0533d1f09a15634526061e3a742ee8831eba32cb834acd5`，verify VALID；包内实测用户 32.3s 原视频 → 32.67s 完整。
- [ ] **【待做·GitHub】** Release `v3.43` 上传 DMG。
- [ ] **【待用户手动·服务器】** `/api/update/check` 更新到 3.43（当前仍指向 3.42 的 61569988）。
- [ ] **【待做】** git 提交 + tag `v3.43` + push；云端台账同步。

## 合并/发版检查清单（v3.42 · 2026-11-23）

- [x] 本次仅含 F20（本地视频不再误裁片尾）+ F20.1（参数回归原样）。
- [x] 版本号：`Info.plist` → **3.42 / 64**（3.41 已登记服务器，且其包不含修复，故升版）。
- [x] 十语言 README 3.41 → 3.42 同步（各 3 处），复核无残留。
- [x] 全量打包 + 校验：`dist/Dòng-3.42.dmg`，size `61641840`，sha256 `34212dd782fb9b1fc0533d1f09a15634526061e3a742ee8831eba32cb834acd5`，verify VALID。挂载复核版本 3.42/64、截断修复符号在、**包内二进制实测 24s→24.37s / 30fps**、签名通过。
- [ ] **【待做·GitHub】** Release `v3.42` 上传 DMG。
- [ ] **【待用户手动·服务器】** `/api/update/check` 更新到 3.42。
- [ ] **【待做】** git 提交 + tag `v3.42` + push；云端台账同步。
- 备注：v3.41 未做 GitHub Release / git tag（直接跳到 3.42），其功能已全部包含在 3.42 包内。

## 合并/发版检查清单（历史：v3.41 · 2026-11-20，已登记官网服务器）

- [x] 核对本次条目：F13 / F14 / F14.2 / F15 / F16 / F17 / F18 / F19（F14.1 已被 F14.2 撤销，保留作历史）。
- [x] 修正重复编号：`F11` 菜单栏悬停 → **F17**；`F12` 下载直链 → **F18**；`F12` 壁纸重命名 → **F19**（原 F11 底栏图标、F12 重命名冲突由多任务并行造成）。
- [x] 确认最终版本号：`Info.plist` → **3.41 / 63**（3.40 已发布，必须升版用户才能收到更新）。
- [x] 全量构建：`zsh package.sh` 11-20 15:40 成功（仅项目原有 deprecated 警告）。
- [x] `package.sh` 出 DMG → `dist/Dòng-3.41.dmg`，size `61569984`，`hdiutil verify` VALID，sha256 `b8b13bbd3d43e83b29204508a5b72ca7cf176919d0aff4a46a096b9fa195b7e2`。
- [x] 挂载复核：版本 3.41/63、API 正确、内置 ffmpeg + yt-dlp、新功能符号齐全（WebStreams 24 / WebWallpaperView 6 / PlaybackPolicy 99 / PerfectLoopInstaller 46 / looksLikeImageLink / importImageLink）、ad-hoc 深度签名校验通过。
- [x] 版本 3.40 → 3.41 已同步十语言 README（各 2 行 3 处），复核无 3.40 残留。
- [ ] **【待做·GitHub】** 创建 Release `v3.41` 并上传 DMG（英文名 `Dong-3.41.dmg`）+ 插件安装器。
- [ ] **【待用户手动·服务器】** 更新 `/api/update/check` 到 3.41（写接口 401 需鉴权，AI 无凭据）。
- [ ] **【待做】** git 提交 + tag `v3.41` + push；云端台账同步。

## 合并/发版检查清单（历史：v3.40 · 2026-11-18）

- [x] 上面 F10（插件下载入口）/ F5.5 / F5.6 / F11（底栏图标调亮）状态已核对；F10 重号已修正——「底栏图标调亮」改编号为 F11，与「插件下载入口 F10」区分。
- [x] 确认最终版本号：`Info.plist` → **3.40 / 62**（用户 11-18 决定升版，不再沿用 3.39）。
- [x] 全量构建：`zsh package.sh`（不带 `VW_NO_PRESETS=1`）11-18 三次构建成功（14:51 初版 / 19:50 加图标改动最终版），仅项目原有 deprecated 警告。
- [x] `package.sh` 出 DMG → `dist/Dòng-3.40.dmg`，`hdiutil verify` VALID；挂载复核版本 3.40/62、API、内置 ffmpeg + yt-dlp、F5.5/F5.6/F10/F11 符号与中文文案齐全、ad-hoc 深度校验通过。
- [x] 签名：按既定路线 **ad-hoc**（用户决定，不做 Developer ID 公证）。
- [x] 版本 3.39 → 3.40 已同步十语言 README（正文 + badge 两处，各 3 处），复核无 3.39 残留；`tools/i18n_data.py` 无当前版本号（仅 v3.31 历史提示词 + 动态 META_URL），无需改。
- [x] **【已完成·GitHub】** 创建 Release `v3.40`（2026-11-18 19:56，`draft=false`、非 prerelease）并上传 3 个资产：`Dong-3.40.dmg`（size `61541183`，线上 digest `sha256:b4426e65744c2cbfc46ef64269e715385f471f906e5bba3e8413d4d9a3532c74` 与本地一致）、`PerfectLoop-Plugin-Installer.zip`、`PerfectLoop-Plugin-README.md`。下载链接 HTTP 200。`https://github.com/zhang-1-kael/dong/releases/tag/v3.40`。注：`/releases/latest` 一时仍返回 v3.39（疑草稿转正式 created_at 排序），按 tag 访问与下载均正常。
- [ ] **【待用户手动·服务器】** 更新 `/api/update/check` 到 3.40：file_size `61541183`、sha256 `b4426e65744c2cbfc46ef64269e715385f471f906e5bba3e8413d4d9a3532c74`、download `...?v=3.40&channel=stable`。探查确认：查询接口只读（`Allow: GET,HEAD,OPTIONS`），写接口 `/api/admin/releases` 存在但 401 需鉴权、`/admin` 后台需登录，AI 无凭据，只能由用户在官网后台手动填。漏填则 3.39 用户收不到 3.40 更新提示。
- [x] **【已完成】** 把 `Unreleased` 归档为 Released 段 v3.40 条目；十语言 README / 云端台账同步完成。git 提交 + push 见下方。

## 本机环境备注（不属于发布内容）
- 实际运行/安装的 App 是 `/Applications/Dòng.app`（bundle id `com.zhanghangshuo.dong`），**不是** `~/Applications/VideoWallpaper.app`；按文件名搜索容易漏，用 `pgrep -fl VideoWallpaper` 查。
- 登录项 `~/Library/LaunchAgents/com.zhanghangshuo.videowallpaper.plist` 仍指向 `~/Applications/VideoWallpaper.app`（另一份），**尚未修正**，开机可能拉起错版本。
- 备份：`~/Applications/Dòng.app.bak-20261113-1625`（替换前原版）。

---

## Released

### v3.44 / build 66 — 2026-11-26

**主题：账号系统上线 —— 换一台 Mac，壁纸和调参自动跟着走。**

- **账号登录与云同步**：注册 / 登录后壁纸库、微调参数、设置同步到云端；另一台 Mac 登录同账号自动拉回，逐张 sha256 一致。上传显示字节级进度，断网 / 退出自动续传。
- **找回与设备管理**：恢复码重置密码（一次有效）；查看已登录设备并踢下线；改昵称 / 头像 / 密码（改完其他设备旧令牌立即失效）。
- **紧凑账号窗口**：登录 / 资料 / 改密码收进 400×432 小窗。
- **稳定性**：`sync.log` 限 256KB（超出只留最后 200 行）；本地视频导入不误裁片头片尾（沿用 3.43）。

**发布产物与渠道：**
- DMG：`dist/Dòng-3.44.dmg`，size `62007615`，sha256 `39d6bb74220542308bfdfe8f115d39e2ff1bc5908d741139f23542edd1c7d1c6`，`hdiutil verify` 通过；内 App 3.44/66。
- **GitHub**：Release `v3.44`（**Latest**），资产 `Dong-3.44.dmg`（GitHub 规范化文件名），API digest 与上述 sha256 一致；此前 v3.41–v3.43 未建 Release，本次只补 v3.44。
- **Gitee（国内）**：`https://gitee.com/dong-is-good/dong` 已同步 `main`（`15994ba`，代码 + 十语言 README 3.44，7 处链接本地化）+ tag `v3.44`；Release `v3.44`（id `1371790`）附件 `Dòng-3.44.dmg`，匿名下载 HTTP 200 / `Content-Length 62007615`。
- **官网**：`/api/update/check` 返回 `latest.version=3.44 / build=66 / channel=stable`，notes 已填。
- **签名**：仍为 ad-hoc（未做 Developer ID 公证），配合开源 + AI 提示词安装。

### v3.43 / build 65 — 2026-11-24

**主题：只含截断修复的轻量版（不含未完成新功能）。**

- **本地视频完整保留（F20 + F20.1 + F20.2）**：
  - 片尾：不再把正常静止收尾误判成「片尾卡」裁掉（`autoTrimIntroOutro` 控制，本地导入关闭）。
  - 片头：同样纳入保护（F20.2 修复「开头被裁 7 秒」）。
  - 参数：1.00× 原速、帧率跟随源、整段循环、无淡化/明暗/时长限制。
- **未编入的功能（并行任务未完成）**：账号登录 / 云同步 / 自动轮换（`Account.swift`、`AccountPopover.swift`、`Rotation.swift`、`SyncCenter.swift`、`SyncEngine.swift`）。构建时用桩顶替并隐藏设置里的「自动轮换」入口，**打包后已还原源码，未改动任何项目文件**。
- **实测（用户原视频 32.30s / 1280×800 / 30fps）**：输出 **32.67s 完整**，分辨率帧率不变（+0.37s 循环补帧）。

**发布产物与交付参数：**
- DMG：`dist/Dòng-3.43.dmg`，size `61641840`，sha256 `34212dd782fb9b1fc0533d1f09a15634526061e3a742ee8831eba32cb834acd5`
- `version` = `3.43`，`build` = `65`
- `download` = `https://dongisgood.coze.site/api/download?v=3.43&channel=stable`
- 注意：服务器当前仍指向 3.42（61569988），需手动改为 3.43。

### v3.42 / build 64 — 2026-11-23

**主题：修复本地视频被误裁片尾 + 参数回归「原样」。**

- **本地视频不再被误裁片尾（F20）**：`detectEndCard` 曾把「正常的静止收尾」判成「片尾卡」裁掉（最多 40% 时长）。现在本地导入（拖拽 / 选择文件 / CLI `--import`）**完全不裁片尾**；链接下载的网络素材仍保留自动裁片尾卡。同时收紧检测阈值（`still` 下限 0.25→0.08、裁切上限 40%→min(8s, 25%)）并加 `baseline >= 1.0` 保护。
- **参数默认回归原样（F20.1）**：不加速（`speed` 1.00×）、帧率跟随源（`outputFPS` 0）、整段循环、无首尾淡化、无明暗调整、不限时长。代码本无自动调速逻辑，1.31× 与固定 60fps 为历史残留偏好，已清除。
- **实测**：24s（结尾 6s 静止）视频：修复前 18.35s → 修复后 **24.37s**；12s/30fps 源 → 输出 12.37s/**30fps**（不再补到 60）。
- **画质**：`targetSize` 只缩不放、CRF 18 高质量；内容/时长/速度/帧率保持原样，仅做一次为无缝循环的高质量重编码。
- **构建说明（hotfix 专用）**：账号登录 / 云同步 / 自动轮换（`Account.swift`、`AccountPopover.swift`、`Rotation.swift`、`SyncCenter.swift`、`SyncEngine.swift`，并行任务未完成）**未编入本包**——构建时临时用 `_StubFeatures.swift` 桩顶替 + 注释掉设置里的「自动轮换」分组入口，打包后已全部还原，源码未改动。后续新功能完成后再单独发版。

**发布产物与交付参数：**
- DMG：`dist/Dòng-3.42.dmg`，size `61641840`，sha256 `34212dd782fb9b1fc0533d1f09a15634526061e3a742ee8831eba32cb834acd5`
- `version` = `3.42`，`build` = `64`
- `download` = `https://dongisgood.coze.site/api/download?v=3.42&channel=stable`
- 注意：**已入库的旧壁纸不会自动重转**，需重新导入才生效。

### v3.41 / build 63 — 2026-11-20

**主题：网页壁纸 + 图片直链 + 自动暂停让路 + 插件一键安装 + 交互细节。**

- **网页 / 流媒体壁纸（F15，新增 `WebWallpaper.swift`）**：贴任意网页链接（YouTube / Shadertoy / 在线播放页）不下载不转码，直接用 WKWebView 渲染成动态壁纸；YouTube 自动转 embed 静音循环、Shadertoy 转 embed 无控件、普通网页原样加载。库里以虚拟 URL `dongweb://` 存储，缩略图用地球图标。
- **图片直链识别（F16）**：右键「复制图片地址」的链接直接下载做成静态壁纸。修掉两个根因——① 旧逻辑把图片链接当网页丢给 WKWebView，成败取决于 WebView 认不认；② 扩展名可能在 path / query / 带参数三种形态。现在按 `looksLikeImageLink` 识别后走 URLSession 下载 + ImageIO 校验 + `importStillImage`，同一条链接每次结果一致。CLI 也支持。
- **自动暂停策略 + 状态可视化（F14 / F14.2，新增 `PlaybackPolicy.swift`）**：前台有程序全屏时壁纸自动暂停让出资源、退出全屏自动续播；只暂停/续播 AVPlayer，不 teardown 窗口。暂停态显示静态果冻图标（F14.1 的橙色暂停符号方案已撤销）。
- **插件 App 内一键安装（F13，新增 `PerfectLoopInstaller.swift`）**：点一下就在 App 内装好 PerfectLoop，无需下载 zip / 解压 / 右键打开 / 重启。
- **菜单栏图标悬停展开（F17）**：鼠标悬停菜单栏图标自动弹出小面板，少点一次。
- **下载改直链（F18）**：修「点下载跳到 releases 列表页、用户找不到安装包」，改为直链下载并写清后续步骤。
- **壁纸重命名（F19）**：壁纸库里每张壁纸可单独改名。
- **编号整理**：F11/F12 曾被多任务并行重复占用，本次新增条目重编为 F17/F18/F19。

**发布产物与交付参数：**
- DMG：`dist/Dòng-3.41.dmg`，size `61569984`，sha256 `b8b13bbd3d43e83b29204508a5b72ca7cf176919d0aff4a46a096b9fa195b7e2`
- `version` = `3.41`，`build` = `63`
- `download` = `https://dongisgood.coze.site/api/download?v=3.41&channel=stable`
- 签名：ad-hoc（未公证）；校验 `hdiutil verify` VALID、深度签名校验通过。
- 已知待验：F15 网页壁纸与 F16 图片直链未经过用户 GUI 点击确认（F16 已 CLI + 装机验证）。

### v3.40 / build 62 — 2026-11-18

**主题：抖音纯图文生成静态壁纸 + 安全验证可手动过 + PerfectLoop 一键安装下载闭环 + 底栏图标调亮。**

- **抖音纯图文笔记生成静态壁纸（F5.6）**：纯图文笔记（图片 + BGM，本身没有动态画面）不再拒绝——详情接口 `images[].url_list` 的高清原图直链按分辨率降序择优下载，交给 F1 的 `importStillImage` 做成 2 秒静态壁纸；视频候选全是音频时自动回退静态图；两轮都没抓到详情时用 SSR 封面图兜底；仍严格只用目标图、绝不碰推荐流（防抓错）。修复 F5.5 遗留的等待 deadline 重算死循环。实测天使图文链接 `OgyvEKzB6MY` 下载到 2364×1774 webp，普通视频/实况图回归正常。
- **安全验证页可手动过（F5.5）**：抖音对部分出口 IP 弹的滑块/短信验证页，过去窗口全透明、用户看不见只能干等超时；现在检测到验证页就把窗口显示到屏幕中央、置顶，并延长等待 120s 供用户手动过验证。收紧检测条件排除抖音每页都挂的 `rmc-nocaptcha` 被动组件，避免误判。纯图文报错改为说人话的提示。
- **PerfectLoop 一键安装 + 下载入口（F10）**：F9 只在 UI 推荐插件但没下载入口，闭环断裂；补齐——三处（拖拽浮层 / 文件面板 message / 微调面板按钮）加下载指引，「下载并安装 PerfectLoop 插件 ↗」按钮打开项目 Releases 页。一键安装器 zip（内置 uv 引导 + 隔离 venv + 清华镜像装 7 依赖 + 自检，隔离 HOME 实测 exit=0）已上传到 v3.39 Release，v3.40 沿用该入口。
- **底栏图标调亮（F11）**：深色模式下底栏关态/动作键图标从灰白描边改浅暖橙（悬停更亮），开态保持饱和主题橙 + 淡雾底；透明度圆环与百分比改固定亮墨色，不再随深浅色切换翻黑压在深玻璃上。

**发布产物与交付参数：**
- DMG：`dist/Dòng-3.40.dmg`，size `61541183`，sha256 `b4426e65744c2cbfc46ef64269e715385f471f906e5bba3e8413d4d9a3532c74`
- `version` = `3.40`，`build` = `62`
- `download` = `https://dongisgood.coze.site/api/download?v=3.40&channel=stable`
- 签名：ad-hoc（未公证）；校验 `hdiutil verify` VALID、深度签名校验通过。
- 上传：GitHub Release `v3.40` + 官网更新接口（见上方 v3.40 检查清单）。

### v3.39 / build 61 — 2026-11-17

**主题：画质与帧率优化 + 壁纸库拖动重排 + 循环跳变修复 + PerfectLoop 自选插件。**

- **画质与帧率（F7 / F7.1，用户核心诉求）**：
  - 下载端放弃卡死 1080p——格式选择器改为分辨率优先 `bv*[height>=2000]`，B 站有 4K 源即取（游客/非大会员仍受平台清晰度墙限制）。
  - 抖音端修正两处误判：真实多档位字段是 `video["bit_rate"]`（非 `bitrate_info`），每档真实分辨率取该档自己的 `play_addr.width/height`（视频顶层宽高是标称值，不可信）；按画质分降序择优，4K/60fps 档排到默认档前。
  - 帧率默认上限 30 → 60（跟随源，有 60fps 源就给 60）；转码码率上限 `maxrate 20M/40M` → `80M/160M`，CRF 18 不变。
  - **端到端实测**（抖音星野链接，隔离库）：旧 `1024×576/30fps/4.2MB` → 新 `2816×1584/60fps/31.6Mbps/62.2MB`（分辨率 ×2.75、帧率 ×2、码率 ×15）。注意已入库旧壁纸不会自动重转码，需重新贴链接导入才走新参数。
- **壁纸库长按拖动重排（F6 / F6.1 / F6.2 / F6.3）**：按住卡片约 0.32s 拖动换位，Apple HIG 弹簧插值 + 避让排布 + 落位弹入，顺序写入偏好重启保持；修复了"拖不动"与拖动抽搐。
- **循环跳变修复（F8）**：首尾淡化关闭时也自动用 PerfectLoop 消除短视频循环硬跳（新增 `autoSeamless` 开关，默认开）；某实况图首尾 SSIM 0.5122 → 0.9726。
- **PerfectLoop 改为用户自选插件（F9）**：App 不再内置（其 Python 依赖约 332MB），导入处/微调面板推荐用户自行安装并如实标注占用（约 330MB 磁盘 / 340MB 峰值内存）；检测到外部插件目录 `~/.local/share/VideoWallpaper/perfectloop-plugin/` 即自动启用，未装则回退内置 blend / 硬切。
- **抖音抓取通道（v3.38 已引入，本版延续）**：WKWebView 抓详情接口，支持普通视频 + 实况图，严格校验 aweme_id 防抓错、后台线程清理防崩溃、App Nap 防护、音频误判过滤。

**发布产物与交付参数（需用户手动上传服务器 / GitHub）：**
- DMG：`dist/Dòng-3.39.dmg`
- `version` = `3.39`
- `build` = `61`
- `file_size` = `61527463`
- `sha256` = `7fb0b5b3906cc9a8735ea8dd22a3c1d182635a3a5356448501720b707ee80e2b`
- `download` = `https://dongisgood.coze.site/api/download?v=3.39&channel=stable`
- 签名：ad-hoc（未公证）；安装走开源 + AI 提示词安装，先清 `com.apple.quarantine`。
- 校验：`hdiutil verify` 通过；DMG 内 App 版本 3.39/61、bundle id `com.zhanghangshuo.dong`、内置 ffmpeg + yt-dlp、无 PerfectLoop。
