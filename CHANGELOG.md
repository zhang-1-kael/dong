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

---

## 合并/发版检查清单（v3.39 · 2026-11-17 已逐项过）

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
- [ ] **【需用户手动·服务器】** 更新更新接口 `/api/update/check?version=…&channel=stable` 的元数据与 SHA256（交付参数见下方 Released 条目）。
- [ ] **【需用户手动·GitHub】** 把 DMG 上传到 GitHub Release `v3.39`（ad-hoc 包，配 AI 提示词安装说明）。
- [x] 把 `Unreleased` 归档为 v3.39 发布条目（见下方 Released 段）；历史条目按约定保留不删。

## 本机环境备注（不属于发布内容）
- 实际运行/安装的 App 是 `/Applications/Dòng.app`（bundle id `com.zhanghangshuo.dong`），**不是** `~/Applications/VideoWallpaper.app`；按文件名搜索容易漏，用 `pgrep -fl VideoWallpaper` 查。
- 登录项 `~/Library/LaunchAgents/com.zhanghangshuo.videowallpaper.plist` 仍指向 `~/Applications/VideoWallpaper.app`（另一份），**尚未修正**，开机可能拉起错版本。
- 备份：`~/Applications/Dòng.app.bak-20261113-1625`（替换前原版）。

---

## Released

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
