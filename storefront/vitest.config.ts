import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": resolve(__dirname, "./src"),
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/__tests__/setup.tsx"],
    include: ["src/**/*.test.{ts,tsx}"],
    // Coverage gate — consumed by `harness coverage` (pallastrade-harness package)
    // and the harness-full.yml `coverage` CI job. Thresholds live in
    // harness/config.json (coverage.thresholds.storefront).
    coverage: {
      provider: "v8",
      include: ["src/**/*.{ts,tsx}"],
      exclude: [
        "src/**/*.test.{ts,tsx}",
        "src/**/__tests__/**",
        "src/generated/**",
      ],
      reporter: ["text", "json-summary"],
    },
  },
});
