#!/usr/bin/env python3
"""All human-readable strings for Dòng's per-language documentation.

One entry per language. `gen_i18n_docs.py` renders these into i18n/<lang>/
and `gen_i18n_readme.py` uses them to localise each README. Technical values
(URLs, file names, shell commands) are injected as {{PLACEHOLDERS}} so they
stay identical across languages.
"""

LANGS = ["en", "zh", "ja", "ko", "fr", "de", "es", "it", "ru"]

REPO = "https://github.com/zhang-1-kael/dong"
SITE = "https://dongisgood.coze.site/en"
STABLE = "https://dongisgood.coze.site/api/download?channel=stable"
META_URL = "https://dongisgood.coze.site/api/update/check?version=0&channel=stable"
RAW = "https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh"
XATTR = 'xattr -dr com.apple.quarantine "/Applications/Dòng.app"'

INSTALL = f"""curl -fsSL {RAW} -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh"""

MANUAL = f"""curl -fL -o ~/Downloads/Dong.dmg "{STABLE}"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg"""

DEBUG = """VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" """

PLACEHOLDERS = {
    "{{REPO}}": REPO,
    "{{SITE}}": SITE,
    "{{STABLE}}": STABLE,
    "{{META_URL}}": META_URL,
    "{{RAW}}": RAW,
    "{{XATTR}}": XATTR,
    "{{INSTALL}}": INSTALL,
    "{{MANUAL}}": MANUAL,
    "{{DEBUG}}": DEBUG,
}

# The one prompt every AI tool can read. The final line makes the AI answer in
# the reader's own language, so the human never has to read a foreign language.
EN_PROMPT = """Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: {repo}
Official site: {site}
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in {reply}."""

T = {
    # ------------------------------------------------------------------ EN
    "en": {
        "name": "English", "local": "English", "reply": "English",
        "badge_ai": "One_message", "badge_license": "License",
        "alt_panel": "Dòng menu bar panel", "alt_library": "Dòng wallpaper library",
        "lang_note": "Everything on this page — screenshots, linked docs and the prompt — is in English.",
        "prompt_note": "The prompt is written in English on purpose, so every AI tool understands it. Its last line asks the AI to reply in English — so everything you read stays in English.",
        "p": {
            "title": "Ask an AI to install Dòng",
            "intro": "Copy one block and paste it into an AI assistant that can run commands on your Mac. That's the whole install.",
            "common": "Recommended — the universal prompt",
            "common_hint": "Copy the whole block. The AI downloads the official DMG, verifies its SHA256, installs the app and finishes macOS's one-time first-open confirmation. Leave the app's own first-run choice to yourself.",
            "alt": "Alternative — the English prompt",
            "alt_hint": "Same instructions, phrased for a human reader.",
            "manual": "Prefer to run three commands yourself",
            "manual_tip": "Add --dry-run to preview: it prints what it would do without downloading or changing anything.",
            "nav": "All documents in English",
        },
        "m_sections": [
            ("Official endpoints", """| | |
|---|---|
| Repository | `{{REPO}}` |
| Official site | `{{SITE}}` |
| Stable DMG endpoint | `{{STABLE}}` |
| Version + SHA256 | `{{META_URL}}` |
| One-shot installer | `{{RAW}}` |"""),
            ("Rules you must not break", """- **GitHub Releases may be empty.** Never send the user there or invent an asset URL.
- **Never hardcode the object-storage URL.** `/api/download` redirects to a signed URL that expires.
- **The DMG is ad-hoc signed and not notarized.** Clearing `com.apple.quarantine` is expected; never disable Gatekeeper system-wide.
- **No `sudo`, no deleting or overwriting user files, no `curl | bash`.** Read the script first.
- Apple Silicon and macOS 13+ only. Intel Macs must build from source."""),
            ("Path A — you have a shell", """Read the installer before running it, preview it, then run it. Explain each step first.

```bash
{{INSTALL}}
```"""),
            ("Path B — no shell, or manual install", """Download from the stable endpoint, compare the SHA256 with the value from the metadata endpoint, then open the DMG.

```bash
{{MANUAL}}
```"""),
            ("After installing", """A jelly icon appears in the menu bar. Click it, open the panel, then paste a Bilibili / YouTube link or drag a local video in."""),
            ("If something goes wrong", """Stop immediately if the checksum does not match. If macOS says the app is damaged, run `{{XATTR}}` once and reopen it — do not touch system-wide security settings."""),
        ],
        "g_sections": [
            ("Architecture", """Four independent pipelines: desktop-layer windows with `AVPlayerLayer`, yt-dlp + ffmpeg transcoding, a hand-drawn AppKit menu bar panel and library, and LaunchAgent autostart / folder watching / anonymous stats."""),
            ("Key implementation details", """- Each window is 24 pt larger than the screen to hide rounded corners and desktop-switch edges.
- `--deep` code signing breaks nested resource signatures — don't use it.
- Loop audio is mixed with three separate seeks; a single pass leaves a click.
- The menu bar panel is drawn by hand so it covers the system frosted glass."""),
            ("Command-line debugging", """```bash
{{DEBUG}}
```

Environment variables (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) are listed in section 9 of the Chinese original."""),
            ("License & commercial use", """Code and docs are **GPL-3.0** — the legally binding text is the English [LICENSE](../../LICENSE). A separate commercial licence is available for closed-source products: [COMMERCIAL.md](../../COMMERCIAL.md)."""),
            ("Brand & assets", """The name "Dòng", `AppIcon.icns` and `BrandMark*.png` are brand marks. `presets/` and `bili/` (wallpaper videos) are not in this repo, and neither are the ffmpeg / yt-dlp binaries."""),
            ("Contributing & AI policy", """Issues and PRs are welcome; templates live in `.github/` and CI builds the app. AI-assisted contributions must be disclosed and reviewed line by line — [AI_POLICY.md](../../AI_POLICY.md)."""),
            ("Privacy", """Anonymous usage stats are on by default and can be switched off in Settings. If you fork the project, change the default of `isEnabled` in `Analytics.swift` to `false`.

Full Chinese technical write-up: [技术原理.md](../../技术原理.md)."""),
        ],
    },
    # ------------------------------------------------------------------ ZH
    "zh": {
        "name": "简体中文", "local": "简体中文", "reply": "Simplified Chinese",
        "badge_ai": "一条消息", "badge_license": "许可证",
        "alt_panel": "Dòng 菜单栏面板", "alt_library": "Dòng 壁纸库",
        "lang_note": "本页所有内容——截图、链接的文档、提示词——都是简体中文。",
        "prompt_note": "下面这段提示词刻意用英文写，这样任何 AI 工具都能读懂；最后一句已经要求它用简体中文回复你，所以你看到的仍然是中文。",
        "p": {
            "title": "让 AI 帮你安装 Dòng",
            "intro": "整段复制，粘贴给能操作你电脑的 AI 助手，安装就交给它了。",
            "common": "推荐：通用提示词（所有 AI 工具都能识别）",
            "common_hint": "整段复制粘贴给 AI。它会下载官方安装包、核对 SHA256、装进「应用程序」，并完成 macOS 首次打开的一次性确认。应用自己弹的首次运行选项留给你点。",
            "alt": "备选：中文提示词",
            "alt_hint": "如果你的 AI 助手更习惯中文，也可以用这一段。",
            "manual": "只想自己敲三行命令",
            "manual_tip": "加上 --dry-run 只预演：仅打印打算做的事，不下载、不改动系统。",
            "nav": "更多中文文档",
        },
        "m_sections": [
            ("官方地址", """| 项目 | 地址 |
|---|---|
| 官方仓库 | `{{REPO}}` |
| 官网 | `{{SITE}}` |
| 稳定下载入口 | `{{STABLE}}` |
| 版本与 SHA256 | `{{META_URL}}` |
| 一键安装脚本 | `{{RAW}}` |"""),
            ("必须遵守", """- **GitHub Releases 可能是空的。** 不要让用户去那里，也不要编造安装包地址。
- **不要硬编码对象存储直链。** `/api/download` 会 302 到带签名的临时链接，很快过期。
- **安装包是 ad-hoc 签名、未经 Apple 公证。** 清除 `com.apple.quarantine` 是正常步骤，不要全局关闭 Gatekeeper。
- **不要 `sudo`、不要删除或覆盖用户文件、不要 `curl | bash`。** 先读脚本再执行。
- 仅支持 Apple 芯片与 macOS 13+，Intel Mac 需要自己编译。"""),
            ("方式 A：有终端（推荐）", """先读一遍脚本，预演一次，再执行；每一步先说明要做什么。

```bash
{{INSTALL}}
```"""),
            ("方式 B：没有终端 / 想手动装", """从稳定入口下载，把 SHA256 与元数据接口给的值核对一遍，再打开 DMG。

```bash
{{MANUAL}}
```"""),
            ("装好之后", """菜单栏会出现果冻图标。点开面板，粘贴 B 站 / YouTube 链接，或直接把本地视频拖进去。"""),
            ("出问题怎么办", """校验和不符立即停下。若 macOS 提示「已损坏」，执行一次 `{{XATTR}}` 再打开，不要改动系统级安全设置。"""),
        ],
        "g_sections": [
            ("架构", """四条独立流水线：桌面层窗口与 `AVPlayerLayer`、yt-dlp + ffmpeg 转码、纯 AppKit 手绘的菜单栏面板与壁纸库、LaunchAgent 自启 / 目录监听 / 匿名统计。"""),
            ("关键实现", """- 窗口比屏幕大 24 pt，遮住圆角与切换桌面时露出的边。
- `--deep` 签名会破坏嵌套资源签名，不能用。
- 循环音频要分三段 seek 混音，一遍过会留下爆音。
- 菜单栏面板全部手绘，用来盖住系统毛玻璃。"""),
            ("命令行调试", """```bash
{{DEBUG}}
```

调试环境变量（`VW_PANEL_SHOT`、`VW_GEOM`、`VW_DUMP_MENU` 等）见中文原文第 9 节。"""),
            ("许可与商业授权", """代码与文档采用 **GPL-3.0**，具法律效力的全文是英文 [LICENSE](../../LICENSE)。闭源商用需另行申请商业授权：[COMMERCIAL.md](../../COMMERCIAL.md)。"""),
            ("品牌与素材", """名称「Dòng」、`AppIcon.icns`、`BrandMark*.png` 属于品牌标识。`presets/`、`bili/` 里的壁纸视频以及 ffmpeg / yt-dlp 二进制都不在本仓库中。"""),
            ("贡献与 AI 政策", """欢迎 issue 与 PR，模板在 `.github/`，CI 会自动构建。AI 辅助贡献需披露并逐行复核，见 [AI_POLICY.md](../../AI_POLICY.md)。"""),
            ("隐私", """匿名统计默认开启，可在设置里一键关闭。如果你 fork 本项目，请把 `Analytics.swift` 中 `isEnabled` 的默认值改成 `false`。

完整中文原文：[技术原理.md](../../技术原理.md)。"""),
        ],
    },
    # ------------------------------------------------------------------ JA
    "ja": {
        "name": "日本語", "local": "日本語", "reply": "Japanese",
        "badge_ai": "メッセージ1つ", "badge_license": "ライセンス",
        "alt_panel": "Dòng のメニューバーパネル", "alt_library": "Dòng の壁紙ライブラリ",
        "lang_note": "このページの内容（スクリーンショット・リンク先の文書・プロンプト）はすべて日本語です。",
        "prompt_note": "下のプロンプトは、どの AI ツールでも読めるよう意図的に英語で書いてあります。最後の一行で日本語での返答を指定しているので、あなたが読む文章は日本語のままです。",
        "p": {
            "title": "AI に Dòng をインストールしてもらう",
            "intro": "ブロックを丸ごとコピーし、Mac でコマンドを実行できる AI アシスタントに貼り付けるだけです。",
            "common": "推奨：共通プロンプト（すべての AI ツールが理解できます）",
            "common_hint": "ブロック全体をコピーして貼り付けてください。AI が公式 DMG のダウンロード、SHA256 の検証、インストール、macOS 初回起動時の確認まで行います。アプリ側の初回設定は自分で選んでください。",
            "alt": "別案：日本語のプロンプト",
            "alt_hint": "日本語の指示のほうが通る AI ツールなら、こちらを使っても構いません。",
            "manual": "自分で 3 行だけ実行したい場合",
            "manual_tip": "--dry-run を付けると、ダウンロードや変更をせずに予定だけを表示します。",
            "nav": "日本語のドキュメント一覧",
        },
        "m_sections": [
            ("公式のアドレス", """| 項目 | アドレス |
|---|---|
| 公式リポジトリ | `{{REPO}}` |
| 公式サイト | `{{SITE}}` |
| 安定版 DMG | `{{STABLE}}` |
| バージョンと SHA256 | `{{META_URL}}` |
| ワンコマンド導入スクリプト | `{{RAW}}` |"""),
            ("守るべきルール", """- **GitHub Releases は空のことがあります。** ユーザーをそこへ誘導せず、アセット URL を作らないでください。
- **オブジェクトストレージの直リンクを固定しないでください。** `/api/download` は期限付き署名 URL へリダイレクトします。
- **DMG は ad-hoc 署名で公証されていません。** `com.apple.quarantine` の解除は想定内です。Gatekeeper をシステム全体で無効化してはいけません。
- **`sudo`、ユーザーファイルの削除・上書き、`curl | bash` は禁止。** まずスクリプトを読んでください。
- Apple Silicon と macOS 13 以降のみ。Intel Mac はソースからビルドが必要です。"""),
            ("方法 A：ターミナルがある場合", """スクリプトを読んでから予行演習し、その後実行します。各手順の前に何をするか説明してください。

```bash
{{INSTALL}}
```"""),
            ("方法 B：ターミナルがない / 手動で入れる場合", """安定版エンドポイントからダウンロードし、メタデータの SHA256 と照合してから DMG を開きます。

```bash
{{MANUAL}}
```"""),
            ("インストール後", """メニューバーにゼリーのアイコンが出ます。クリックしてパネルを開き、Bilibili / YouTube のリンクを貼るか、ローカル動画をドラッグしてください。"""),
            ("うまくいかないとき", """チェックサムが一致しない場合は即座に中止してください。「壊れている」と表示されたら `{{XATTR}}` を一度実行して開き直します。システム全体のセキュリティ設定は変更しないでください。"""),
        ],
        "g_sections": [
            ("構成", """4 本の独立したパイプライン：デスクトップ層のウィンドウと `AVPlayerLayer`、yt-dlp + ffmpeg の変換、AppKit で手描きしたメニューバーパネルとライブラリ、LaunchAgent による自動起動・フォルダ監視・匿名統計です。"""),
            ("実装の要点", """- ウィンドウは画面より 24 pt 大きくし、角の丸みとデスクトップ切替時の縁を隠します。
- `--deep` 署名は入れ子のリソース署名を壊すため使いません。
- ループ音声は 3 回の seek で混合します。1 回だけだとノイズが残ります。
- メニューバーパネルはシステムのすりガラスを覆うため、すべて手描きです。"""),
            ("コマンドラインでのデバッグ", """```bash
{{DEBUG}}
```

環境変数（`VW_PANEL_SHOT`、`VW_GEOM`、`VW_DUMP_MENU` など）は中国語の原文書 9 章にあります。"""),
            ("ライセンスと商用利用", """コードと文書は **GPL-3.0** です。法的に有効な全文は英語の [LICENSE](../../LICENSE) です。クローズドソースの商用利用には別途ライセンスが必要です：[COMMERCIAL.md](../../COMMERCIAL.md)。"""),
            ("ブランドと素材", """名称「Dòng」、`AppIcon.icns`、`BrandMark*.png` はブランド標識です。`presets/` と `bili/` の壁紙動画、ffmpeg / yt-dlp のバイナリはリポジトリに含まれません。"""),
            ("コントリビューションと AI 方針", """issue と PR を歓迎します。テンプレートは `.github/`、CI でビルドされます。AI を使った貢献は開示し、行単位でレビューしてください：[AI_POLICY.md](../../AI_POLICY.md)。"""),
            ("プライバシー", """匿名の利用統計は既定で有効ですが、設定から無効化できます。fork する場合は `Analytics.swift` の `isEnabled` 初期値を `false` に変更してください。

中国語の完全な技術解説：[技术原理.md](../../技术原理.md)。"""),
        ],
    },
    # ------------------------------------------------------------------ KO
    "ko": {
        "name": "한국어", "local": "한국어", "reply": "Korean",
        "badge_ai": "메시지_하나", "badge_license": "라이선스",
        "alt_panel": "Dòng 메뉴 막대 패널", "alt_library": "Dòng 배경화면 보관함",
        "lang_note": "이 페이지의 모든 내용(스크린샷, 연결된 문서, 프롬프트)은 한국어입니다.",
        "prompt_note": "아래 프롬프트는 어떤 AI 도구든 읽을 수 있도록 일부러 영어로 작성했습니다. 마지막 줄에서 한국어로 답하라고 지정하므로, 여러분이 읽는 내용은 여전히 한국어입니다.",
        "p": {
            "title": "AI 에게 Dòng 설치를 맡기기",
            "intro": "블록을 통째로 복사해 Mac 에서 명령을 실행할 수 있는 AI 도구에 붙여넣으면 끝입니다.",
            "common": "추천: 공용 프롬프트(모든 AI 도구가 이해합니다)",
            "common_hint": "블록 전체를 복사해 붙여넣으세요. AI 가 공식 DMG 다운로드, SHA256 검증, 설치, macOS 첫 실행 확인까지 처리합니다. 앱 자체의 첫 실행 선택은 직접 하세요.",
            "alt": "다른 선택: 한국어 프롬프트",
            "alt_hint": "한국어 지시를 더 잘 이해하는 AI 도구라면 이쪽을 써도 됩니다.",
            "manual": "직접 명령 세 줄만 실행하고 싶다면",
            "manual_tip": "--dry-run 을 붙이면 다운로드나 변경 없이 계획만 출력합니다.",
            "nav": "한국어 문서 모음",
        },
        "m_sections": [
            ("공식 주소", """| 항목 | 주소 |
|---|---|
| 공식 저장소 | `{{REPO}}` |
| 공식 사이트 | `{{SITE}}` |
| 안정판 DMG | `{{STABLE}}` |
| 버전 및 SHA256 | `{{META_URL}}` |
| 한 번에 설치하는 스크립트 | `{{RAW}}` |"""),
            ("반드시 지킬 것", """- **GitHub Releases 가 비어 있을 수 있습니다.** 사용자를 그곳으로 보내거나 파일 URL 을 만들어 내지 마세요.
- **오브젝트 스토리지 직링크를 고정하지 마세요.** `/api/download` 는 만료되는 서명 URL 로 리다이렉트합니다.
- **DMG 는 ad-hoc 서명이며 공증되지 않았습니다.** `com.apple.quarantine` 제거는 정상 절차입니다. Gatekeeper 를 시스템 전체에서 끄지 마세요.
- **`sudo` 금지, 사용자 파일 삭제·덮어쓰기 금지, `curl | bash` 금지.** 먼저 스크립트를 읽으세요.
- Apple Silicon 및 macOS 13 이상만 지원합니다. Intel Mac 은 직접 빌드해야 합니다."""),
            ("방법 A: 터미널이 있는 경우", """스크립트를 먼저 읽고, 미리 실행해 본 뒤 실제로 실행합니다. 각 단계 전에 무엇을 할지 설명하세요.

```bash
{{INSTALL}}
```"""),
            ("방법 B: 터미널이 없거나 직접 설치할 경우", """안정판 주소에서 내려받고 메타데이터의 SHA256 과 비교한 뒤 DMG 를 엽니다.

```bash
{{MANUAL}}
```"""),
            ("설치 후", """메뉴 막대에 젤리 아이콘이 나타납니다. 클릭해 패널을 열고 Bilibili / YouTube 링크를 붙여넣거나 로컬 동영상을 끌어다 놓으세요."""),
            ("문제가 생기면", """체크섬이 다르면 즉시 중단하세요. macOS 가 «손상됨»이라고 하면 `{{XATTR}}` 을 한 번 실행한 뒤 다시 여세요. 시스템 전체 보안 설정은 건드리지 마세요."""),
        ],
        "g_sections": [
            ("구조", """네 개의 독립 파이프라인: 데스크톱 레이어 창과 `AVPlayerLayer`, yt-dlp + ffmpeg 변환, AppKit 으로 직접 그린 메뉴 막대 패널과 보관함, LaunchAgent 자동 실행·폴더 감시·익명 통계입니다."""),
            ("구현의 핵심", """- 창을 화면보다 24 pt 크게 만들어 둥근 모서리와 데스크톱 전환 시 드러나는 가장자리를 숨깁니다.
- `--deep` 서명은 중첩 리소스 서명을 망가뜨리므로 쓰지 않습니다.
- 반복 오디오는 세 번의 seek 로 혼합합니다. 한 번만 처리하면 잡음이 남습니다.
- 메뉴 막대 패널은 시스템 블러 효과를 덮기 위해 전부 직접 그립니다."""),
            ("명령줄 디버깅", """```bash
{{DEBUG}}
```

환경 변수(`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU` 등)는 중국어 원문 9 장에 정리되어 있습니다."""),
            ("라이선스와 상업적 이용", """코드와 문서는 **GPL-3.0** 입니다. 법적 효력이 있는 전문은 영어 [LICENSE](../../LICENSE) 입니다. 클로즈드 소스 상용 제품은 별도 라이선스가 필요합니다: [COMMERCIAL.md](../../COMMERCIAL.md)."""),
            ("브랜드와 자산", """이름 «Dòng», `AppIcon.icns`, `BrandMark*.png` 는 브랜드 표지입니다. `presets/`, `bili/` 의 배경화면 영상과 ffmpeg / yt-dlp 바이너리는 저장소에 포함되지 않습니다."""),
            ("기여와 AI 정책", """issue 와 PR 을 환영합니다. 템플릿은 `.github/` 에 있고 CI 가 빌드합니다. AI 도움을 받은 기여는 공개하고 줄 단위로 검토해야 합니다: [AI_POLICY.md](../../AI_POLICY.md)."""),
            ("개인정보", """익명 사용 통계는 기본적으로 켜져 있으며 설정에서 끌 수 있습니다. fork 했다면 `Analytics.swift` 의 `isEnabled` 기본값을 `false` 로 바꾸세요.

중국어 기술 원문: [技术原理.md](../../技术原理.md)."""),
        ],
    },
    # ------------------------------------------------------------------ FR
    "fr": {
        "name": "Français", "local": "français", "reply": "French",
        "badge_ai": "Un_message", "badge_license": "Licence",
        "alt_panel": "Panneau de la barre de menus de Dòng", "alt_library": "Bibliothèque de fonds d'écran de Dòng",
        "lang_note": "Tout le contenu de cette page — captures, documents liés et prompt — est en français.",
        "prompt_note": "Le prompt ci-dessous est volontairement en anglais pour être compris par tous les outils d'IA. Sa dernière ligne demande à l'IA de répondre en français : vous ne lisez donc que du français.",
        "p": {
            "title": "Demander à une IA d'installer Dòng",
            "intro": "Copiez un bloc, collez-le dans un assistant capable d'exécuter des commandes sur votre Mac, et c'est fait.",
            "common": "Recommandé — le prompt universel",
            "common_hint": "Copiez tout le bloc. L'IA télécharge le DMG officiel, vérifie son SHA256, installe l'app et effectue la confirmation unique de macOS au premier lancement. Le choix proposé par l'app au premier démarrage reste à vous.",
            "alt": "Autre option — le prompt en français",
            "alt_hint": "Si votre assistant comprend mieux le français, utilisez plutôt ce bloc.",
            "manual": "Préférer trois commandes à la main",
            "manual_tip": "Ajoutez --dry-run pour un aperçu : rien n'est téléchargé ni modifié.",
            "nav": "Tous les documents en français",
        },
        "m_sections": [
            ("Adresses officielles", """| Élément | Adresse |
|---|---|
| Dépôt officiel | `{{REPO}}` |
| Site officiel | `{{SITE}}` |
| DMG stable | `{{STABLE}}` |
| Version + SHA256 | `{{META_URL}}` |
| Script d'installation | `{{RAW}}` |"""),
            ("Règles à ne pas enfreindre", """- **Les GitHub Releases peuvent être vides.** N'y envoyez jamais l'utilisateur et n'inventez pas d'URL d'asset.
- **Ne codez jamais l'URL de stockage en dur.** `/api/download` redirige vers une URL signée qui expire.
- **Le DMG est signé ad-hoc et non notarisé.** Effacer `com.apple.quarantine` est normal ; ne désactivez jamais Gatekeeper globalement.
- **Pas de `sudo`, ni suppression/écrasement de fichiers, ni `curl | bash`.** Lisez d'abord le script.
- Apple Silicon et macOS 13+ uniquement. Les Mac Intel doivent compiler depuis les sources."""),
            ("Méthode A — avec un terminal", """Lisez le script, faites un essai à blanc, puis exécutez-le. Expliquez chaque étape avant de la lancer.

```bash
{{INSTALL}}
```"""),
            ("Méthode B — sans terminal / installation manuelle", """Téléchargez depuis l'URL stable, comparez le SHA256 à celui du endpoint de métadonnées, puis ouvrez le DMG.

```bash
{{MANUAL}}
```"""),
            ("Après l'installation", """Une icône gélatineuse apparaît dans la barre de menus. Cliquez, ouvrez le panneau, puis collez un lien Bilibili / YouTube ou glissez une vidéo locale."""),
            ("En cas de problème", """Arrêtez-vous immédiatement si la somme ne correspond pas. Si macOS dit que l'app est endommagée, exécutez une fois `{{XATTR}}` puis rouvrez-la, sans modifier la sécurité du système."""),
        ],
        "g_sections": [
            ("Architecture", """Quatre pipelines indépendants : fenêtres sur la couche bureau avec `AVPlayerLayer`, transcodage yt-dlp + ffmpeg, panneau de barre de menus et bibliothèque dessinés à la main en AppKit, démarrage automatique / surveillance de dossier / statistiques anonymes via LaunchAgent."""),
            ("Détails d'implémentation", """- Chaque fenêtre dépasse l'écran de 24 pt pour masquer les coins arrondis et les bords lors du changement de bureau.
- La signature `--deep` casse les signatures de ressources imbriquées : à éviter.
- L'audio en boucle est mixé en trois seeks ; un seul laisse un clic.
- Le panneau de la barre de menus est entièrement dessiné à la main pour couvrir le verre dépoli du système."""),
            ("Débogage en ligne de commande", """```bash
{{DEBUG}}
```

Les variables d'environnement (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) sont listées à la section 9 de l'original chinois."""),
            ("Licence et usage commercial", """Le code et la documentation sont sous **GPL-3.0** ; le texte juridiquement valable est le [LICENSE](../../LICENSE) anglais. Une licence commerciale distincte existe pour les produits propriétaires : [COMMERCIAL.md](../../COMMERCIAL.md)."""),
            ("Marque et ressources", """Le nom « Dòng », `AppIcon.icns` et `BrandMark*.png` sont des signes de marque. Les vidéos de `presets/` et `bili/`, ainsi que les binaires ffmpeg / yt-dlp, ne sont pas dans ce dépôt."""),
            ("Contribuer et politique IA", """Issues et PR sont bienvenues ; les modèles sont dans `.github/` et la CI compile l'app. Toute contribution assistée par IA doit être déclarée et relue ligne par ligne — [AI_POLICY.md](../../AI_POLICY.md)."""),
            ("Confidentialité", """Les statistiques anonymes sont activées par défaut et se désactivent dans les réglages. Si vous forkez le projet, passez la valeur par défaut de `isEnabled` dans `Analytics.swift` à `false`.

Texte technique complet en chinois : [技术原理.md](../../技术原理.md)."""),
        ],
    },
    # ------------------------------------------------------------------ DE
    "de": {
        "name": "Deutsch", "local": "Deutsch", "reply": "German",
        "badge_ai": "Eine_Nachricht", "badge_license": "Lizenz",
        "alt_panel": "Dòng-Menüleistenpanel", "alt_library": "Dòng-Hintergrundbibliothek",
        "lang_note": "Alle Inhalte dieser Seite — Screenshots, verlinkte Dokumente und der Prompt — sind auf Deutsch.",
        "prompt_note": "Der Prompt unten ist absichtlich auf Englisch, damit ihn jedes KI-Werkzeug versteht. Die letzte Zeile verlangt eine Antwort auf Deutsch — du liest also durchgehend Deutsch.",
        "p": {
            "title": "Dòng von einer KI installieren lassen",
            "intro": "Einen Block kopieren, in einen Assistenten einfügen, der Befehle auf deinem Mac ausführen kann — fertig.",
            "common": "Empfohlen — der universelle Prompt",
            "common_hint": "Den gesamten Block kopieren. Die KI lädt das offizielle DMG, prüft die SHA256, installiert die App und erledigt die einmalige Bestätigung von macOS beim ersten Start. Die Auswahl beim ersten App-Start triffst du selbst.",
            "alt": "Alternative — der Prompt auf Deutsch",
            "alt_hint": "Wenn dein KI-Assistent Deutsch besser versteht, kannst du diesen Block nehmen.",
            "manual": "Lieber drei Befehle selbst eingeben",
            "manual_tip": "Mit --dry-run wird nur angezeigt, was passieren würde — kein Download, keine Änderung.",
            "nav": "Alle Dokumente auf Deutsch",
        },
        "m_sections": [
            ("Offizielle Adressen", """| Eintrag | Adresse |
|---|---|
| Offizielles Repo | `{{REPO}}` |
| Offizielle Website | `{{SITE}}` |
| Stabile DMG-URL | `{{STABLE}}` |
| Version + SHA256 | `{{META_URL}}` |
| Installationsskript | `{{RAW}}` |"""),
            ("Regeln, die nicht gebrochen werden dürfen", """- **GitHub Releases können leer sein.** Schicke niemanden dorthin und erfinde keine Asset-URL.
- **Die Object-Storage-URL nie fest codieren.** `/api/download` leitet auf eine signierte URL weiter, die abläuft.
- **Das DMG ist ad-hoc signiert und nicht notarisiert.** `com.apple.quarantine` zu entfernen ist normal; Gatekeeper darf nie systemweit deaktiviert werden.
- **Kein `sudo`, keine gelöschten oder überschriebenen Dateien, kein `curl | bash`.** Erst das Skript lesen.
- Nur Apple Silicon und macOS 13+. Intel-Macs müssen selbst kompilieren."""),
            ("Weg A — mit Terminal", """Skript zuerst lesen, Probe-Lauf, dann ausführen. Vor jedem Schritt kurz erklären, was passiert.

```bash
{{INSTALL}}
```"""),
            ("Weg B — ohne Terminal / manuell", """Von der stabilen URL laden, SHA256 mit dem Wert der Metadaten-API vergleichen und das DMG öffnen.

```bash
{{MANUAL}}
```"""),
            ("Nach der Installation", """In der Menüleiste erscheint das Glibber-Symbol. Anklicken, Panel öffnen, dann einen Bilibili-/YouTube-Link einfügen oder eine lokale Videodatei hineinziehen."""),
            ("Wenn etwas schiefgeht", """Bei abweichender Prüfsumme sofort abbrechen. Sagt macOS, die App sei beschädigt, einmal `{{XATTR}}` ausführen und erneut öffnen — keine systemweiten Sicherheitseinstellungen ändern."""),
        ],
        "g_sections": [
            ("Architektur", """Vier unabhängige Pipelines: Fenster auf der Desktop-Ebene mit `AVPlayerLayer`, Transkodierung mit yt-dlp + ffmpeg, handgezeichnetes AppKit-Menüleistenpanel und Bibliothek sowie Autostart / Ordnerüberwachung / anonyme Statistik via LaunchAgent."""),
            ("Wichtige Implementierungsdetails", """- Jedes Fenster ist 24 pt größer als der Bildschirm, um abgerundete Ecken und Ränder beim Desktop-Wechsel zu verdecken.
- `--deep`-Signatur zerstört verschachtelte Ressourcensignaturen — nicht verwenden.
- Loop-Audio wird mit drei getrennten Seeks gemischt; ein Durchgang hinterlässt ein Knacken.
- Das Menüleistenpanel wird komplett von Hand gezeichnet, um den systemeigenen Milchglaseffekt zu überdecken."""),
            ("Debugging in der Kommandozeile", """```bash
{{DEBUG}}
```

Die Umgebungsvariablen (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) stehen in Abschnitt 9 des chinesischen Originals."""),
            ("Lizenz und kommerzielle Nutzung", """Code und Dokumentation stehen unter **GPL-3.0**; rechtlich verbindlich ist der englische [LICENSE](../../LICENSE)-Text. Für proprietäre Produkte gibt es eine eigene kommerzielle Lizenz: [COMMERCIAL.md](../../COMMERCIAL.md)."""),
            ("Marke und Assets", """Der Name „Dòng", `AppIcon.icns` und `BrandMark*.png` sind Markenzeichen. Die Wallpaper-Videos aus `presets/` und `bili/` sowie die ffmpeg-/yt-dlp-Binaries liegen nicht im Repo."""),
            ("Mitmachen und KI-Richtlinie", """Issues und PRs sind willkommen, Vorlagen liegen in `.github/`, die CI baut die App. KI-unterstützte Beiträge müssen offengelegt und Zeile für Zeile geprüft werden — [AI_POLICY.md](../../AI_POLICY.md)."""),
            ("Datenschutz", """Anonyme Statistik ist standardmäßig an und lässt sich in den Einstellungen abschalten. Wenn du das Projekt forkst, setze den Standardwert von `isEnabled` in `Analytics.swift` auf `false`.

Vollständige technische Ausführung auf Chinesisch: [技术原理.md](../../技术原理.md)."""),
        ],
    },
    # ------------------------------------------------------------------ ES
    "es": {
        "name": "Español", "local": "español", "reply": "Spanish",
        "badge_ai": "Un_mensaje", "badge_license": "Licencia",
        "alt_panel": "Panel de la barra de menús de Dòng", "alt_library": "Biblioteca de fondos de Dòng",
        "lang_note": "Todo el contenido de esta página — capturas, documentos enlazados y el prompt — está en español.",
        "prompt_note": "El prompt está escrito en inglés a propósito para que cualquier herramienta de IA lo entienda. Su última línea pide responder en español, así que todo lo que lees sigue en español.",
        "p": {
            "title": "Pide a una IA que instale Dòng",
            "intro": "Copia un bloque, pégalo en un asistente que pueda ejecutar comandos en tu Mac y listo.",
            "common": "Recomendado — el prompt universal",
            "common_hint": "Copia el bloque completo. La IA descarga el DMG oficial, verifica el SHA256, instala la app y completa la confirmación única de macOS al abrirla por primera vez. La elección inicial de la app la haces tú.",
            "alt": "Alternativa — el prompt en español",
            "alt_hint": "Si tu asistente entiende mejor el español, puedes usar este bloque.",
            "manual": "Prefieres ejecutar tres comandos tú mismo",
            "manual_tip": "Añade --dry-run para una simulación: no descarga nada ni cambia el sistema.",
            "nav": "Todos los documentos en español",
        },
        "m_sections": [
            ("Direcciones oficiales", """| Elemento | Dirección |
|---|---|
| Repo oficial | `{{REPO}}` |
| Sitio oficial | `{{SITE}}` |
| DMG estable | `{{STABLE}}` |
| Versión + SHA256 | `{{META_URL}}` |
| Script de instalación | `{{RAW}}` |"""),
            ("Reglas que no se pueden romper", """- **GitHub Releases puede estar vacío.** No envíes allí al usuario ni inventes una URL de asset.
- **No fijes la URL del almacenamiento de objetos.** `/api/download` redirige a una URL firmada que caduca.
- **El DMG tiene firma ad-hoc y no está notarizado.** Limpiar `com.apple.quarantine` es normal; nunca desactives Gatekeeper globalmente.
- **Nada de `sudo`, ni borrar/sobrescribir archivos, ni `curl | bash`.** Lee el script antes.
- Solo Apple Silicon y macOS 13+. Los Mac Intel deben compilar desde el código."""),
            ("Vía A — con terminal", """Lee el script, haz una simulación y luego ejecútalo. Explica cada paso antes de lanzarlo.

```bash
{{INSTALL}}
```"""),
            ("Vía B — sin terminal / instalación manual", """Descarga desde la URL estable, compara el SHA256 con el endpoint de metadatos y abre el DMG.

```bash
{{MANUAL}}
```"""),
            ("Después de instalar", """Aparece el icono de gelatina en la barra de menús. Ábrelo, despliega el panel y pega un enlace de Bilibili / YouTube o arrastra un vídeo local."""),
            ("Si algo falla", """Detente de inmediato si el checksum no coincide. Si macOS dice que la app está dañada, ejecuta una vez `{{XATTR}}` y vuelve a abrirla, sin tocar la seguridad del sistema."""),
        ],
        "g_sections": [
            ("Arquitectura", """Cuatro flujos independientes: ventanas en la capa del escritorio con `AVPlayerLayer`, transcodificación yt-dlp + ffmpeg, panel y biblioteca dibujados a mano en AppKit, y arranque automático / vigilancia de carpetas / estadísticas anónimas con LaunchAgent."""),
            ("Detalles clave de implementación", """- Cada ventana es 24 pt mayor que la pantalla para ocultar las esquinas redondeadas y los bordes al cambiar de escritorio.
- La firma `--deep` rompe las firmas de recursos anidados: no usar.
- El audio en bucle se mezcla con tres seeks; con uno solo queda un clic.
- El panel de la barra de menús se dibuja por completo a mano para cubrir el cristal esmerilado del sistema."""),
            ("Depuración por línea de comandos", """```bash
{{DEBUG}}
```

Las variables de entorno (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) están en la sección 9 del original chino."""),
            ("Licencia y uso comercial", """Código y documentación bajo **GPL-3.0**; el texto legalmente vinculante es el [LICENSE](../../LICENSE) en inglés. Para productos de código cerrado hay una licencia comercial aparte: [COMMERCIAL.md](../../COMMERCIAL.md)."""),
            ("Marca y recursos", """El nombre «Dòng», `AppIcon.icns` y `BrandMark*.png` son signos de marca. Los vídeos de `presets/` y `bili/` y los binarios de ffmpeg / yt-dlp no están en este repo."""),
            ("Contribuir y política de IA", """Se agradecen issues y PR; las plantillas están en `.github/` y la CI compila la app. Las contribuciones asistidas por IA deben declararse y revisarse línea por línea — [AI_POLICY.md](../../AI_POLICY.md)."""),
            ("Privacidad", """Las estadísticas anónimas están activadas por defecto y se desactivan en Ajustes. Si haces un fork, cambia el valor por defecto de `isEnabled` en `Analytics.swift` a `false`.

Artículo técnico completo en chino: [技术原理.md](../../技术原理.md)."""),
        ],
    },
    # ------------------------------------------------------------------ IT
    "it": {
        "name": "Italiano", "local": "italiano", "reply": "Italian",
        "badge_ai": "Un_messaggio", "badge_license": "Licenza",
        "alt_panel": "Pannello della barra dei menu di Dòng", "alt_library": "Libreria di sfondi di Dòng",
        "lang_note": "Tutti i contenuti di questa pagina — screenshot, documenti collegati e prompt — sono in italiano.",
        "prompt_note": "Il prompt è scritto apposta in inglese così qualsiasi strumento IA lo capisce. L'ultima riga chiede di rispondere in italiano: quindi tutto quello che leggi resta in italiano.",
        "p": {
            "title": "Chiedi a un'IA di installare Dòng",
            "intro": "Copia un blocco, incollalo in un assistente che può eseguire comandi sul tuo Mac e hai finito.",
            "common": "Consigliato — il prompt universale",
            "common_hint": "Copia tutto il blocco. L'IA scarica il DMG ufficiale, verifica lo SHA256, installa l'app e completa la conferma una tantum di macOS al primo avvio. La scelta iniziale dell'app la fai tu.",
            "alt": "Alternativa — il prompt in italiano",
            "alt_hint": "Se il tuo assistente capisce meglio l'italiano, puoi usare questo blocco.",
            "manual": "Preferisci digitare tre comandi da solo",
            "manual_tip": "Aggiungi --dry-run per una simulazione: non scarica nulla e non modifica il sistema.",
            "nav": "Tutti i documenti in italiano",
        },
        "m_sections": [
            ("Indirizzi ufficiali", """| Elemento | Indirizzo |
|---|---|
| Repo ufficiale | `{{REPO}}` |
| Sito ufficiale | `{{SITE}}` |
| DMG stabile | `{{STABLE}}` |
| Versione + SHA256 | `{{META_URL}}` |
| Script di installazione | `{{RAW}}` |"""),
            ("Regole da non infrangere", """- **Le GitHub Releases possono essere vuote.** Non mandarci l'utente e non inventare un URL dell'asset.
- **Non fissare l'URL dell'object storage.** `/api/download` reindirizza a un URL firmato che scade.
- **Il DMG ha firma ad-hoc e non è notarizzato.** Rimuovere `com.apple.quarantine` è normale; non disattivare Gatekeeper a livello di sistema.
- **Niente `sudo`, né cancellazione/sovrascrittura di file, né `curl | bash`.** Leggi prima lo script.
- Solo Apple Silicon e macOS 13+. I Mac Intel devono compilare dai sorgenti."""),
            ("Percorso A — con terminale", """Leggi lo script, fai una prova e poi eseguilo. Spiega ogni passo prima di lanciarlo.

```bash
{{INSTALL}}
```"""),
            ("Percorso B — senza terminale / installazione manuale", """Scarica dall'URL stabile, confronta lo SHA256 con l'endpoint dei metadati e apri il DMG.

```bash
{{MANUAL}}
```"""),
            ("Dopo l'installazione", """Nella barra dei menu appare l'icona gelatinosa. Cliccala, apri il pannello e incolla un link di Bilibili / YouTube oppure trascina un video locale."""),
            ("Se qualcosa va storto", """Fermati subito se il checksum non corrisponde. Se macOS dice che l'app è danneggiata, esegui una volta `{{XATTR}}` e riaprila, senza modificare la sicurezza di sistema."""),
        ],
        "g_sections": [
            ("Architettura", """Quattro pipeline indipendenti: finestre sul livello desktop con `AVPlayerLayer`, transcodifica yt-dlp + ffmpeg, pannello e libreria disegnati a mano in AppKit, e avvio automatico / monitoraggio cartelle / statistiche anonime tramite LaunchAgent."""),
            ("Dettagli implementativi chiave", """- Ogni finestra è 24 pt più grande dello schermo per nascondere gli angoli arrotondati e i bordi nel cambio desktop.
- La firma `--deep` rompe le firme annidate delle risorse: da evitare.
- L'audio in loop si mixa con tre seek separati; con uno solo resta un clic.
- Il pannello della barra dei menu è disegnato a mano per coprire il vetro smerigliato di sistema."""),
            ("Debug da riga di comando", """```bash
{{DEBUG}}
```

Le variabili d'ambiente (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) sono nella sezione 9 dell'originale cinese."""),
            ("Licenza e uso commerciale", """Codice e documentazione sono sotto **GPL-3.0**; il testo legalmente vincolante è il [LICENSE](../../LICENSE) in inglese. Per prodotti closed-source esiste una licenza commerciale separata: [COMMERCIAL.md](../../COMMERCIAL.md)."""),
            ("Marchio e risorse", """Il nome «Dòng», `AppIcon.icns` e `BrandMark*.png` sono segni distintivi. I video di `presets/` e `bili/` e i binari ffmpeg / yt-dlp non sono in questo repo."""),
            ("Contribuire e policy IA", """Issue e PR sono benvenute, i modelli sono in `.github/` e la CI compila l'app. I contributi assistiti da IA vanno dichiarati e rivisti riga per riga — [AI_POLICY.md](../../AI_POLICY.md)."""),
            ("Privacy", """Le statistiche anonime sono attive per impostazione predefinita e si disattivano nelle impostazioni. Se fai un fork, imposta a `false` il valore di `isEnabled` in `Analytics.swift`.

Approfondimento tecnico completo in cinese: [技术原理.md](../../技术原理.md)."""),
        ],
    },
    # ------------------------------------------------------------------ RU
    "ru": {
        "name": "Русский", "local": "русском", "reply": "Russian",
        "badge_ai": "Одно_сообщение", "badge_license": "Лицензия",
        "alt_panel": "Панель Dòng в строке меню", "alt_library": "Библиотека обоев Dòng",
        "lang_note": "Всё содержимое этой страницы — снимки, связанные документы и промпт — на русском языке.",
        "prompt_note": "Промпт ниже намеренно написан по-английски, чтобы его понял любой ИИ-инструмент. Последняя строка просит отвечать по-русски, поэтому всё, что вы читаете, остаётся на русском.",
        "p": {
            "title": "Попросить ИИ установить Dòng",
            "intro": "Скопируйте блок и вставьте его в помощника, который может выполнять команды на вашем Mac. На этом всё.",
            "common": "Рекомендуется — универсальный промпт",
            "common_hint": "Скопируйте весь блок. ИИ скачает официальный DMG, проверит SHA256, установит приложение и выполнит однократное подтверждение macOS при первом запуске. Выбор при первом запуске самого приложения оставьте за собой.",
            "alt": "Альтернатива — промпт на русском",
            "alt_hint": "Если ваш ИИ-помощник лучше понимает русский, используйте этот блок.",
            "manual": "Хотите выполнить три команды сами",
            "manual_tip": "С --dry-run будет только предварительный показ: ничего не скачивается и не меняется.",
            "nav": "Все документы на русском",
        },
        "m_sections": [
            ("Официальные адреса", """| Что | Адрес |
|---|---|
| Официальный репозиторий | `{{REPO}}` |
| Официальный сайт | `{{SITE}}` |
| Стабильная ссылка на DMG | `{{STABLE}}` |
| Версия и SHA256 | `{{META_URL}}` |
| Скрипт установки | `{{RAW}}` |"""),
            ("Правила, которые нельзя нарушать", """- **GitHub Releases может быть пустым.** Не отправляйте туда пользователя и не выдумывайте URL файла.
- **Не задавайте прямую ссылку объектного хранилища.** `/api/download` перенаправляет на подписанную ссылку с истекающим сроком.
- **DMG подписан ad-hoc и не нотаризован.** Удаление `com.apple.quarantine` — штатный шаг; не отключайте Gatekeeper для всей системы.
- **Никаких `sudo`, удаления или перезаписи файлов, никакого `curl | bash`.** Сначала прочитайте скрипт.
- Только Apple Silicon и macOS 13+. На Intel Mac нужно собирать из исходников."""),
            ("Способ А — есть терминал", """Сначала прочитайте скрипт, сделайте пробный запуск, затем выполните. Перед каждым шагом объясняйте, что делаете.

```bash
{{INSTALL}}
```"""),
            ("Способ Б — без терминала / вручную", """Скачайте со стабильной ссылки, сравните SHA256 со значением из API метаданных и откройте DMG.

```bash
{{MANUAL}}
```"""),
            ("После установки", """В строке меню появится желейный значок. Нажмите его, откройте панель и вставьте ссылку Bilibili / YouTube или перетащите локальное видео."""),
            ("Если что-то пошло не так", """При несовпадении контрольной суммы сразу остановитесь. Если macOS говорит, что приложение повреждено, один раз выполните `{{XATTR}}` и откройте снова, не меняя системные настройки безопасности."""),
        ],
        "g_sections": [
            ("Архитектура", """Четыре независимых конвейера: окна на слое рабочего стола с `AVPlayerLayer`, перекодирование yt-dlp + ffmpeg, нарисованные вручную панель строки меню и библиотека на AppKit, а также автозапуск / наблюдение за папками / анонимная статистика через LaunchAgent."""),
            ("Ключевые детали реализации", """- Каждое окно на 24 pt больше экрана, чтобы скрыть скруглённые углы и кромки при смене рабочего стола.
- Подпись `--deep` ломает вложенные подписи ресурсов — не используйте её.
- Звук для цикла микшируется тремя отдельными перемотками; при одной остаётся щелчок.
- Панель строки меню целиком рисуется вручную, чтобы перекрыть системное матовое стекло."""),
            ("Отладка из командной строки", """```bash
{{DEBUG}}
```

Переменные окружения (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) перечислены в разделе 9 китайского оригинала."""),
            ("Лицензия и коммерческое использование", """Код и документация под **GPL-3.0**; юридически значимый текст — английский [LICENSE](../../LICENSE). Для проприетарных продуктов нужна отдельная коммерческая лицензия: [COMMERCIAL.md](../../COMMERCIAL.md)."""),
            ("Бренд и материалы", """Название «Dòng», `AppIcon.icns` и `BrandMark*.png` — знаки бренда. Видео из `presets/` и `bili/`, а также бинарники ffmpeg / yt-dlp в репозитории отсутствуют."""),
            ("Участие и политика по ИИ", """Приветствуются issue и PR, шаблоны в `.github/`, CI собирает приложение. Вклад с помощью ИИ нужно раскрыть и проверить построчно — [AI_POLICY.md](../../AI_POLICY.md)."""),
            ("Приватность", """Анонимная статистика включена по умолчанию и отключается в настройках. Если вы делаете форк, задайте `isEnabled` в `Analytics.swift` значение `false` по умолчанию.

Полный технический разбор на китайском: [技术原理.md](../../技术原理.md)."""),
        ],
    },
}
