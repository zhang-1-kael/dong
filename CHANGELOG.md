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

---

## Unreleased（合成下一个版本统一发布）

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

---

## 合并/发版检查清单（统一发布时逐项过）

- [ ] 逐条核对上面所有 `Unreleased` 条目的状态，把 `待决策` / `有风险` 处理掉（尤其 F2 的依赖分发）
- [ ] **F1 与 F2 在 `Transcoder.swift`、`LibraryWindow.swift` 里是同一批未提交改动**——合并或回滚时别互相覆盖
- [ ] **F4 已废弃、以 F5 为准**：抖音通道改走 `DouyinWebFetcher.swift`（WKWebView），`build.sh` 已加该文件 + `-framework WebKit`，别漏编译；F4 的借 cookie 代码是死代码，可择机清理
- [ ] 确认最终版本号，改 `Info.plist` 两个字段（当前源码 3.38 / 60）
- [ ] 全量构建：`zsh build.sh`（**不要带 `VW_NO_PRESETS=1`**，正式版要内置壁纸）
- [ ] `swiftc -O` 编译验证 + 图片导入/拖放 + 视频链接导入实测
- [ ] `package.sh` 出 DMG（要求 `Info.plist` 含 `ApiBaseURL`）
- [ ] `sign-notarize.sh` 做 Developer ID 签名与公证（本机目前仅 ad-hoc）
- [ ] 版本信息变动时同步多语言 README（`AGENTS.md` 约定）+ i18n 生成脚本
- [ ] 更新更新接口 `/api/update/check?version=…&channel=stable` 的元数据与 SHA256
- [ ] 把 `Unreleased` 归档成带版本号的发布条目，清空 `Unreleased` 重新开始

## 本机环境备注（不属于发布内容）
- 实际运行/安装的 App 是 `/Applications/Dòng.app`（bundle id `com.zhanghangshuo.dong`），**不是** `~/Applications/VideoWallpaper.app`；按文件名搜索容易漏，用 `pgrep -fl VideoWallpaper` 查。
- 登录项 `~/Library/LaunchAgents/com.zhanghangshuo.videowallpaper.plist` 仍指向 `~/Applications/VideoWallpaper.app`（另一份），**尚未修正**，开机可能拉起错版本。
- 备份：`~/Applications/Dòng.app.bak-20261113-1625`（替换前原版）。

---

## Released
（暂无）
