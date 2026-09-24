import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

const protocolPath = fileURLToPath(new URL("../../cloudflare/worker/src/shared/protocol.ts", import.meta.url));
const workerUrl = process.env.CONTROL_PLANE_DEV_URL ?? "http://localhost:8787";

export default defineConfig({
  resolve: {
    alias: { "@protocol": protocolPath },
  },
  esbuild: {
    jsx: "automatic",
    jsxImportSource: "preact",
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: false,
    target: "es2022",
  },
  server: {
    port: 5173,
    fs: { allow: ["../.."] },
    // During development the Worker runs with `wrangler dev` on :8787.
    proxy: {
      "/api": { target: workerUrl, changeOrigin: false },
      "/ws": { target: workerUrl, ws: true, changeOrigin: false },
    },
  },
  test: {
    include: ["test/**/*.spec.ts"],
    environment: "node",
  },
});
