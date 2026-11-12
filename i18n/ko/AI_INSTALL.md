# Dòng — 설치 안내서

> 사람이 읽는 설치 참고 문서입니다. AI 에이전트는 저장소 루트의 영문 AI_INSTALL.md 를 사용하세요.

## 공식 주소

| 항목 | 주소 |
|---|---|
| 공식 저장소 | `https://github.com/zhang-1-kael/dong` |
| 공식 사이트 | `https://dongisgood.coze.site/en` |
| 안정판 DMG | `https://dongisgood.coze.site/api/download?channel=stable` |
| 버전 및 SHA256 | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` |
| 한 번에 설치하는 스크립트 | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |

## 반드시 지킬 것

- **GitHub Releases 가 비어 있을 수 있습니다.** 사용자를 그곳으로 보내거나 파일 URL 을 만들어 내지 마세요.
- **오브젝트 스토리지 직링크를 고정하지 마세요.** `/api/download` 는 만료되는 서명 URL 로 리다이렉트합니다.
- **DMG 는 ad-hoc 서명이며 공증되지 않았습니다.** `com.apple.quarantine` 제거는 정상 절차입니다. Gatekeeper 를 시스템 전체에서 끄지 마세요.
- **`sudo` 금지, 사용자 파일 삭제·덮어쓰기 금지, `curl | bash` 금지.** 먼저 스크립트를 읽으세요.
- Apple Silicon 및 macOS 13 이상만 지원합니다. Intel Mac 은 직접 빌드해야 합니다.

## 방법 A: 터미널이 있는 경우

스크립트를 먼저 읽고, 미리 실행해 본 뒤 실제로 실행합니다. 각 단계 전에 무엇을 할지 설명하세요.

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh --dry-run
bash /tmp/dong-install.sh
```

## 방법 B: 터미널이 없거나 직접 설치할 경우

안정판 주소에서 내려받고 메타데이터의 SHA256 과 비교한 뒤 DMG 를 엽니다.

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg
open ~/Downloads/Dong.dmg
```

## 설치 후

메뉴 막대에 젤리 아이콘이 나타납니다. 클릭해 패널을 열고 Bilibili / YouTube 링크를 붙여넣거나 로컬 동영상을 끌어다 놓으세요.

## 문제가 생기면

체크섬이 다르면 즉시 중단하세요. macOS 가 «손상됨»이라고 하면 `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` 을 한 번 실행한 뒤 다시 여세요. 시스템 전체 보안 설정은 건드리지 마세요.

---

## 한국어 문서 모음

- [README.ko.md](../../README.ko.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
