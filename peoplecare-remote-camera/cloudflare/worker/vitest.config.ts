import { defineConfig } from "vitest/config";
import { cloudflareTest } from "@cloudflare/vitest-plugin";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        // Test-only values: no real credential is ever used by the test suite.
        // Cloudflare API calls are intercepted by a fetch mock (test/helpers.ts).
        bindings: {
          CONTROL_ROOM_PASSWORD: "test-password-0123",
          CLOUDFLARE_ACCOUNT_ID: "test-account-id",
          CLOUDFLARE_API_TOKEN: "test-api-token",
          CLOUDFLARE_API_BASE: "https://cf-api.test/client/v4",
          STREAM_WEBHOOK_SECRET: "test-webhook-secret",
          CLOUDFLARE_STREAM_CUSTOMER_CODE: "testcustomer123",
          CF_WATCHDOG: "true",
        },
      },
    }),
  ],
  server: {
    fs: {
      allow: ["../.."],
    },
  },
  test: {
    include: ["test/**/*.spec.ts"],
  },
});
