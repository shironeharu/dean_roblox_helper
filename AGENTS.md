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

- `session-unlocker.ahk`: 앱 시작 구간에서 include하는 Windows x64 멀티 실행 모듈. 실행 수 제한 없이 기존 Roblox의 `ROBLOX_singletonEvent`만 해제하고 한 번에 하나씩 추가 실행합니다. 클래스 초기화가 있으므로 auto-execute의 `return` 뒤에 include하지 않습니다.
- 잠수도우미는 선택한 HWND/PID 목록을 순회합니다. 일부 창이 닫혀도 나머지는 계속 실행합니다. 채팅 한/영 기억값은 HWND/PID별로 관리하며 입력을 다른 창에 복제하지 않습니다.
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
