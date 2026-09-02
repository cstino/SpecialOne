import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    host: true,
    port: 5173,
    // Permette di testare da reti diverse da quella di casa tramite un
    // tunnel cloudflared temporaneo (sottodominio nuovo ogni volta).
    allowedHosts: ['.trycloudflare.com'],
  },
})
