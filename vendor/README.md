# vendor

`dean.dll`의 실행 엔진(런타임)으로 쓰는 외부 바이너리입니다.

| 파일 | 출처 | 버전 |
|---|---|---|
| `AutoHotkey64.dll` | https://github.com/thqby/AutoHotkey_H/releases/tag/v2.0.25 (`v2.0.25.7z` 안의 `AutoHotkey64.dll`) | AutoHotkey_H v2.0.25 |

- `AutoHotkey_H-license.txt`: 해당 프로젝트의 라이선스 (GPL-2.0)
- 원본 압축 파일 `v2.0.25.7z` SHA256: `07dfd5c8b1fecb6ff0198b1045c97ee3697ce7819bfaab8d6c946379f67f1c76`
- `AutoHotkey64.dll` SHA256: `1f36ee7d22fd5aa96441b88159b7d9bb505e972c4e9a864565b984524cafb229`

`npm run build:core`는 이 dll을 복사한 뒤 앱 스크립트·화면 파일을 리소스로 넣어 `build/dean.dll`을 만듭니다.
버전을 올릴 때는 위 해시를 릴리스 페이지에서 직접 확인한 뒤 교체하세요.
