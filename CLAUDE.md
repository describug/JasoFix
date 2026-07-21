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
- `Settings.swift` — UserDefaults(`com.seojungho.jasofix`) 기반. 키: `folders`, `backgroundEnabled`, `intervalMinutes`
- `AgentManager.swift` — LaunchAgent `com.seojungho.jasofix` 등록/해제 (토글·주기 변경 시 자동 반영)
- `ContentView.swift` — SwiftUI 설정 창

## 반드시 알아야 할 함정 (버그 원인 1순위)

- Swift의 `String ==`는 유니코드 정준 동등 비교라서 **NFD 문자열 == NFC 문자열이 true**다. 저장 형태 비교는 반드시 UTF-8 바이트로 (`NormalizeEngine.needsNormalize` 참고)
- `FileManager`의 `fileSystemRepresentation`은 경로를 다시 NFD로 되돌려버린다. 실제 rename은 `withCString` + POSIX `rename()` 사용
- APFS는 정규화 무시(normalization-insensitive)라 NFD/NFC 어느 형태의 경로로도 같은 파일이 열린다 — rename 후 옛 경로 참조가 깨지지 않는 이유

## 배포

- GitHub: `seojh517-code` 계정 public 저장소. **push는 사용자가 GitHub Desktop에서 직접** (Claude는 자격 증명 접근 불가). 커밋까지 해두고 "GitHub Desktop에서 Push origin 눌러주세요"라고 안내할 것

## 테스트 방법

스크래치 폴더에 NFD 이름 파일을 만들어 검증 (python: `unicodedata.normalize('NFD', ...)` 으로 생성 후 바이너리를 `--background-run`으로 실행). 이때 `defaults write com.seojungho.jasofix folders`를 임시로 바꾸면 **실제 사용자 설정을 덮어쓰므로 테스트 후 반드시 원복**할 것.
