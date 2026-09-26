// 런처(exe)를 컴파일합니다: launcher/launcher.ahk -> build/DEAN ROBLOX.exe
// Ahk2Exe 는 상대 경로를 스크립트 위치 기준으로 해석하고, 오류가 나면 창을 띄운 채 멈추기도 해서
// 절대 경로 + /silent 로 호출합니다.
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const bin = path.join(root, "node_modules", "ahk64", "bin")
// 출력 파일 이름은 첫 번째 인자로 바꿀 수 있습니다: node scripts/build-launcher.mjs "DEAN ROBLOX v1.2.exe"
const out = path.join(root, "build", process.argv[2] || "DEAN ROBLOX.exe")
fs.mkdirSync(path.dirname(out), { recursive: true })

const result = spawnSync(
	path.join(bin, "Ahk2Exe.exe"),
	[
		"/silent",
		"verbose",
		"/base",
		path.join(bin, "AutoHotkey64.exe"),
		"/in",
		path.join(root, "launcher", "launcher.ahk"),
		"/out",
		out,
		"/icon",
		path.join(root, "app.ico"),
		"/compress",
		"0",
	],
	{ stdio: "inherit" },
)

if (result.status !== 0 || !fs.existsSync(out)) {
	console.error("launcher build failed")
	process.exit(1)
}
console.log(`launcher built: ${out}`)
