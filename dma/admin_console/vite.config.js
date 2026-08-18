import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const PORT = process.env.VITE_PORT || process.env.PORT || 3000;
const SERVER_URL = process.env.VITE_SERVER_URL || 'http://localhost:9000';

export default defineConfig({
  plugins: [react()],
  build: {
    target: 'es2015'
  },
  server: {
    port: parseInt(PORT, 10),
    strictPort: false, // Auto-find next available port if 3000 is occupied
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: SERVER_URL,
        changeOrigin: true
      },
      '/ws': {
        target: SERVER_URL.replace('http', 'ws'),
        ws: true,
        changeOrigin: true
      }
    }
  }
})
