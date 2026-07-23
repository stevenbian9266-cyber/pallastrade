/** Serialize expand/fields arrays into comma-separated query params */
export function getParams(params) {
  if (!params) return undefined
  const result = {}
  if (params.expand?.length) result.expand = params.expand.join(',')
  if (params.fields?.length) result.fields = params.fields.join(',')
  return Object.keys(result).length > 0 ? result : undefined
}
export function resolveRetryConfig(retry) {
  if (retry === false) return false
  return {
    maxRetries: retry?.maxRetries ?? 2,
    retryOnStatus: retry?.retryOnStatus ?? [429, 500, 502, 503, 504],
    baseDelay: retry?.baseDelay ?? 300,
    maxDelay: retry?.maxDelay ?? 10000,
    retryOnNetworkError: retry?.retryOnNetworkError ?? true,
  }
}
//# sourceMappingURL=helpers.js.map
