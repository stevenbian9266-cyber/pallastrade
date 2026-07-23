/** Serialize expand/fields arrays into comma-separated query params */
export declare function getParams(params?: {
  expand?: string[]
  fields?: string[]
}): Record<string, string> | undefined
/** Resolve retry config with defaults */
export interface ResolvedRetryConfig {
  maxRetries: number
  retryOnStatus: number[]
  baseDelay: number
  maxDelay: number
  retryOnNetworkError: boolean
}
export declare function resolveRetryConfig(
  retry?: import('./request').RetryConfig | false,
): ResolvedRetryConfig | false
//# sourceMappingURL=helpers.d.ts.map
