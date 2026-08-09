'use strict';

// src/helpers.ts
function getParams(params) {
  if (!params) return void 0;
  const result = {};
  if (params.expand?.length) result.expand = params.expand.join(",");
  if (params.fields?.length) result.fields = params.fields.join(",");
  return Object.keys(result).length > 0 ? result : void 0;
}
function resolveRetryConfig(retry) {
  if (retry === false) return false;
  return {
    maxRetries: retry?.maxRetries ?? 2,
    retryOnStatus: retry?.retryOnStatus ?? [429, 500, 502, 503, 504],
    baseDelay: retry?.baseDelay ?? 300,
    maxDelay: retry?.maxDelay ?? 1e4,
    retryOnNetworkError: retry?.retryOnNetworkError ?? true
  };
}

// src/params.ts
var PASSTHROUGH_KEYS = /* @__PURE__ */ new Set(["page", "limit", "expand", "sort", "fields"]);
function transformListParams(params) {
  const result = {};
  for (const [key, value] of Object.entries(params)) {
    if (value === void 0) continue;
    if (PASSTHROUGH_KEYS.has(key)) {
      result[key] = Array.isArray(value) ? value.join(",") : value;
      continue;
    }
    if (key.startsWith("q[")) {
      result[key] = value;
      continue;
    }
    if (Array.isArray(value)) {
      const base = key.endsWith("[]") ? key.slice(0, -2) : key;
      result[`q[${base}][]`] = value;
    } else {
      result[`q[${key}]`] = value;
    }
  }
  return result;
}

// src/request.ts
var PallasTradeError = class extends Error {
  code;
  status;
  details;
  constructor(response, status) {
    super(response.error.message);
    this.name = "PallasTradeError";
    this.code = response.error.code;
    this.status = status;
    this.details = response.error.details;
  }
};
function calculateDelay(attempt, config) {
  const exponentialDelay = config.baseDelay * 2 ** attempt;
  const jitter = Math.random() * config.baseDelay;
  return Math.min(exponentialDelay + jitter, config.maxDelay);
}
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
function generateIdempotencyKey() {
  return `pallastrade-sdk-retry-${crypto.randomUUID()}`;
}
function shouldRetryOnStatus(method, status, config, hasIdempotencyKey) {
  const isIdempotent = method === "GET" || method === "HEAD" || hasIdempotencyKey;
  if (isIdempotent) {
    return config.retryOnStatus.includes(status);
  }
  return status === 429;
}
function shouldRetryOnNetworkError(method, config, hasIdempotencyKey) {
  if (!config.retryOnNetworkError) return false;
  return method === "GET" || method === "HEAD" || hasIdempotencyKey;
}
function createRequestFn(config, basePath, auth, defaults) {
  return async function request(method, path, options = {}) {
    const { token, guestToken, idempotencyKey, headers = {}, body, params } = options;
    const locale = options.locale ?? defaults?.locale;
    const currency = options.currency ?? defaults?.currency;
    const country = options.country ?? defaults?.country;
    const channel = options.channel ?? defaults?.channel;
    const browserOrigin = typeof window !== "undefined" ? window.location.origin : void 0;
    const urlBase = config.baseUrl || browserOrigin;
    if (!urlBase) {
      throw new TypeError(
        "sdk-core: baseUrl is required in non-browser environments (no window.location to resolve relative URLs against)"
      );
    }
    const url = new URL(`${config.baseUrl}${basePath}${path}`, urlBase);
    if (params) {
      Object.entries(params).forEach(([key, value]) => {
        if (value !== void 0) {
          if (Array.isArray(value)) {
            for (const v of value) {
              url.searchParams.append(key, String(v));
            }
          } else {
            url.searchParams.set(key, String(value));
          }
        }
      });
    }
    const requestHeaders = {
      "Content-Type": "application/json",
      ...headers
    };
    if (auth.headerName && auth.headerValue) {
      requestHeaders[auth.headerName] = auth.headerValue;
    }
    if (token) {
      requestHeaders.Authorization = `Bearer ${token}`;
    }
    if (guestToken) {
      requestHeaders["x-pallastrade-token"] = guestToken;
    }
    if (locale) {
      requestHeaders["x-pallastrade-locale"] = locale;
    }
    if (currency) {
      requestHeaders["x-pallastrade-currency"] = currency;
    }
    if (country) {
      requestHeaders["x-pallastrade-country"] = country;
    }
    if (channel) {
      requestHeaders["x-pallastrade-channel"] = channel;
    }
    const isMutating = method !== "GET" && method !== "HEAD";
    const effectiveIdempotencyKey = idempotencyKey ?? (isMutating && config.retryConfig ? generateIdempotencyKey() : void 0);
    if (effectiveIdempotencyKey) {
      requestHeaders["Idempotency-Key"] = effectiveIdempotencyKey;
    }
    const hasIdempotencyKey = !!effectiveIdempotencyKey;
    const maxAttempts = config.retryConfig ? config.retryConfig.maxRetries + 1 : 1;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        const response = await config.fetchFn(url.toString(), {
          method,
          headers: requestHeaders,
          body: body ? JSON.stringify(body) : void 0,
          credentials: config.credentials
        });
        if (!response.ok) {
          const isLastAttempt = attempt >= maxAttempts - 1;
          if (!isLastAttempt && config.retryConfig && shouldRetryOnStatus(method, response.status, config.retryConfig, hasIdempotencyKey)) {
            const retryAfter = response.headers.get("Retry-After");
            const delay = retryAfter ? Math.min(parseInt(retryAfter, 10) * 1e3, config.retryConfig.maxDelay) : calculateDelay(attempt, config.retryConfig);
            await sleep(delay);
            continue;
          }
          const errorBody = await response.json();
          throw new PallasTradeError(errorBody, response.status);
        }
        if (response.status === 204) {
          return void 0;
        }
        if (response.status === 202) {
          const contentType = response.headers.get("content-type");
          if (contentType?.includes("application/json")) {
            return response.json();
          }
          return void 0;
        }
        return response.json();
      } catch (error) {
        if (error instanceof PallasTradeError) {
          throw error;
        }
        const isLastAttempt = attempt >= maxAttempts - 1;
        if (!isLastAttempt && config.retryConfig && shouldRetryOnNetworkError(method, config.retryConfig, hasIdempotencyKey)) {
          const delay = calculateDelay(attempt, config.retryConfig);
          await sleep(delay);
          continue;
        }
        throw error;
      }
    }
    throw new Error("Unexpected end of retry loop");
  };
}

exports.PallasTradeError = PallasTradeError;
exports.createRequestFn = createRequestFn;
exports.getParams = getParams;
exports.resolveRetryConfig = resolveRetryConfig;
exports.transformListParams = transformListParams;
//# sourceMappingURL=index.cjs.map
//# sourceMappingURL=index.cjs.map