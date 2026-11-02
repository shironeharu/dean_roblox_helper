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
