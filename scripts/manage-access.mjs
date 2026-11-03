import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const idPattern = /^DEAN-(?:[A-F0-9]{8}-){3}[A-F0-9]{8}$/

export function normalizeId(value) {
	const id = String(value || "").trim().toUpperCase()
	if (!idPattern.test(id)) throw new Error("PC ID 형식이 올바르지 않습니다")
	return id
}

export function validateName(value) {
	const name = String(value || "").trim().normalize("NFC")
	if (!name || [...name].length > 24 || /[\p{Cc}\p{Cf}|<>]/u.test(name)) throw new Error("이름은 제어문자 없는 1~24자로 입력하세요")
	return name
}

export function expiryUtc(value) {
	if (!value) return "-"
	if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("만료일은 YYYY-MM-DD 또는 빈칸으로 입력하세요")
	const date = new Date(`${value}T00:00:00.000Z`)
	if (!Number.isFinite(date.valueOf()) || date.toISOString().slice(0, 10) !== value || Number(value.slice(0, 4)) < 2020) throw new Error("유효하지 않은 만료일입니다")
	// The selected Korean date remains valid until 23:59:59 KST.
	return new Date(date.valueOf() + (15 * 60 * 60 - 1) * 1000).toISOString().replace(/[-:T]/g, "").slice(0, 14)
}

export function validateRegistry(registry) {
	if (registry?.schema !== 1 || !Array.isArray(registry.devices) || registry.devices.length > 1000) throw new Error("등록 목록 형식이 올바르지 않습니다")
	const seen = new Set()
	for (const device of registry.devices) {
		if (!device || typeof device.id !== "string" || typeof device.name !== "string" || typeof device.expires !== "string") throw new Error("등록 항목 형식이 올바르지 않습니다")
		const id = normalizeId(device.id)
		if (device.id !== id) throw new Error("저장된 PC ID는 대문자 표준 형식이어야 합니다")
		if (seen.has(id)) throw new Error("중복 PC ID가 있습니다")
		seen.add(id)
		validateName(device.name)
		expiryUtc(device.expires)
		if (typeof device.blocked !== "boolean") throw new Error("차단 여부가 올바르지 않습니다")
	}
	return registry
}

export function updateRegistry(input, values) {
	const registry = structuredClone(validateRegistry(input))
	const action = values.action || "list"
	if (action === "list") return registry
	const id = normalizeId(values.id)
	const existing = registry.devices.find(device => device.id === id)
	if (action === "upsert") {
		const name = validateName(values.name)
		const expires = String(values.expires || "").trim()
		expiryUtc(expires)
		if (values.blocked !== "true" && values.blocked !== "false") throw new Error("차단 값이 올바르지 않습니다")
		const device = { id, name, blocked: values.blocked === "true", expires }
		if (existing) Object.assign(existing, device)
		else registry.devices.push(device)
	} else if (action === "block" || action === "unblock") {
		if (!existing) throw new Error("등록된 PC가 아닙니다. 먼저 등록/수정으로 추가하세요")
		existing.blocked = action === "block"
	} else throw new Error("알 수 없는 관리 작업입니다")
	registry.devices.sort((a, b) => a.id.localeCompare(b.id))
	return validateRegistry(registry)
}

export function renderAllowlist(registry) {
	validateRegistry(registry)
	return "DEAN_ACCESS_V1\n" + registry.devices.map(device => [
		device.id, device.blocked ? "1" : "0", expiryUtc(device.expires), Buffer.from(device.name, "utf8").toString("base64"),
	].join("|")).join("\n") + (registry.devices.length ? "\n" : "")
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const registryFile = path.join(root, "access/registry.json")
	const registry = updateRegistry(JSON.parse(fs.readFileSync(registryFile, "utf8")), {
		action: process.env.ACCESS_ACTION,
		id: process.env.ACCESS_PC_ID,
		name: process.env.ACCESS_NAME,
		expires: process.env.ACCESS_EXPIRES,
		blocked: process.env.ACCESS_BLOCKED || "false",
	})
	fs.writeFileSync(registryFile, JSON.stringify(registry, null, 2) + "\n")
	fs.writeFileSync(path.join(root, "access/allowlist.txt"), renderAllowlist(registry))
	if (process.env.GITHUB_STEP_SUMMARY) {
		const escape = value => String(value).replace(/[\\`*_[\]<>|]/g, "\\$&")
		const rows = registry.devices.map(device => `| ${escape(device.name)} | \`${device.id}\` | ${device.blocked ? "차단" : "허용"} | ${device.expires || "무기한"} |`)
		fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## PC 등록 목록\n\n| 이름 | PC ID | 상태 | 만료일(KST) |\n| --- | --- | --- | --- |\n${rows.join("\n")}\n`)
	}
	console.log(`PC 등록 목록 ${registry.devices.length}개 처리 완료`)
}
