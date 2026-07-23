/**
 * Keys that are passed through to the API without wrapping in q[...].
 */
const PASSTHROUGH_KEYS = new Set(['page', 'limit', 'expand', 'sort', 'fields'])
/**
 * Transforms flat SDK params into Ransack-compatible query params.
 *
 * - `page`, `limit`, `expand`, `sort` pass through unchanged
 * - Keys already in `q[...]` format pass through (backward compat)
 * - All other keys are wrapped: `name_cont` → `q[name_cont]`
 */
export function transformListParams(params) {
  const result = {}
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined) continue
    if (PASSTHROUGH_KEYS.has(key)) {
      // Join arrays for passthrough keys (e.g., expand: ['variants', 'media'] → 'variants,media')
      result[key] = Array.isArray(value) ? value.join(',') : value
      continue
    }
    // Backward compat: already-wrapped q[...] keys pass through
    if (key.startsWith('q[')) {
      result[key] = value
      continue
    }
    // Array values get [] suffix automatically: `foo: [1,2]` → `q[foo][]`
    if (Array.isArray(value)) {
      const base = key.endsWith('[]') ? key.slice(0, -2) : key
      result[`q[${base}][]`] = value
    } else {
      result[`q[${key}]`] = value
    }
  }
  return result
}
//# sourceMappingURL=params.js.map
