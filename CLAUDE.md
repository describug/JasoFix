# JasoFix

맥 한글 파일명 자소 분리(NFD)를 조합형(NFC)으로 바꿔주는 macOS 앱. 윈도우 원격 데스크톱(Windows App) 폴더 공유에서 파일명이 깨져 보이는 문제를 해결하려고 만들었다.

## 빌드와 설치

```bash
./build.sh                              # build/JasoFix.app 생성 (swiftc 직접 빌드, Xcode 프로젝트 없음)
osascript -e 'quit app "JasoFix"'       # 실행 중이면 종료
rm -rf /Applications/JasoFix.app && cp -R build/JasoFix.app /Applications/
```

- 버전 올릴 때 `Resources/Info.plist`의 `CFBundleShortVersionString` 수정
- 사용자는 개발자가 아님 — 수정 후 빌드·설치·검증까지 끝내서 전달할 것

## 구조

- `Sources/JasoFix/main.swift` — 진입점. `--background-run` 인자가 있으면 UI 없이 변환만 하고 종료 (launchd용)
- `Engine.swift` — 변환 엔진. 하위 항목부터(깊은 것 먼저) rename, 마지막에 선택 폴더 자체도 rename
- `Settings.swift` — UserDefaults(`dev.describug.jasofix`) 기반. 키: `folders`, `backgroundEnabled`, `intervalMinutes`
- `AgentManager.swift` — LaunchAgent `dev.describug.jasofix` 등록/해제 (토글·주기 변경 시 자동 반영)
- `ContentView.swift` — SwiftUI 설정 창
- `Updater.swift` — 자동 업데이트. 설정 창을 열 때 GitHub 최신 릴리스(`tag_name`, `JasoFix.zip`)와 버전을 비교해 알림 → 받아서 ditto로 풀고 번들 ID·버전·서명 확인 → 지금 앱 자리에 바꿔 끼운 뒤 재실행. 백그라운드 실행(`--background-run`)에서는 확인하지 않음

## 반드시 알아야 할 함정 (버그 원인 1순위)

- Swift의 `String ==`는 유니코드 정준 동등 비교라서 **NFD 문자열 == NFC 문자열이 true**다. 저장 형태 비교는 반드시 UTF-8 바이트로 (`NormalizeEngine.needsNormalize` 참고)
- `FileManager`의 `fileSystemRepresentation`은 경로를 다시 NFD로 되돌려버린다. 실제 rename은 `withCString` + POSIX `rename()` 사용
- APFS는 정규화 무시(normalization-insensitive)라 NFD/NFC 어느 형태의 경로로도 같은 파일이 열린다 — rename 후 옛 경로 참조가 깨지지 않는 이유

## 배포

- GitHub: `describug` 계정 public 저장소. **push는 사용자가 GitHub Desktop에서 직접** (Claude는 자격 증명 접근 불가). 커밋까지 해두고 "GitHub Desktop에서 Push origin 눌러주세요"라고 안내할 것

- 릴리스는 `v1.3.0` 같은 태그를 push하면 GitHub Actions가 만든다. **태그 버전과 Info.plist 버전이 같아야** 자동 업데이트가 받는다 (다르면 "올바른 JasoFix가 아닙니다"로 거부)

## 테스트 방법

자동 업데이트: 환경변수 `JASOFIX_UPDATE_FEED`로 GitHub API 대신 로컬 JSON(`{"tag_name":"v1.3.1","assets":[{"name":"JasoFix.zip","browser_download_url":"http://127.0.0.1:8765/JasoFix.zip"}]}`)을 보게 해서, 스크래치 폴더에 복사한 앱으로 검증한다.


스크래치 폴더에 NFD 이름 파일을 만들어 검증 (python: `unicodedata.normalize('NFD', ...)` 으로 생성 후 바이너리를 `--background-run`으로 실행). 이때 `defaults write dev.describug.jasofix folders`를 임시로 바꾸면 **실제 사용자 설정을 덮어쓰므로 테스트 후 반드시 원복**할 것.
