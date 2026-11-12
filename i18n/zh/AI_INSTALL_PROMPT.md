# 让 AI 帮你安装 Dòng

整段复制，粘贴给能操作你电脑的 AI 助手，安装就交给它了。

> [!TIP]
> 下面这段提示词刻意用英文写，这样任何 AI 工具都能读懂；最后一句已经要求它用简体中文回复你，所以你看到的仍然是中文。

## ① 推荐：通用提示词（所有 AI 工具都能识别）

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in Simplified Chinese.
```

整段复制粘贴给 AI。它会下载官方安装包、核对 SHA256、装进「应用程序」，并完成 macOS 首次打开的一次性确认。应用自己弹的首次运行选项留给你点。

## ② 备选：中文提示词

```text
请帮我在这台 Mac 上安装 Dòng（macOS 动态壁纸 App）。

官方仓库：https://github.com/zhang-1-kael/dong
官网：https://dongisgood.coze.site/en
给 AI 的安装手册：仓库里的 AI_INSTALL.md；一键安装脚本：install.sh

请先读手册和脚本，再按手册执行：从官网稳定入口下载安装包、用官方接口给的 SHA256 校验、装进「应用程序」、完成 macOS 首次打开的确认、启动后告诉我结果和用法。
只用上述官方域名；不要 sudo、不要删除或覆盖我的文件、不要改动系统级安全设置；如果你没有终端权限，就直接给我最短的可复制命令，不要假装已经装好。
```

如果你的 AI 助手更习惯中文，也可以用这一段。

## ③ 只想自己敲三行命令

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

加上 --dry-run 只预演：仅打印打算做的事，不下载、不改动系统。

---

## 更多中文文档

- [README.zh.md](../../README.zh.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
