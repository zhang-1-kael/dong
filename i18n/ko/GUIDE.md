# Dòng — 기술 및 프로젝트 문서

> 프로젝트의 나머지 설명을 모두 한국어로 정리했습니다.

## 구조

네 개의 독립 파이프라인: 데스크톱 레이어 창과 `AVPlayerLayer`, yt-dlp + ffmpeg 변환, AppKit 으로 직접 그린 메뉴 막대 패널과 보관함, LaunchAgent 자동 실행·폴더 감시·익명 통계입니다.

## 구현의 핵심

- 창을 화면보다 24 pt 크게 만들어 둥근 모서리와 데스크톱 전환 시 드러나는 가장자리를 숨깁니다.
- `--deep` 서명은 중첩 리소스 서명을 망가뜨리므로 쓰지 않습니다.
- 반복 오디오는 세 번의 seek 로 혼합합니다. 한 번만 처리하면 잡음이 남습니다.
- 메뉴 막대 패널은 시스템 블러 효과를 덮기 위해 전부 직접 그립니다.

## 명령줄 디버깅

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

환경 변수(`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU` 등)는 중국어 원문 9 장에 정리되어 있습니다.

## 라이선스와 상업적 이용

코드와 문서는 **GPL-3.0** 입니다. 법적 효력이 있는 전문은 영어 [LICENSE](../../LICENSE) 입니다. 클로즈드 소스 상용 제품은 별도 라이선스가 필요합니다: [COMMERCIAL.md](../../COMMERCIAL.md).

## 브랜드와 자산

이름 «Dòng», `AppIcon.icns`, `BrandMark*.png` 는 브랜드 표지입니다. `presets/`, `bili/` 의 배경화면 영상과 ffmpeg / yt-dlp 바이너리는 저장소에 포함되지 않습니다.

## 기여와 AI 정책

issue 와 PR 을 환영합니다. 템플릿은 `.github/` 에 있고 CI 가 빌드합니다. AI 도움을 받은 기여는 공개하고 줄 단위로 검토해야 합니다: [AI_POLICY.md](../../AI_POLICY.md).

## 개인정보

익명 사용 통계는 기본적으로 켜져 있으며 설정에서 끌 수 있습니다. fork 했다면 `Analytics.swift` 의 `isEnabled` 기본값을 `false` 로 바꾸세요.

중국어 기술 원문: [技术原理.md](../../技术原理.md).

---

## 한국어 문서 모음

- [README.ko.md](../../README.ko.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
