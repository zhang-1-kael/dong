# 让 AI 帮你装 Dòng / Ask an AI to install Dòng for you

把下面任意一段整段复制，粘贴给任何 AI 助手（能执行命令的它会直接装好；
不能执行命令的它会把最短的三行命令给你）。以后安装方式变了，只需要改仓库里的
`AI_INSTALL.md`，这段提示词不用换。

Copy one of the blocks below into any AI assistant. If it can run terminal
commands, it will install Dòng for you; if it cannot, it will hand you the
three-line command instead.

---

## 中文版（复制这一整段）

```
请帮我在这台 Mac 上安装 Dòng（一个 macOS 动态壁纸 App）。

官方开源仓库：https://github.com/zhang-1-kael/dong
官网：https://dongisgood.coze.site/en
给 AI 的安装手册：仓库里的 AI_INSTALL.md

请按手册操作：
1. 先读 AI_INSTALL.md 和 install.sh，确认内容后再执行，不要用 curl | bash。
2. 优先用仓库的一键安装脚本：从官网稳定入口下载 dmg，用官方接口给的 SHA256 校验，挂载、装进「应用程序」、清除 macOS 隔离属性、启动。
3. 这个包是 ad-hoc 签名、没有 Apple 公证，macOS 可能提示「已损坏」；按手册清除 com.apple.quarantine 即可，不要全局关闭 Gatekeeper。
4. GitHub Releases 已发布 v3.31 安装包和完整发布包：https://github.com/zhang-1-kael/dong/releases/tag/v3.31 。优先走官网稳定入口；若官网打不开，可直接从该页面下载 Dong-3.31.dmg，用发布说明里的 SHA256 校验后再装。不要硬编码对象存储带 sign 的直链（会过期），也不要编造其它版本的 asset 地址。
5. 装好后告诉我结果，以及怎么用（菜单栏果冻图标 → 点开面板 → 粘贴 B 站 / YouTube 链接）。

安全要求：只用上面这几个官方域名；不要 sudo；不要删除或覆盖我的文件；校验和不匹配就停下来告诉我；每一步先说明你要做什么再执行。如果你没有终端权限，就直接给我可以复制的最短命令，不要假装已经装好了。
```

## English (copy this whole block)

```
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official open-source repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo

Follow the manual:
1. Read AI_INSTALL.md and install.sh before running anything; never curl | bash.
2. Prefer the repo's one-shot installer: download the DMG from the official stable endpoint, verify its SHA256 against the official release endpoint, mount it, copy the app into /Applications, clear the macOS quarantine attribute, and launch it.
3. The build is ad-hoc signed and not notarized, so macOS may say it is damaged. Clear com.apple.quarantine as the manual describes; do NOT disable Gatekeeper system-wide.
4. GitHub Releases now hosts the v3.31 package (installer + full release bundle): https://github.com/zhang-1-kael/dong/releases/tag/v3.31 . Prefer the official stable endpoint; if the site is down, download Dong-3.31.dmg from that page and verify the SHA256 in the release notes. Never hardcode the signed object-storage URL (it expires) and never invent asset URLs for other versions.
5. When done, tell me the result and how to use it (jelly icon in the menu bar → open the panel → paste a Bilibili / YouTube link).

Safety: use only the official hosts above; no sudo; do not delete or overwrite my files; stop and tell me if the checksum mismatches; explain each step before running it. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
```

---

## 给只想手动装的人 / Manual, in three lines

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh          # 先看一遍 / read it first
bash /tmp/dong-install.sh         # 再执行 / then run
```

`bash /tmp/dong-install.sh --dry-run` 只打印它打算做什么，不会下载也不会改动系统。
