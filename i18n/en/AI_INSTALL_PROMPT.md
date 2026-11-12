# Ask an AI to install Dòng

Copy one block and paste it into an AI assistant that can run commands on your Mac. That's the whole install.

> [!TIP]
> The prompt is written in English on purpose, so every AI tool understands it. Its last line asks the AI to reply in English — so everything you read stays in English.

## ① Recommended — the universal prompt

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in English.
```

Copy the whole block. The AI downloads the official DMG, verifies its SHA256, installs the app and finishes macOS's one-time first-open confirmation. Leave the app's own first-run choice to yourself.

## ② Prefer to run three commands yourself

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

Add --dry-run to preview: it prints what it would do without downloading or changing anything.

---

## All documents in English

- [README.md](../../README.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
