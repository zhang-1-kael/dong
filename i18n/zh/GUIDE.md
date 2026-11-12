# Dòng — 技术与项目文档

> 本项目的其它说明，全部使用简体中文。

## 架构

四条独立流水线：桌面层窗口与 `AVPlayerLayer`、yt-dlp + ffmpeg 转码、纯 AppKit 手绘的菜单栏面板与壁纸库、LaunchAgent 自启 / 目录监听 / 匿名统计。

## 关键实现

- 窗口比屏幕大 24 pt，遮住圆角与切换桌面时露出的边。
- `--deep` 签名会破坏嵌套资源签名，不能用。
- 循环音频要分三段 seek 混音，一遍过会留下爆音。
- 菜单栏面板全部手绘，用来盖住系统毛玻璃。

## 命令行调试

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

调试环境变量（`VW_PANEL_SHOT`、`VW_GEOM`、`VW_DUMP_MENU` 等）见中文原文第 9 节。

## 许可与商业授权

代码与文档采用 **GPL-3.0**，具法律效力的全文是英文 [LICENSE](../../LICENSE)。闭源商用需另行申请商业授权：[COMMERCIAL.md](../../COMMERCIAL.md)。

## 品牌与素材

名称「Dòng」、`AppIcon.icns`、`BrandMark*.png` 属于品牌标识。`presets/`、`bili/` 里的壁纸视频以及 ffmpeg / yt-dlp 二进制都不在本仓库中。

## 贡献与 AI 政策

欢迎 issue 与 PR，模板在 `.github/`，CI 会自动构建。AI 辅助贡献需披露并逐行复核，见 [AI_POLICY.md](../../AI_POLICY.md)。

## 隐私

匿名统计默认开启，可在设置里一键关闭。如果你 fork 本项目，请把 `Analytics.swift` 中 `isEnabled` 的默认值改成 `false`。

完整中文原文：[技术原理.md](../../技术原理.md)。

---

## 更多中文文档

- [README.zh.md](../../README.zh.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
