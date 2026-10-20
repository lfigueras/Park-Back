import { defineConfig, loadEnv } from "vite"
import react from "@vitejs/plugin-react"

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "VITE_")

  return {
    base: env.VITE_BASE_PATH || "/",
    plugins: [react()],
    build: {
      outDir: "dist",
      emptyOutDir: true,
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (id.includes("/node_modules/@firebase/")) return "firebase"
            if (id.includes("/node_modules/react-leaflet/") || id.includes("/node_modules/leaflet/")) return "maps"
            if (id.includes("/node_modules/react/") || id.includes("/node_modules/react-dom/")) return "react"
          },
        },
      },
    },
  }
})
