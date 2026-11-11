<div align="center">
  <img width="225" height="225" src="assets/brandmark-sway.gif" alt="Dòng">
  <h1><b>Dòng</b></h1>
  <p>把任何视频，变成会动的桌面。<br>
  <a href="#features"><strong>探索 Dòng »</strong></a><br><br>
  <a href="#installation">下载 for macOS</a> · <a href="https://dongisgood.coze.site/en">访问官网 ↗</a><br>
  <i>~ 版本 3.31 · macOS 13 及更高版本 · Apple Silicon ~</i></p>
  <p>
    <a href="README.en.md">English</a> · <b>简体中文</b> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a><br>
    <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.ru.md">Русский</a>
  </p>
</div>

> [!NOTE]
>
> Dòng 是一个完全用 Swift 和 AppKit 写的 macOS 动态壁纸工具 —— 约 8,500 行代码，零第三方框架，
> 没有 Electron、没有 SwiftUI、没有一颗 Pod。
> 贴一条视频链接，或拖进一个本地视频，它会自动下载、裁剪、拼接成无缝循环，铺在你的桌面上。

<h6 align="center">
  <a href="https://github.com/zhang-1-kael/dong/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-5865F2?style=for-the-badge&labelColor=23272A" alt="MIT License"></a>
  <a href="https://github.com/zhang-1-kael/dong/releases"><img src="https://img.shields.io/badge/version-3.31-57F287?style=for-the-badge&labelColor=23272A" alt="Version 3.31"></a>
  <a href="https://github.com/zhang-1-kael/dong"><img src="https://img.shields.io/badge/macOS-13%2B-23272A?style=for-the-badge&labelColor=23272A&logo=apple&logoColor=white" alt="macOS 13+"></a>
  <a href="https://github.com/zhang-1-kael/dong"><img src="https://img.shields.io/badge/Swift-F05138?style=for-the-badge&labelColor=23272A&logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://github.com/zhang-1-kael/dong/stargazers"><img src="https://img.shields.io/github/stars/zhang-1-kael/dong?style=for-the-badge&label=Stars&color=FEE75C&labelColor=23272A" alt="Stars"></a>
  <a href="https://github.com/zhang-1-kael/dong/issues"><img src="https://img.shields.io/github/issues/zhang-1-kael/dong?style=for-the-badge&label=Issues&color=ED4245&labelColor=23272A" alt="Issues"></a>
</h6>

## Features

### 🖥 桌面级动态壁纸

在 WindowServer 的桌面层上挂一扇无边框窗口，用 `AVPlayerLayer` 循环播放。
不改系统壁纸、不装内核扩展、不需要管理员权限。每块屏幕独立窗口、独立播放器，插拔显示器自动重建。

### 🔗 链接即壁纸

贴一条 B 站 / YouTube 链接，下载 → 转码 → 调优 → 入库全自动。
抖音链接受平台反爬限制（详见[已知限制](#已知限制)），请先把视频保存到本地再拖进来。

### ✂️ 自动剪成无缝循环

用 ffmpeg 把画面「运动量」算成一维信号，在信号上找突变，判断哪里是正片；
按白度、长宽比、边缘密度定位平台水印，用 `delogo` 插值填补；
片尾与片头做 0.4 秒交叉淡化，循环点彻底消失。

<p align="center">
  <img src="docs/pipeline.svg" width="700" alt="导入流水线">
</p>

### 🎛 菜单栏玻璃面板

一个常驻菜单栏的 App：当前壁纸、磁盘占用、在线时长，粘贴链接即导入，全部控件 AppKit 自绘。

<p align="center">
  <img src="assets/panel.jpg" width="620" alt="Dòng 菜单栏面板">
</p>

### 📚 瀑布流壁纸库

按封面网格铺开全部壁纸，悬停即预览，点击切换。音量、播放控制、当前帧信息一屏搞定。

<p align="center">
  <img src="assets/library-wide.jpg" width="720" alt="Dòng 壁纸库">
</p>

### 🔒 锁屏同款画面

抽一帧视频设为系统壁纸 —— 解锁时是动的，锁屏时是同一张静帧。

---

## Usage

### Installation

#### 下载 Dòng

前往 [Releases](https://github.com/zhang-1-kael/dong/releases) 页面下载最新的 `.dmg`，打开后把 Dòng 拖进「应用程序」即可。

> [!TIP]
> 首个正式版本正在打包中。在它发布之前，你可以按下方步骤从源码构建一份 —— 只需要 Xcode 命令行工具，一分钟装好。

#### 从源码构建

**依赖只有 Xcode 命令行工具**，不需要 Xcode 本体：

```bash
xcode-select --install   # 如果已经装过就跳过
```

克隆后直接编译：

```bash
git clone https://github.com/zhang-1-kael/dong.git
cd dong
./build.sh
open build/VideoWallpaper.app
```

`build.sh` 用一行 `swiftc` 把 10 个 `.swift` 文件编成一个可执行文件，再组装成 `.app`。
编译产物是 **ad-hoc 签名**，只能在你自己机器上跑；要分发给别人得走 `sign-notarize.sh`。

##### 可选组件

下面两个都不是编译必需的，缺了只影响对应功能：

| 组件 | 作用 | 装法 |
|---|---|---|
| **ffmpeg** | 转码、剪片头片尾、去水印、做循环 | `brew install ffmpeg`，或放到 `~/.local/bin/ffmpeg` |
| **yt-dlp** | 粘贴链接下载 | `brew install yt-dlp`，或放可执行文件到 `vendor/yt-dlp_macos` |

`build.sh` 会自动把找到的 ffmpeg / yt-dlp 塞进 App 包里，这样拷给别人也能用。

> ⚠️ 本仓库**不包含**这两个二进制，也不包含内置壁纸素材 —— 见下方[许可与素材](#许可与素材)。

##### 打包成 DMG

```bash
./package.sh                    # → dist/Dòng-<版本>.dmg
VW_NO_PRESETS=1 ./package.sh    # 不带内置壁纸，DMG 小 360 MB
```

### 导入一条壁纸

1. 点菜单栏里的 Dòng 图标，打开面板；
2. 把 B 站 / YouTube 链接粘进输入框（一整段分享文案也没关系，程序会自己把链接挑出来），回车；
3. 或者直接把本地视频文件拖进壁纸库窗口；
4. 等底部胶囊跑完 —— 通常 20~60 秒，壁纸就换上去了。

---

## 架构

四条独立的流水线，围绕一个「没有窗口的菜单栏 App」：

```
┌──────────────────────────────────────────────────────────────┐
│                     菜单栏 App（LSUIElement）                 │
│                                                              │
│  ① 显示层   桌面窗口 ×N 屏  ──►  AVPlayerLayer  ──►  AVPlayerLooper│
│  ② 处理层   yt-dlp  ──►  ffmpeg 转码  ──►  壁纸库             │
│  ③ 界面层   菜单栏面板 / 壁纸库窗口（AppKit 全自绘）           │
│  ④ 系统层   LaunchAgent 自启 · 目录监听 · 匿名统计             │
└──────────────────────────────────────────────────────────────┘
```

| 文件 | 行数 | 职责 |
|---|---:|---|
| `main.swift` | 1 833 | 显示层：桌面窗口、多屏、播放器生命周期、自动更新接线 |
| `LibraryWindow.swift` | 2 631 | 壁纸库窗口，瀑布流布局 + 悬停预览 + 常驻透明度滑杆 |
| `Panel.swift` | 1 654 | 菜单栏玻璃面板、果冻徽章动画，全部自绘 |
| `Transcoder.swift` | 672 | 探测、目标尺寸、片头片尾检测、去水印、编码 |
| `Analytics.swift` | 534 | 匿名统计 + 云服务地址（可关） |
| `Updater.swift` | 515 | 自动更新：检查、下载、SHA256 校验、就地替换 |
| `Downloader.swift` | 202 | yt-dlp 封装与进度解析 |
| `FrameHealth.swift` | 320 | 卡顿看门狗与播放探针，落 diag.log |
| `LockScreen.swift` | 70 | 抽帧设为系统壁纸 |
| `Presets.swift` | 47 | 内置素材首次导入 |

**完整的技术细节在 [`技术原理.md`](技术原理.md)**：为什么窗口要比屏幕大 24pt、
为什么 `--deep` 签名有害、为什么循环混音必须分三段 seek、
为什么面板自绘会把毛玻璃盖住 —— 每个坑都有记录，包括踩坑时错在哪。

---

## 命令行调试

不想每次改算法都等整个转码跑完，内置了无头（headless）调试入口：

```bash
VideoWallpaper --detect a.mp4             # 只跑检测，0.2 秒出片头/片尾/角标判定
VideoWallpaper --try a.mp4 out.mp4        # 跑一次完整转码到指定文件
VideoWallpaper --import a.mp4 b.mp4       # 批量导入并打印处理结果
VideoWallpaper --link "https://…"         # 链接下载 + 导入
```

调试用环境变量见 `技术原理.md` 第 9 节（`VW_PANEL_SHOT`、`VW_GEOM`、`VW_DUMP_MENU` 等）。

---

## 已知限制

| 限制 | 原因 |
|---|---|
| 仅 arm64 | 编译目标与内置 ffmpeg 都是 Apple Silicon；出通用二进制要 `lipo` |
| 锁屏是静止的 | macOS 不向第三方开放锁屏视频，抽帧是唯一不越界的做法 |
| 多屏共用同一视频 | 每屏一个播放器，但取自同一个文件 |
| 更新全自动 | 检查 → 下载 → 校验 SHA256 → 退出后就地替换并重开；装不了才退回打开 dmg |
| 不接抖音链接 | 抖音启用 a_bogus 反爬，必须带登录态 cookie，匿名请求直接被拒。请先在 App 里保存到本地，再把文件拖进来 |
| 链接下载有法律边界 | 抓取第三方平台内容，请只用于自己有权的素材 |

---

## 隐私

App 内置一份匿名使用统计，**只记录**：随机生成的安装 UUID、版本号、系统版本、
CPU 架构、语言、事件名。

**不记录**：文件名、目录路径、链接内容、壁纸画面、任何可识别个人的信息。
设置里可以一键关闭，关掉后立即清空本地队列并停止所有请求。

统计数据发往作者自己的服务器（`Analytics.swift` 里硬编码的地址），且**默认开启**。
**如果你 fork 了并自己发行，请把 `Analytics.swift` 第 50 行 `isEnabled` 的默认值改成 `false`**，
否则你的用户会往作者的服务器上报 —— 这一步不体面，但必须说清楚。

---

## 许可与素材

代码与文档以 **MIT** 授权，见 [LICENSE](LICENSE)。

**不包含在授权里的部分：**

- 名称「Dòng」、`AppIcon.icns`、`BrandMark*.png` —— 品牌标识，请勿用于衍生作品的图标或名称。
- **壁纸素材**：`presets/` 与 `bili/` 已加入 `.gitignore`，仓库里没有视频文件。
  你自己打包时使用的素材，版权由你负责。
- `ffmpeg` 与 `yt-dlp` 二进制不在仓库内。注意：官方 ffmpeg 的
  `--enable-gpl --enable-nonfree` 构建**不可再分发**，对外分发应换 LGPL 构建
  并把编码器从 `libx264` 换成 `h264_videotoolbox`。

---

## About

I'm a 16-year-old high school sophomore. Dòng started as a whim — I wondered
why a wallpaper couldn't be a moving video, so I wrote one in Swift from
scratch, just for myself.

Then my classmates saw it and wanted it too. So I thought, why not build it
properly and share it. Getting from "it runs on my machine" to "it runs on
yours" meant figuring out downloads, transcoding, code signing, auto-updates —
none of which I had needed to care about before. It was a lot of reading docs
and hitting walls, one small fix at a time.

Now it's open source, and I'm sharing it with everyone. I hope you enjoy using
it — and if you run into any problems or have ideas, please open an issue.
I read every one.

---

<p align="center">
  <sub>Built with swiftc. No frameworks were harmed.</sub>
</p>
