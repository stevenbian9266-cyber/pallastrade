import { type Client, createClient } from "@pallastrade/sdk";
import type { PallasTradeNextConfig } from "./types";

let _client: Client | null = null;
let _config: PallasTradeNextConfig | null = null;

/**
 * Initialize the PallasTrade Next.js integration.
 * Call this once in your app (e.g., in `lib/storefront.ts`).
 * If not called, the client will auto-initialize from PALLASTRADE_API_URL and PALLASTRADE_PUBLISHABLE_KEY env vars.
 */
export function initPallasTradeNext(config: PallasTradeNextConfig): void {
  _config = config;
  _client = createClient({
    baseUrl: config.baseUrl,
    publishableKey: config.publishableKey,
  });
}

/**
 * Get the Client instance. Auto-initializes from env vars if needed.
 */
export function getClient(): Client {
  if (!_client) {
    const baseUrl = process.env.PALLASTRADE_API_URL;
    const publishableKey = process.env.PALLASTRADE_PUBLISHABLE_KEY;
    if (baseUrl && publishableKey) {
      initPallasTradeNext({ baseUrl, publishableKey });
    } else {
      throw new Error(
        "PallasTrade client is not configured. Either call initPallasTradeNext() or set PALLASTRADE_API_URL and PALLASTRADE_PUBLISHABLE_KEY environment variables.",
      );
    }
  }
  return _client!;
}

/**
 * Get the current config. Auto-initializes from env vars if needed.
 */
export function getConfig(): PallasTradeNextConfig {
  if (!_config) {
    getClient(); // triggers auto-init
  }
  return _config!;
}

/**
 * Reset the client (useful for testing).
 */
export function resetClient(): void {
  _client = null;
  _config = null;
}
