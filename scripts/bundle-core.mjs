// app.ahk 와 #Include 된 파일들을 하나의 스크립트 텍스트로 합칩니다.
// dean.dll 안에는 스크립트가 파일이 아니라 텍스트로 들어가서 NewThread()로 실행되므로
// #Include 를 미리 펼쳐 둬야 합니다.
//
// 사용법: node scripts/bundle-core.mjs <입력 app.ahk> <출력 파일>
import fs from "node:fs"
import path from "node:path"

const [, , inputArg, outputArg] = process.argv
if (!inputArg || !outputArg) {
	console.error("usage: node scripts/bundle-core.mjs <app.ahk> <output>")
	process.exit(1)
}

const seen = new Set()

function expand(file) {
	const base = path.dirname(file)
	const lines = fs.readFileSync(file, "utf8").replace(/^﻿/, "").split(/\r?\n/)
	const out = []
	let skip = false

	for (const line of lines) {
		const trimmed = line.trim()

		// 개발 전용 구간(Ahk2Exe-IgnoreBegin ~ IgnoreEnd)은 코어에 넣지 않음 (F6 종료 핫키 등)
		if (/^;@Ahk2Exe-IgnoreBegin/i.test(trimmed)) { skip = true; continue }
		if (/^;@Ahk2Exe-IgnoreEnd/i.test(trimmed)) { skip = false; continue }
		if (skip) continue

		// 단일 인스턴스 처리는 런처(exe)가 담당
		if (/^#SingleInstance/i.test(trimmed)) continue

		const include = /^#Include\s+(.+)$/i.exec(trimmed)
		if (include) {
			const target = path.resolve(base, include[1].trim().replace(/\\/g, path.sep))
			// 컴파일용 리소스 목록(자동 생성 파일)은 코어에 필요 없음
			if (path.basename(target).toLowerCase() === "resource.ahk") continue
			const key = target.toLowerCase()
			if (seen.has(key)) continue
			seen.add(key)
			out.push(expand(target))
			continue
		}
		out.push(line)
	}
	return out.join("\n")
}

const input = path.resolve(inputArg)
seen.add(input.toLowerCase())
const text = expand(input)
fs.mkdirSync(path.dirname(path.resolve(outputArg)), { recursive: true })
fs.writeFileSync(path.resolve(outputArg), text, "utf8")
console.log(`bundled ${text.split("\n").length} lines -> ${outputArg}`)
