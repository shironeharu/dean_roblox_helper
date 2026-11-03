# AGENTS.md

## Project Overview

A **Vite + TailwindCSS** WebView GUI template for **AutoHotkey v2**. Uses [WebViewToo](https://github.com/The-CoDingman/WebViewToo) to render a web-based frontend inside an AHK desktop window, with bidirectional message passing between the AHK script and the web frontend.

## Launcher + dean.dll (배포 구조)

배포 형태는 폴더에 같이 넣는 `DEAN ROBLOX.exe`(런처) + `dean.dll`(화면·기능) 두 파일입니다.

- `launcher/launcher.ahk` → 컴파일하면 exe. 시작할 때 GitHub 릴리스(`releases/latest/download/`)의 `dean.version`이 로컬 `dean.dll`보다 높으면 `dean.dll`+`dean.dll.sha256`을 받아 해시 검증 후 교체하고, `dean.dll`을 로드해 `NewThread`로 앱을 실행합니다. 화면(코어 스레드)이 끝나면 런처도 종료합니다.
- `dean.dll` = `vendor/AutoHotkey64.dll`(AutoHotkey_H 런타임) + 리소스(합친 앱 스크립트 `APP_SCRIPT`, `APP_VERSION`, `WEBVIEW2LOADER`, 화면 파일 `UI_*` + `UI_MANIFEST`). `scripts/bundle-core.mjs`가 `app.ahk`의 `#Include`를 펼치고, `scripts/pack-core.ahk`가 리소스를 넣습니다.
- `app.ahk`는 개발 모드(`npm run dev`)와 코어 모드(`--core 화면폴더 로더경로 설정폴더` 인자)를 모두 지원합니다. 코어 모드에서는 `A_IsCompiled`가 false이므로 화면은 `BrowseFolder`로 지정합니다.
- 빌드: `npm run build:core` → `build/dean.dll`, `build/dean.dll.sha256`, `build/dean.version` / `npm run build:launcher` → `build/DEAN ROBLOX.exe`.
- 릴리스: `version.txt`를 올리고 커밋한 뒤 같은 값의 태그(`v1.05`)를 push하면 `.github/workflows/release.yml`이 dean.dll과 런처 EXE를 빌드해 함께 릴리스로 올립니다. 자동 업데이트는 DLL만 교체하므로 런처 변경은 새 EXE를 배포합니다.
- `Ahk2Exe`는 상대 경로를 스크립트 위치 기준으로 해석하고 오류 시 창을 띄운 채 멈출 수 있으니, 컴파일은 `scripts/build-launcher.mjs`처럼 절대 경로 + `/silent`로 호출합니다.

## Repository Structure

```
app.ahk                  # AHK entry point — creates WebViewGui, registers callbacks
gen_resource.ahk         # Generates resource.ahk with embedded dist/ assets for compiled builds
resource.ahk             # Generated file — do not edit manually
vite.config.js           # Vite config (root: frontend/, output: dist/)
frontend/
  index.html             # Frontend entry — loads components via <load> tags
  index2.html            # Clean single-page template (input + Confirm + Exit) used by `npm run init`
  src/
    main.js              # Page navigation and AHK message handling
    counter.js           # Standalone frontend counter component
    stepper.js           # Stepper control logic
    app.css              # TailwindCSS v4 + DaisyUI v5 theme config
  components/            # 20 HTML partials injected via vite-plugin-html-inject
  public/assets/         # Static assets (images, fonts)
scripts/
  dev.js                 # Dev orchestrator — runs Vite + AHK concurrently
  init-workspace.js      # Workspace initializer — strips template demo, creates clean workspace
webview/                 # WebViewToo library (WebView2 wrapper for AHK)
dist/                    # Build output (generated)
```

## Development Commands

앱과 런처는 `require-admin.ahk`를 통해 항상 관리자 권한으로 실행합니다. Windows 권한 요청을 취소하면 실행을 종료합니다. `scripts/dev.js`는 F6 종료 코드 5173일 때만 AHK를 다시 시작하며, 정상 종료나 관리자 재실행 시에는 반복 실행하지 않습니다.

| Command | Description |
|---|---|
| `npm install` | Install dependencies |
| `npm run dev` | Start dev mode (Vite + AHK, frontend hot-reloads) |
| `npm run dev:watch` | Dev mode with auto-reload on AHK file changes |
| `npm run build:front` | Build frontend to `dist/` |
| `npm run build:ahk` | Compile AHK script to `app.exe` (requires ahk64 CLI) |
| `npm run build` | Full build (frontend + AHK compilation) |
| `npm run preview` | Run compiled `app.exe` |
| `npm run init` | Strip template demo and create a clean workspace for custom development |

Press `F6` in dev mode to reload the AHK script. Press `Ctrl+C` to exit dev mode.

## Architecture

- **AHK ↔ Frontend communication**: AHK calls `MyGui.PostWebMessageAsJson()` to send JSON messages to the web frontend. Frontend calls `window.chrome.webview.postMessage()` to send messages back. AHK registers callbacks via `MyGui.AddCallbackToScript()`.
- **Component loading**: HTML partials in `frontend/components/` are loaded into `index.html` using `<load src="...">` syntax (processed by `vite-plugin-html-inject`).
- **Dev vs compiled**: In dev mode, AHK navigates to `http://localhost:5173` (Vite dev server). In compiled mode, it loads `index.html` from embedded resources.
- **Theming**: DaisyUI custom dark theme defined in `frontend/src/app.css` using `@plugin "daisyui/theme"`.
- **Workspace init**: `npm run init` replaces `index.html` with a minimal single-page (`index2.html`), simplifies `app.ahk`, and removes all template demo files (components, demo JS, unused assets). Use this to start a new project from a clean slate.

## Coding Conventions

- **AutoHotkey**: v2.0 64-bit syntax. Tab indentation.
- **JavaScript**: Vanilla JS only — no frameworks, no TypeScript. ES modules.
- **CSS**: TailwindCSS v4 utility classes + DaisyUI v5 components. Custom theme in `app.css`.
- **HTML components**: Place reusable HTML partials in `frontend/components/`. Use `<load src="./components/name.html">` to include them.
- **Message protocol**: JSON objects with `type` and `content` fields for AHK↔frontend communication.
- **No linter or formatter** is configured — match existing code style.

## Testing

- `pc-recorder.ahk`는 PC 전체 입력 녹화·재생 모듈이며 시작 구간에서 include합니다. 기본 F8/F9/F10은 녹화/재생·일시정지/중단이며 사용자 지정이 가능합니다. Ctrl+Alt+Esc는 긴급 중단입니다. 다른 도우미는 정지하고 채팅 핫키는 끝난 뒤 복원합니다.
- 녹화는 최대 30분 또는 10만 이벤트이며 `.deanrec` 숫자 이벤트 형식으로 저장합니다. 읽기 시 크기·시간순서·입력 종류를 검증하고 코드로 실행하지 않습니다. 재생은 화면 좌표 기반이므로 녹화 당시 모니터 배치가 일치해야 합니다. 한글 조합 상태나 클립보드 내용은 별도로 녹화하지 않습니다.

- 멀티 실행의 개별 종료는 실행 파일 이름을 검증한 프로세스 핸들 하나만 종료합니다. 실제 게임 대신 별도 테스트 프로세스로 격리 여부를 검증합니다.
- 채팅·클릭 핫키는 `HotIfWinActive`로 Roblox에 한정합니다. 잠수 입력 중에는 자동 클릭을 중단하고 물리 입력 직후에는 잠수 창 전환을 미룹니다.

- `session-unlocker.ahk`: 앱 시작 구간에서 include하는 Windows x64 멀티 실행 모듈. 실행 수 제한 없이 기존 Roblox의 `ROBLOX_singletonEvent`만 해제하고 한 번에 하나씩 추가 실행합니다. 클래스 초기화가 있으므로 auto-execute의 `return` 뒤에 include하지 않습니다.
- 잠수도우미는 선택한 HWND/PID 목록을 순회합니다. 일부 창이 닫혀도 나머지는 계속 실행합니다. 채팅 한/영 기억값은 HWND/PID별로 관리하며 입력을 다른 창에 복제하지 않습니다.
- `robbery-protection.ahk`는 잠수 키 `감지` 모드입니다. 경고 아이콘 모양만 FindText로 검사합니다. 사용자 원본 패턴과 실제 큰/작은 창에서 추출한 아이콘 패턴을 함께 사용하며 60~150% 배율과 글자·배경 오차 각각 15%를 허용합니다. 빨간 진행 막대·비슷한 피부색·이름표만으로 감지하지 않습니다. 1초마다 선택한 모든 HWND/PID에 별도 캡처 프로세스를 요청하며 처리 중인 창은 중복 실행하지 않습니다. 최소화·검은 캡처는 경고를 표시하고 미감지로 처리하지 않습니다. 검사 대상은 확인용과 동일한 JPG이며 감지 시 전체 JPG를 앱 설정 폴더의 `소매치기 범인`에 `범인 yyMMdd_AM/PM_hh_mm.jpg` 형식으로 한 번 저장하고 해당 창에만 리스폰 입력을 보냅니다. 문구 소실 3회와 10초 재실행 제한이 있으며 보호 횟수는 입력 완료 횟수입니다.
- `window-capture.cs`는 Windows .NET Framework C# 캡처 도우미입니다. `scripts/build-capture.mjs`가 `frontend/public/assets/dean-window-capture.exe`를 생성하며 `npm run dev` 및 `npm run build:front`에서 먼저 빌드합니다. 이 EXE는 UI_MANIFEST를 통해 DLL에 포함됩니다. PrintWindow(3)는 별도 프로세스에서만 호출하고 부모는 프로세스 핸들로 2.5초 제한·중단을 관리합니다. 창별 임시 JPG/ready 슬롯은 처리 후 삭제하고 사건 JPG만 보존합니다. FindText는 저장된 상단 중앙 600×200 영역을 메모리에서 검색하며 배율 간 캡처를 재사용합니다. `vendor/FindText.README.md`에 라이브러리 출처를 기록합니다.
- 멀티 실행 목록의 ID는 Roblox 계정 ID가 아니라 Windows PID입니다. 실제 게임의 세션을 변경하는 테스트와 테스트용 프로세스 검증을 구분합니다.

No test framework is configured. Verify changes manually by running `npm run dev` and interacting with the WebView UI.

## Contribution Rules for Agents

- Make minimal, focused changes — do not refactor unrelated code.
- Preserve existing code style and architecture patterns.
- Frontend changes: verify with `npm run dev` that the UI renders correctly.
- AHK changes: verify with `npm run dev` that the script loads and callbacks work.
- Do not edit `resource.ahk` — it is auto-generated by `gen_resource.ahk`.
- Do not modify files in `webview/` — it is a third-party library.
- Update this AGENTS.md when repository conventions, commands, structure, or workflows change.

- PC 녹화 단축키는 Recorder 섹션에 저장하며 F1~F12와 Insert/Home/PgUp/PgDn/Delete/End를 지원합니다. 클릭 단축키와 중복을 금지합니다. 재생 키는 일시정지/재개를 겸하고 Ctrl+Alt+Esc는 긴급 중단입니다. F6을 녹화 단축키로 지정하면 개발 재시작 키는 비활성화됩니다. 녹화 파일은 검증된 숫자 이벤트를 담는 .deanrec 형식입니다.

- 감지 모드의 캡처·리스폰은 물리 입력 중에도 실행합니다. 일반 잠수 입력의 0.5초 입력 대기는 유지합니다. 테스트용 최신 캡처 보관은 제거했으며 사건 저장은 `소매치기 범인`에 유지합니다. 기존 캡처 폴더들은 Git에서 제외합니다.

- 감지 모드에서도 300초마다 모든 선택 창에 스페이스 한 번을 보냅니다. `ProtectionHeartbeat`가 감지와 별도의 1초 타이머로 `NextJumpTick`을 확인해 `DoJump(true)`를 호출하며 실패한 창만 재시도한 뒤 다음 300초를 셉니다. 감지·리스폰과 점프는 `afkInputBusy`와 감지 Busy 상태로 겹침을 막고 중단 시 두 타이머를 함께 해제합니다.

- 300초 점프 기한은 리스폰·캡처로 초기화하지 않으며 기한이 되면 새 캡처보다 우선 처리합니다. 입력 중첩 때도 기한을 유지하여 다음 타이머 틱에 다시 시도합니다.

- 캡처 도우미는 `CreateProcessW`의 `STARTF_FORCEOFFFEEDBACK | STARTF_USESHOWWINDOW`로 숨겨 실행해 매초 실행 로딩 커서가 표시되지 않도록 합니다. 반환된 프로세스 핸들을 직접 보관하며 thread 핸들은 즉시 닫습니다. `Run`으로 되돌리면 로딩 커서가 다시 나타날 수 있습니다.

- 캡처 도우미는 `--serve 부모PID` 모드로 창별 1개를 재사용합니다. `.request.tmp`→`.request`, `.result.tmp`→`.result` 원자적 파일 교체로 완료 신호를 전달하며 검사 도중 덮어쓰지 않습니다. 타임아웃인 창만 도우미를 종료·재생성하고 개별 오류로 감지 전체나 300초 점프를 끄지 않습니다. 중단 시 유휴 도우미까지 모두 정리하며 부모 종료·30초 무요청 시 도우미도 종료합니다. `protection.log`는 오류·복구만 기록하고 256KB를 넘으면 초기화합니다.

- 응답성: JPEG 디코딩과 FindText 검색은 `warning-match-worker.ahk`를 컴파일한 `dean-warning-match.exe`에서만 수행합니다. `warning-matcher.ahk`가 공통 패턴 매칭을 정의하며 UI 스레드는 작은 완료 파일만 읽습니다. 검색 도우미는 앱당 1개를 재사용하고 2.5초 검색 타임아웃이면 해당 검색 대기 프레임을 버린 뒤 재시작합니다. 캡처/검색 도우미는 모두 빌드·UI_MANIFEST에 포함하며 중단/부모 종료/30초 유휴 시 종료합니다. 대기 작업은 창당 1개로 제한합니다.

- 장시간 실행: 캡처 도우미는 현재 프레임 완료 후 30~34분(창별 분산)에 교체하고, 검색 도우미는 30분이 지난 뒤 검색 대기 프레임이 없을 때 교체합니다. 정상 요청에 의해 주기가 무한 연장되지 않으며 교체 중에도 점프 기한을 초기화하지 않습니다. 반복 파일 검사 자원 추이 검증과 실제 Roblox 12시간 연속 실행 검증은 구분합니다.

- 감지 후 리스폰은 25ms 타이머의 창별 단계 큐로 처리합니다. 키 누름 150ms·키 사이 최소 1800ms를 유지하며 기다리는 사이 다른 창의 단계를 처리합니다. 키 입력 중에도 캡처·검색은 계속하며 300초 점프는 열린 리스폰 단계가 끝나면 진행합니다. 중단/포커스 이탈 시 키를 해제하고 기한을 보존합니다. 사진 저장 실패가 리스폰 큐 등록을 막지 않으며 감지/입력 완료/중단은 protection.log에 기록합니다.
- 검색 제한은 큐 대기와 실제 검색을 구분합니다. `.match.started` 이후 2.5초를 검색 제한으로 적용하고, 시작 전 큐 대기는 최대 5초 또는 창수×2.5초+1초로 제한합니다. 대기 프레임을 무조건 2.5초에 폐기하지 않습니다.
