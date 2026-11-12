# Dòng — 安装手册

> 给读者看的安装参考。AI 代理请直接读仓库根目录的英文版 AI_INSTALL.md。

## 官方地址

| 项目 | 地址 |
|---|---|
| 官方仓库 | `https://github.com/zhang-1-kael/dong` |
| 官网 | `https://dongisgood.coze.site/en` |
| 稳定下载入口 | `https://dongisgood.coze.site/api/download?channel=stable` |
| 版本与 SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| 一键安装脚本 | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## 必须遵守

- **GitHub Releases 已发布 v3.31**（`https://github.com/zhang-1-kael/dong/releases/tag/v3.31`）：`Dong-3.31.dmg` 与完整发布包。官网打不开时可作为备用入口，仍要核对 SHA256；不要编造其它版本的下载地址。
- **不要硬编码对象存储直链。** `/api/download` 会 302 到带签名的临时链接，很快过期。
- **安装包是 ad-hoc 签名、未经 Apple 公证。** 清除 `com.apple.quarantine` 是正常步骤，不要全局关闭 Gatekeeper。
- **不要 `sudo`、不要删除或覆盖用户文件、不要 `curl | bash`。** 先读脚本再执行。
- 仅支持 Apple 芯片与 macOS 13+，Intel Mac 需要自己编译。

## 方式 A：有终端（推荐）

先读一遍脚本，预演一次，再执行；每一步先说明要做什么。

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## 方式 B：没有终端 / 想手动装

从稳定入口下载，把 SHA256 与元数据接口给的值核对一遍，再打开 DMG。

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## 装好之后

菜单栏会出现果冻图标。点开面板，粘贴 B 站 / YouTube 链接，或直接把本地视频拖进去。

## 出问题怎么办

校验和不符立即停下。若 macOS 提示「已损坏」，执行一次 `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` 再打开，不要改动系统级安全设置。

---

## 更多中文文档

- [README.zh.md](../../README.zh.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
