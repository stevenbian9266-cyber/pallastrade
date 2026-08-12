import { type Client, createClient } from "@pallastrade/sdk";
import type { PallasTradeNextConfig } from "./types";

/**
 * 单次 Store API 请求超时（毫秒）。
 *
 * 背景（修复：storefront API 请求缺超时导致预渲染挂起/构建失败）：
 * SDK 对 GET 网络错误默认指数退避重试（maxRetries=2），且 fetch 本身无超时。
 * 当 API 不可达（如部署/重建期间、DNS/网络故障），单个请求可挂起数分钟，
 * 导致 Next.js 预渲染 "use cache" 缓存填充超时（USE_CACHE_TIMEOUT）→ 构建失败、
 * SSR 长时间阻塞。此处为每次请求注入 AbortSignal.timeout，快速失败并走上层降级。
 */
const API_FETCH_TIMEOUT_MS = 8_000;

/**
 * 包装 fetch，为每次请求附加 AbortSignal.timeout 超时。
 * SDK 调用 fetch 时不传 signal，因此这里注入的 signal 不会被覆盖。
 */
export function createFetchWithTimeout(
  timeoutMs: number = API_FETCH_TIMEOUT_MS,
  fetchFn: typeof fetch = fetch,
): typeof fetch {
  return (input, init) =>
    fetchFn(input, {
      ...init,
      signal: AbortSignal.timeout(timeoutMs),
    });
}

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
    fetch: createFetchWithTimeout(),
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
