import { defineConfig } from 'vite'
import { readFileSync, existsSync, cpSync, copyFileSync } from 'fs'
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
        server.middlewares.use('/deps', (req, res, next) => {
          const filePath = resolve(__dirname, 'deps', req.url?.slice(1) || '')
          if (existsSync(filePath)) {
            res.setHeader('Content-Type', 'text/plain; charset=utf-8')
            res.end(readFileSync(filePath, 'utf-8'))
          } else {
            next()
          }
        })
        // Dev: serve doc.json
        server.middlewares.use('/doc.json', (_req, res, next) => {
          const filePath = resolve(__dirname, 'doc.json')
          if (existsSync(filePath)) {
            res.setHeader('Content-Type', 'application/json; charset=utf-8')
            res.end(readFileSync(filePath, 'utf-8'))
          } else {
            next()
          }
        })
      },
      closeBundle() {
        // Build: copy examples/, lib/, and doc.json to dist/
        cpSync('examples', 'dist/examples', { recursive: true })
        cpSync('lib', 'dist/lib', { recursive: true })
        cpSync('deps/lume', 'dist/deps/lume', { recursive: true })
        if (existsSync('doc.json')) {
          copyFileSync('doc.json', 'dist/doc.json')
          console.log('Copied doc.json to dist/')
        }
        console.log('Copied examples/ and lib/ to dist/')
      },
    },
  ],
})
