/// <reference types="vitest" />
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.ts',
  },
  server: {
    allowedHosts: true,
    proxy: {
      '/auth': {
        target: 'http://backend:8080',
        changeOrigin: true,
      },
      '/sessions': {
        target: 'http://backend:8080',
        changeOrigin: true,
      },
      '/ws': {
        target: 'ws://backend:8080',
        ws: true,
      },
      '/boundary': {
        target: 'http://controller:9200',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/boundary/, ''),
      },
    },
  },
})
