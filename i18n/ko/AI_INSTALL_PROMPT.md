# AI 에게 Dòng 설치를 맡기기

블록을 통째로 복사해 Mac 에서 명령을 실행할 수 있는 AI 도구에 붙여넣으면 끝입니다.

> [!TIP]
> 아래 프롬프트는 어떤 AI 도구든 읽을 수 있도록 일부러 영어로 작성했습니다. 마지막 줄에서 한국어로 답하라고 지정하므로, 여러분이 읽는 내용은 여전히 한국어입니다.

## ① 추천: 공용 프롬프트(모든 AI 도구가 이해합니다)

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in Korean.
```

블록 전체를 복사해 붙여넣으세요. AI 가 공식 DMG 다운로드, SHA256 검증, 설치, macOS 첫 실행 확인까지 처리합니다. 앱 자체의 첫 실행 선택은 직접 하세요.

## ② 다른 선택: 한국어 프롬프트

```text
이 Mac에 macOS 라이브 배경화면 앱 Dòng을 설치해 주세요.

공식 저장소: https://github.com/zhang-1-kael/dong
공식 사이트: https://dongisgood.coze.site/en
AI용 설치 안내: 저장소의 AI_INSTALL.md / 원클릭 스크립트: install.sh

먼저 안내 문서와 스크립트를 읽고 그 지시를 따르세요. 공식 안정 엔드포인트에서 내려받고, 공식 API의 SHA256으로 검증하고, /Applications에 설치하고, macOS 최초 실행 확인을 마친 뒤 실행하고 결과와 사용법을 알려 주세요.
위 공식 도메인만 사용하고, sudo를 쓰지 말고, 내 파일을 삭제·덮어쓰기하거나 시스템 전체 보안 설정을 바꾸지 마세요. 터미널 권한이 없다면 복사 가능한 가장 짧은 명령만 알려 주고 설치했다고 하지 마세요.
```

한국어 지시를 더 잘 이해하는 AI 도구라면 이쪽을 써도 됩니다.

## ③ 직접 명령 세 줄만 실행하고 싶다면

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

--dry-run 을 붙이면 다운로드나 변경 없이 계획만 출력합니다.

---

## 한국어 문서 모음

- [README.ko.md](../../README.ko.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
