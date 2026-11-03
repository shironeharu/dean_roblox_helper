import test from "node:test"
import assert from "node:assert/strict"
import { normalizeId, validateName, expiryUtc, updateRegistry, renderAllowlist } from "./manage-access.mjs"

const id = "DEAN-01234567-89ABCDEF-01234567-89ABCDEF"
const empty = { schema: 1, devices: [] }

test("register, rename, expiry and block transitions", () => {
	const registered = updateRegistry(empty, { action: "upsert", id: id.toLowerCase(), name: "딘 테스트", expires: "2026-11-30", blocked: "false" })
	assert.equal(empty.devices.length, 0)
	assert.equal(registered.devices[0].id, id)
	assert.match(renderAllowlist(registered), /\|0\|20261130145959\|/)
	assert.equal(updateRegistry(registered, { action: "block", id }).devices[0].blocked, true)
	const unblocked = updateRegistry(updateRegistry(registered, { action: "block", id }), { action: "unblock", id })
	assert.equal(unblocked.devices[0].blocked, false)
	const renamed = updateRegistry(unblocked, { action: "upsert", id, name: "새 이름", expires: "", blocked: "true" })
	assert.equal(renamed.devices.length, 1)
	assert.equal(renamed.devices[0].name, "새 이름")
	assert.match(renderAllowlist(renamed), /\|1\|-\|/)
})

test("Korean expiry includes the entire selected day", () => {
	assert.equal(expiryUtc("2028-02-29"), "20280229145959")
	assert.equal(expiryUtc(""), "-")
	for (const invalid of ["2026-02-29", "2026-02-30", "2026-13-01", "26-11-03", "$(whoami)"])
		assert.throws(() => expiryUtc(invalid))
})

test("malformed identifiers, names and unexpected actions fail before publishing", () => {
	for (const invalid of ["", id + "\nother", "DEAN-1234", "$(whoami)"])
		assert.throws(() => normalizeId(invalid))
	for (const invalid of ["", "a\nb", "<script>", "x|y", "a".repeat(25)])
		assert.throws(() => validateName(invalid))
	assert.throws(() => updateRegistry(empty, { action: "block", id }))
	assert.throws(() => updateRegistry(empty, { action: "delete", id }))
	assert.throws(() => updateRegistry(empty, { action: "upsert", id, name: "딘", blocked: "maybe" }))
})

test("manifest contains encoded display names and rejects duplicate entries", () => {
	const registered = updateRegistry(empty, { action: "upsert", id, name: "별명 😀", expires: "", blocked: "false" })
	const fields = renderAllowlist(registered).trim().split("\n")[1].split("|")
	assert.equal(Buffer.from(fields[3], "base64").toString("utf8"), "별명 😀")
	assert.throws(() => renderAllowlist({ schema: 1, devices: [...registered.devices, ...registered.devices] }))
})
