// vite.config.js
import { defineConfig } from "vite"
import tailwindcss from "@tailwindcss/vite"
import injectHTML from "vite-plugin-html-inject"
import { readFileSync } from "node:fs"

export default defineConfig({
	root: "frontend",
	base: "./",
	plugins: [tailwindcss(), injectHTML(), {
		name: "app-version",
		transformIndexHtml(html) {
			if (!html.includes("%DEAN_VERSION%")) return html
			const version = readFileSync(new URL("./version.txt", import.meta.url), "utf8").trim()
			if (!/^\d+(?:\.\d+)*$/.test(version)) throw new Error("Invalid version.txt")
			return html.replace("%DEAN_VERSION%", version)
		},
	}],
	build: {
		outDir: "../dist",
		emptyOutDir: true,
		rollupOptions: {
			input: { main: "frontend/index.html", login: "frontend/login.html", shortcuts: "frontend/chat-shortcuts.html" },
			output: {
				// fixed name for the main JavaScript bundle
				entryFileNames: "assets/app.js",
				// fixed name for dynamic chunks
				chunkFileNames: "assets/[name].js",
				// fixed name for emitted CSS and other assets
				assetFileNames: (assetInfo) => {
					if (
						assetInfo.names[0] &&
						assetInfo.names[0].endsWith(".css")
					) {
						return "assets/app.css" // single fixed CSS filename
					}
					return "assets/[name].[ext]" // images, fonts, etc.
				},
			},
		},
	},
})
