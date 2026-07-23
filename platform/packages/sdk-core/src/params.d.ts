type ParamValue = string | number | boolean | (string | number)[] | undefined
/**
 * Transforms flat SDK params into Ransack-compatible query params.
 *
 * - `page`, `limit`, `expand`, `sort` pass through unchanged
 * - Keys already in `q[...]` format pass through (backward compat)
 * - All other keys are wrapped: `name_cont` → `q[name_cont]`
 */
export declare function transformListParams(
  params: Record<string, unknown>,
): Record<string, ParamValue>
export {}
//# sourceMappingURL=params.d.ts.map
