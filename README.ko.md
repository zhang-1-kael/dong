<div align="center">
  <img width="225" height="225" src="assets/brandmark-sway.gif" alt="Dòng">
  <h1><b>Dòng</b></h1>
  <p>어떤 영상이든 살아 움직이는 데스크톱으로.<br>
  <a href="#features"><strong>Dòng 살펴보기 »</strong></a><br><br>
  <a href="#installation">macOS용 다운로드</a> · <a href="https://dongisgood.coze.site/en">공식 웹사이트 ↗</a><br>
  <a href="AI_INSTALL_PROMPT.md"><strong>🤖 AI에게 설치 맡기기 (가장 쉬움) »</strong></a><br>
  <i>~ 버전 3.31 · macOS 13 이상 · Apple Silicon ~</i></p>
  <p>
    <a href="README.en.md">English</a> · <a href="README.zh.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <b>한국어</b> · <a href="README.fr.md">Français</a><br>
    <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.ru.md">Русский</a>
  </p>
</div>

> [!NOTE]
>
> Dòng은 Swift와 AppKit만으로 작성한 macOS 라이브 배경화면 도구입니다 — 약 8,500줄의 코드, 서드파티 프레임워크는 단 하나도 없습니다.
> Electron도, SwiftUI도, Pod도 없습니다.
> 영상 링크를 붙여넣거나 로컬 영상을 끌어다 놓으면 다운로드하고, 자르고, 이어 붙여 끊김 없는 루프를 만든 뒤 데스크톱에 깔아 줍니다.

<h6 align="center">
  <a href="AI_INSTALL_PROMPT.md"><img src="https://img.shields.io/badge/AI_Install-One_message-7B61FF?style=for-the-badge&labelColor=23272A" alt="AI one-message install"></a>
  <a href="https://github.com/zhang-1-kael/dong/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-5865F2?style=for-the-badge&labelColor=23272A" alt="GPL-3.0 License"></a>
  <a href="https://github.com/zhang-1-kael/dong/releases"><img src="https://img.shields.io/badge/version-3.31-57F287?style=for-the-badge&labelColor=23272A" alt="Version 3.31"></a>
  <a href="https://github.com/zhang-1-kael/dong"><img src="https://img.shields.io/badge/macOS-13%2B-23272A?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 13+"></a>
  <a href="https://github.com/zhang-1-kael/dong"><img src="https://img.shields.io/badge/Swift-F05138?style=for-the-badge&labelColor=23272A&logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://github.com/zhang-1-kael/dong/stargazers"><img src="https://img.shields.io/github/stars/zhang-1-kael/dong?style=for-the-badge&label=Stars&color=FEE75C&labelColor=23272A" alt="Stars"></a>
  <a href="https://github.com/zhang-1-kael/dong/issues"><img src="https://img.shields.io/github/issues/zhang-1-kael/dong?style=for-the-badge&label=Issues&color=ED4245&labelColor=23272A" alt="Issues"></a>
</h6>

<a id="features" name="features"></a>

---

## 🤖 직접 설치하지 마세요 —— 이걸 AI에게 붙여넣으면 끝

> [!IMPORTANT]
> **가장 쉬운 설치 방법: AI에게 한 문장만 보내세요.** 아래 블록을 통째로 복사해 Mac에서 명령을 실행할 수 있는 AI 도구(WorkBuddy, Claude Code, Cursor, Codex 등)에 붙여넣으세요.
>
> 공식 사이트에서 DMG를 내려받고 SHA256을 검증한 뒤 «응용 프로그램»에 설치하고, macOS의 최초 실행 확인도 한 번에 마쳐 줍니다. 이후에는 더블클릭만 하면 열립니다.
>
> 터미널을 열거나 시스템 설정을 뒤질 필요가 전혀 없습니다.

**① 아래 블록 전체 복사**

```text
이 Mac에 macOS 라이브 배경화면 앱 Dòng을 설치해 주세요.

공식 저장소: https://github.com/zhang-1-kael/dong
공식 사이트: https://dongisgood.coze.site/en
AI용 설치 안내: 저장소의 AI_INSTALL.md / 원클릭 스크립트: install.sh

먼저 안내 문서와 스크립트를 읽고 그 지시를 따르세요. 공식 안정 엔드포인트에서 내려받고, 공식 API의 SHA256으로 검증하고, /Applications에 설치하고, macOS 최초 실행 확인을 마친 뒤 실행하고 결과와 사용법을 알려 주세요.
위 공식 도메인만 사용하고, sudo를 쓰지 말고, 내 파일을 삭제·덮어쓰기하거나 시스템 전체 보안 설정을 바꾸지 마세요. 터미널 권한이 없다면 복사 가능한 가장 짧은 명령만 알려 주고 설치했다고 하지 마세요.
```

**② AI에 붙여넣고 기다리기만 하면 됩니다. 첫 실행 시 앱이 묻는 «라이브 배경화면 켤까요?» 선택은 제가 직접 할게요.**

📖 관련 파일: [AI용 전체 안내](AI_INSTALL.md) · [프롬프트 모음](AI_INSTALL_PROMPT.md) · [원클릭 스크립트](install.sh) · [공식 사이트에서 직접 받기](https://dongisgood.coze.site/en)

---

## 기능

### 🖥 데스크톱 수준의 라이브 배경화면

WindowServer의 데스크톱 계층에 테두리 없는 창을 띄우고 `AVPlayerLayer`로 반복 재생합니다.
시스템 배경화면을 건드리지 않고, 커널 확장도, 관리자 권한도 필요 없습니다. 화면마다 창과 플레이어가 따로 있으며, 모니터를 연결하거나 빼면 창이 자동으로 다시 만들어집니다.

### 🔗 링크 → 배경화면

Bilibili / YouTube 링크를 붙여넣으면 다운로드, 변환, 미세 조정, 가져오기까지 전 과정이 자동으로 진행됩니다.
Douyin 링크는 플랫폼의 크롤링 방지 때문에 막혀 있습니다([알려진 제한](#알려진-제한) 참고). 먼저 영상을 로컬에 저장한 뒤 파일을 끌어다 놓으세요.

### ✂️ 자동으로 끊김 없는 루프 만들기

ffmpeg가 화면의 움직임을 1차원 신호로 바꾸고, 신호가 튀는 지점에서 실제 본편이 시작되는 위치를 찾아냅니다.
플랫폼 워터마크는 밝기, 화면비, 가장자리 밀도로 찾아낸 뒤 `delogo` 보간으로 지웁니다.
끝과 처음 사이에 0.4초 크로스페이드를 넣어 루프가 이어지는 지점을 완전히 감춥니다.

### 🎛 메뉴 막대 글래스 패널

메뉴 막대에 상주하는 앱입니다. 현재 배경화면, 디스크 사용량, 접속 시간, 링크 붙여넣기까지 — 모든 컨트롤을 AppKit으로 직접 그렸습니다.

<p align="center">
  <img src="assets/panel.jpg" width="620" alt="Dòng 메뉴 막대 패널">
</p>

### 📚 워터폴 배경화면 라이브러리

모든 배경화면을 표지 격자로 보여 줍니다. 마우스를 올리면 미리보기, 클릭하면 전환. 볼륨, 재생 조작, 현재 프레임 정보까지 한 화면에 담았습니다.

<p align="center">
  <img src="assets/library-wide.jpg" width="720" alt="Dòng 배경화면 라이브러리">
</p>

### 🔒 잠금 화면에도 같은 장면

한 프레임을 잡아 시스템 배경화면으로 지정합니다. 잠금을 풀면 움직이고, 잠그면 그대로 멈춘 같은 장면이 보입니다.

---

## 사용법

<a id="installation" name="installation"></a>

### 설치

#### Dòng 다운로드

[공식 사이트](https://dongisgood.coze.site/en)에서 최신 `.dmg`를 받아 연 뒤, Dòng을 «응용 프로그램»으로 끌어다 놓으세요.

이 빌드는 ad-hoc 서명이라 공증되지 않았습니다. macOS가 «손상됨»이라고 하면 `xattr -dr com.apple.quarantine "/Applications/Dòng.app"`을 한 번 실행한 뒤 다시 여세요.

> [!TIP]
> **직접 하기 귀찮다면 AI에 맡기세요.** [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)의 프롬프트를 아무 AI 도구에 붙여넣으면 다운로드·검증·설치를 한 번에 해 줍니다.
>
> 직접 빌드하려면 아래 단계를 따르세요. Xcode 명령줄 도구만 있으면 됩니다.

#### 소스에서 빌드

**유일한 의존성은 Xcode 명령줄 도구입니다** — Xcode 앱 전체는 필요하지 않습니다:

```bash
xcode-select --install   # 이미 설치했다면 건너뛰기
```

클론하고 컴파일:

```bash
git clone https://github.com/zhang-1-kael/dong.git
cd dong
./build.sh
open build/VideoWallpaper.app
```

`build.sh`는 `swiftc` 한 줄로 `.swift` 파일 10개를 실행 파일 하나로 컴파일한 뒤 `.app`을 조립합니다.
빌드는 **임시(ad-hoc) 서명**이라 자기 Mac에서만 실행되며, 다른 사람에게 배포하려면 `sign-notarize.sh`를 거쳐야 합니다.

##### 선택적 구성 요소

둘 다 컴파일에는 필요하지 않습니다 — 없으면 해당 기능만 꺼집니다:

| 구성 요소 | 용도 | 설치 |
|---|---|---|
| **ffmpeg** | 변환, 앞뒤 자르기, 워터마크 제거, 루프 | `brew install ffmpeg`, 또는 `~/.local/bin/ffmpeg`에 넣기 |
| **yt-dlp** | 링크 다운로드 | `brew install yt-dlp`, 또는 실행 파일을 `vendor/yt-dlp_macos`에 넣기 |

`build.sh`는 찾은 ffmpeg / yt-dlp를 앱 패키지에 함께 넣으므로, 다른 Mac으로 옮겨도 그대로 동작합니다.

> ⚠️ 이 저장소에는 **해당 바이너리 두 개도, 기본 제공 배경화면도 들어 있지 않습니다** — [라이선스 및 자료](#라이선스-및-자료)를 참고하세요.

##### DMG로 패키징

```bash
./package.sh                    # → dist/Dòng-<버전>.dmg
VW_NO_PRESETS=1 ./package.sh    # 기본 제공 배경화면 제외, DMG가 360 MB 작아짐
```

### 배경화면 가져오기

1. 메뉴 막대의 Dòng 아이콘을 눌러 패널을 엽니다;
2. 입력 칸에 Bilibili / YouTube 링크를 붙여넣고(공유 문구 전체를 넣어도 됩니다 — 앱이 링크만 골라냅니다) Enter를 누릅니다;
3. 또는 로컬 영상 파일을 라이브러리 창으로 바로 끌어다 놓습니다;
4. 아래쪽 알약 모양 진행 표시가 끝날 때까지 기다리면 — 보통 20~60초 — 배경화면이 바뀝니다.

---

## 아키텍처

«창 없는 메뉴 막대 앱»을 중심으로 네 개의 독립적인 파이프라인이 돌아갑니다:

```
┌──────────────────────────────────────────────────────────────┐
│               메뉴 막대 앱 (LSUIElement)                    │
│                                                              │
│  ① 표시     데스크톱 창 ×N  ──►  AVPlayerLayer  ──►  AVPlayerLooper │
│  ② 파이프라인 yt-dlp  ──►  ffmpeg 변환  ──►  라이브러리 │
│  ③ UI      메뉴 막대 패널 / 라이브러리 창 (전부 AppKit) │
│  ④ 시스템   LaunchAgent 자동 실행 · 폴더 감시 · 통계    │
└──────────────────────────────────────────────────────────────┘
```

| 파일 | 줄 수 | 역할 |
|---|---:|---|
| `main.swift` | 1 833 | 표시 계층: 데스크톱 창, 멀티 디스플레이, 플레이어 수명 주기, 자동 업데이트 연결 |
| `LibraryWindow.swift` | 2 631 | 라이브러리 창, 워터폴 배치 + 호버 미리보기 + 상주 투명도 슬라이더 |
| `Panel.swift` | 1 654 | 메뉴 막대 글래스 패널, 젤리 배지 애니메이션, 전부 직접 그림 |
| `Transcoder.swift` | 672 | 분석, 목표 크기, 앞뒤 감지, 워터마크 제거, 인코딩 |
| `Analytics.swift` | 534 | 익명 통계 + 클라우드 서비스 주소 (끌 수 있음) |
| `Updater.swift` | 515 | 자동 업데이트: 확인, 다운로드, SHA256 검증, 제자리 교체 |
| `Downloader.swift` | 202 | yt-dlp 래퍼와 진행률 파싱 |
| `FrameHealth.swift` | 320 | 끊김 감시 및 재생 프로브, diag.log 기록 |
| `LockScreen.swift` | 70 | 한 프레임을 시스템 배경화면으로 잡기 |
| `Presets.swift` | 47 | 기본 제공 자료의 최초 가져오기 |

**전체 기술 설명은 [`技术原理.md`](技术原理.md)(중국어)에 있습니다**: 창을 화면보다 24pt 크게 만들어야 하는 이유,
`--deep` 서명이 왜 해로운지, 루프 오디오 믹싱이 왜 세 구간으로 나눠 탐색해야 하는지,
직접 그린 패널이 반투명 유리를 덮어야 하는 이유까지 — 실제로 겪었던 실수와 함께 모든 함정을 기록해 두었습니다.

---

## 명령줄 디버깅

알고리즘을 조금 바꿀 때마다 전체 변환을 기다리기 귀찮다면, 헤드리스 진입점이 있습니다:

```bash
VideoWallpaper --detect a.mp4             # 감지만: 앞/뒤/워터마크 판정을 0.2초에
VideoWallpaper --try a.mp4 out.mp4        # 지정한 파일로 전체 변환 한 번
VideoWallpaper --import a.mp4 b.mp4       # 일괄 가져오기, 결과 출력
VideoWallpaper --link "https://…"         # 링크 다운로드 + 가져오기
```

디버깅 환경 변수는 `技术原理.md`의 9절에 있습니다(`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU` 등).

---

## 알려진 제한

| 제한 | 이유 |
|---|---|
| arm64 전용 | 빌드 대상과 내장 ffmpeg 모두 Apple Silicon이며, 유니버설 바이너리에는 `lipo`가 필요합니다 |
| 잠금 화면은 정지 화면 | macOS는 잠금 화면 영상을 서드파티에 열어 주지 않습니다. 프레임을 잡는 것이 선을 넘지 않는 유일한 방법입니다 |
| 여러 화면이 영상 하나를 공유 | 화면마다 플레이어는 따로 있지만 같은 파일을 재생합니다 |
| 업데이트는 완전 자동 | 확인 → 다운로드 → SHA256 검증 → 종료 시 교체 후 재실행. 설치가 실패할 때만 dmg를 엽니다 |
| Douyin 링크 불가 | Douyin은 `a_bogus` 크롤링 방지를 적용하고 로그인 쿠키를 요구해 익명 요청을 바로 거부합니다. 앱에서 영상을 먼저 저장한 뒤 파일을 끌어다 놓으세요 |
| 링크 다운로드에는 법적 경계가 있습니다 | 제3자 콘텐츠를 가져올 때는 권한이 있는 자료만 사용하세요 |

---

## 개인정보

앱에는 익명 사용 통계가 포함되어 있습니다. **기록되는 것**: 무작위로 생성된 설치 UUID, 버전 번호, 운영체제 버전,
CPU 아키텍처, 언어, 이벤트 이름.

**기록되지 않는 것**: 파일 이름, 폴더 경로, 링크 내용, 배경화면 이미지, 개인을 식별할 수 있는 모든 정보.
설정에서 한 번 클릭으로 끌 수 있고, 끄면 로컬 대기열을 즉시 비우고 모든 요청을 멈춥니다.

통계는 작성자 서버(`Analytics.swift`에 적힌 주소)로 전송되며 **기본적으로 켜져 있습니다**.
**이 저장소를 포크해 직접 배포한다면 `Analytics.swift` 50행의 `isEnabled` 기본값을 `false`로 바꾸세요** —
그렇지 않으면 여러분의 사용자 데이터가 작성자 서버로 전송됩니다. 기분 좋은 얘기는 아니지만 분명히 해야 합니다.

---

## 라이선스 및 자료

코드와 문서는 **GPL-3.0** 라이선스를 따릅니다 — [LICENSE](LICENSE) 참고. 수정한 바이너리를 배포할 때는 완전한 대응 소스 코드를 동일한 라이선스로 제공해야 합니다.

**이중 라이선스:** Dòng을 클로즈드 소스 상용 제품에 사용하려면 별도의 상용 라이선스가 필요합니다 — [COMMERCIAL.md](COMMERCIAL.md)를 보거나 이슈로 작성자에게 문의하세요.

> **이전 버전 안내:** v3.31 이하는 MIT 라이선스로 공개되었으며 해당 허가는 철회할 수 없습니다. GPL-3.0은 그 이후 버전에만 적용됩니다.

**라이선스에 포함되지 않는 것:**

- «Dòng»이라는 이름, `AppIcon.icns`, `BrandMark*.png` — 브랜드 표식이므로 파생물의 이름이나 아이콘에 쓰지 말아 주세요.
- **배경화면 자료**: `presets/`와 `bili/`는 `.gitignore`에 있으며, 저장소에는 영상 파일이 없습니다.
  직접 넣은 자료의 저작권은 각자 책임입니다.
- `ffmpeg`와 `yt-dlp` 바이너리는 저장소에 없습니다. 참고로 `--enable-gpl --enable-nonfree`로 빌드된 공식 ffmpeg는
  **재배포할 수 없습니다**. 배포하려면 LGPL 빌드로 바꾸고 인코더를 `libx264`에서 `h264_videotoolbox`로 변경하세요.

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
