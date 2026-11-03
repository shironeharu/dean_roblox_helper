import fs from "node:fs"
import path from "node:path"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const source = path.join(root, "window-capture.cs")
const output = path.join(root, "frontend/public/assets/dean-window-capture.exe")
const compiler = path.join(process.env.WINDIR || "C:/Windows", "Microsoft.NET/Framework64/v4.0.30319/csc.exe")
fs.mkdirSync(path.dirname(output), { recursive: true })
if (!fs.existsSync(output) || fs.statSync(source).mtimeMs > fs.statSync(output).mtimeMs) {
	const result = spawnSync(compiler, ["/nologo", "/target:winexe", "/platform:x64", "/optimize+", "/reference:System.Drawing.dll", `/out:${output}`, source], { stdio: "inherit", windowsHide: true })
	if (result.status !== 0) process.exit(result.status || 1)
}
console.log("window capture helper ready")

const matcherOutput = path.join(root, "frontend/public/assets/dean-warning-match.exe")
const matcherSources = ["warning-match-worker.ahk", "warning-matcher.ahk", "robbery-patterns.ahk", "vendor/FindText.ahk"]
if (!fs.existsSync(matcherOutput) || matcherSources.some(file => fs.statSync(path.join(root, file)).mtimeMs > fs.statSync(matcherOutput).mtimeMs)) {
	const bin = path.join(root, "node_modules/ahk64/bin")
	const result = spawnSync(path.join(bin, "Ahk2Exe.exe"), ["/silent", "verbose", "/base", path.join(bin, "AutoHotkey64.exe"), "/in", path.join(root, "warning-match-worker.ahk"), "/out", matcherOutput, "/compress", "0"], { stdio: "inherit", windowsHide: true })
	if (result.status !== 0 || !fs.existsSync(matcherOutput)) process.exit(result.status || 1)
}
console.log("isolated warning matcher ready")
