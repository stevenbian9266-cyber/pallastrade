/**
 * Wraps a server action in a try/catch that returns a standardized
 * { success: true, ...data } | { success: false, error: string, code?: string } result.
 *
 * `code`（PRD-20260914-checkout B2 FR-007）：Store API v3 错误信封
 * `{ error: { code, message } }` 的机器可读错误码，供 UI 映射 i18n 文案
 * （如 store_credit_not_available / store_credit_gift_card_conflict）。
 * 鸭子类型提取（不 instanceof PallasTradeError）：保持 utils 零依赖，
 * 避免 client 侧因引入 SDK 而带上服务端代码。
 */
export async function actionResult<T extends Record<string, unknown>>(
  fn: () => Promise<T>,
  fallbackMessage: string,
): Promise<
  ({ success: true } & T) | { success: false; error: string; code?: string }
> {
  try {
    const result = await fn();
    return { success: true, ...result };
  } catch (error) {
    const code = errorCodeOf(error);
    return {
      success: false,
      error: error instanceof Error ? error.message : fallbackMessage,
      ...(code ? { code } : {}),
    };
  }
}

/** Store API v3 错误信封里的结构化错误码（取不到 → undefined）。 */
function errorCodeOf(error: unknown): string | undefined {
  if (!error || typeof error !== "object" || !("code" in error))
    return undefined;

  const code = (error as { code?: unknown }).code;
  return typeof code === "string" && code.trim().length > 0 ? code : undefined;
}

/**
 * Wraps a server action in a try/catch that returns a fallback value on error.
 */
export async function withFallback<T>(
  fn: () => Promise<T>,
  fallback: T,
): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    console.error(error);
    return fallback;
  }
}
