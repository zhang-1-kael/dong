# Dòng — Installation manual

> A readable version of the installation reference. AI agents should use the English AI_INSTALL.md in the repo root.

## Official endpoints

| | |
|---|---|
| Repository | `https://github.com/zhang-1-kael/dong` |
| Official site | `https://dongisgood.coze.site/en` |
| Stable DMG endpoint | `https://dongisgood.coze.site/api/download?channel=stable` |
| Version + SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| One-shot installer | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## Rules you must not break

- **GitHub Releases hosts v3.31** (`https://github.com/zhang-1-kael/dong/releases/tag/v3.31`): `Dong-3.31.dmg` plus a full release bundle. Use it as a fallback if the official site is down; always verify the SHA256. Never invent asset URLs for other versions.
- **Never hardcode the object-storage URL.** `/api/download` redirects to a signed URL that expires.
- **The DMG is ad-hoc signed and not notarized.** Clearing `com.apple.quarantine` is expected; never disable Gatekeeper system-wide.
- **No `sudo`, no deleting or overwriting user files, no `curl | bash`.** Read the script first.
- Apple Silicon and macOS 13+ only. Intel Macs must build from source.

## Path A — you have a shell

Read the installer before running it, preview it, then run it. Explain each step first.

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## Path B — no shell, or manual install

Download from the stable endpoint, compare the SHA256 with the value from the metadata endpoint, then open the DMG.

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## After installing

A jelly icon appears in the menu bar. Click it, open the panel, then paste a Bilibili / YouTube link or drag a local video in.

## If something goes wrong

Stop immediately if the checksum does not match. If macOS says the app is damaged, run `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` once and reopen it — do not touch system-wide security settings.

---

## All documents in English

- [README.md](../../README.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
