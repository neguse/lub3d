import { defineConfig } from "vite";
import { readFileSync, existsSync, cpSync, copyFileSync } from "fs";
import { resolve, extname } from "path";

const textExts = new Set([
  ".lua",
  ".json",
  ".txt",
  ".md",
  ".csv",
  ".xml",
  ".html",
  ".js",
  ".ts",
  ".glsl",
]);

export default defineConfig({
  publicDir: "public",
  server: {
    fs: {
      allow: [".."],
    },
  },
  build: {
    outDir: "dist",
  },
  plugins: [
    {
      name: "serve-examples",
      configureServer(server) {
        // Serve files with correct Content-Type (binary-safe for WAV etc.)
        function serveDir(prefix: string, baseDir: string) {
          server.middlewares.use(prefix, (req, res, next) => {
            const filePath = resolve(baseDir, req.url?.slice(1) || "");
            if (!existsSync(filePath)) return next();
            const ext = extname(filePath).toLowerCase();
            if (textExts.has(ext)) {
              res.setHeader("Content-Type", "text/plain; charset=utf-8");
              res.end(readFileSync(filePath, "utf-8"));
            } else {
              res.setHeader("Content-Type", "application/octet-stream");
              res.end(readFileSync(filePath));
            }
          });
        }
        serveDir("/examples", resolve(__dirname, "examples"));
        serveDir("/lib", resolve(__dirname, "lib"));
        serveDir("/deps", resolve(__dirname, "deps"));
        // Dev: serve doc.json
        server.middlewares.use("/doc.json", (_req, res, next) => {
          const filePath = resolve(__dirname, "doc.json");
          if (existsSync(filePath)) {
            res.setHeader("Content-Type", "application/json; charset=utf-8");
            res.end(readFileSync(filePath, "utf-8"));
          } else {
            next();
          }
        });
      },
      closeBundle() {
        // Build: copy examples/, lib/, and doc.json to dist/
        cpSync("examples", "dist/examples", { recursive: true });
        cpSync("lib", "dist/lib", { recursive: true });
        cpSync("deps/lume", "dist/deps/lume", { recursive: true });
        if (existsSync("doc.json")) {
          copyFileSync("doc.json", "dist/doc.json");
          console.log("Copied doc.json to dist/");
        }
        console.log("Copied examples/ and lib/ to dist/");
      },
    },
  ],
});
