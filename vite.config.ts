import { defineConfig } from 'vite'
import { readFileSync, existsSync, cpSync } from 'fs'
import { resolve } from 'path'

export default defineConfig({
  publicDir: 'public',
  server: {
    fs: {
      allow: ['..'],
    },
  },
  build: {
    outDir: 'dist',
  },
  plugins: [
    {
      name: 'serve-examples',
      configureServer(server) {
        // Dev: serve /examples/* and /lib/* from source
        server.middlewares.use('/examples', (req, res, next) => {
          const filePath = resolve(__dirname, 'examples', req.url?.slice(1) || '')
          if (existsSync(filePath)) {
            res.setHeader('Content-Type', 'text/plain; charset=utf-8')
            res.end(readFileSync(filePath, 'utf-8'))
          } else {
            next()
          }
        })
        server.middlewares.use('/lib', (req, res, next) => {
          const filePath = resolve(__dirname, 'lib', req.url?.slice(1) || '')
          if (existsSync(filePath)) {
            res.setHeader('Content-Type', 'text/plain; charset=utf-8')
            res.end(readFileSync(filePath, 'utf-8'))
          } else {
            next()
          }
        })
      },
      closeBundle() {
        // Build: copy examples/ and lib/ to dist/
        cpSync('examples', 'dist/examples', { recursive: true })
        cpSync('lib', 'dist/lib', { recursive: true })
        console.log('Copied examples/ and lib/ to dist/')
      },
    },
  ],
})
