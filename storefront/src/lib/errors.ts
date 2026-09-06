/**
 * BFF/API 错误消息归一化（client-safe：无 server-only 依赖，可被 "use client"
 * 组件与测试直接引用）。
 *
 * 统一错误契约（与后端 v3 error envelope 对齐，见 pallastrade-api-v3 skill
 * "Error responses" + backend error_handler#render_error）：
 *
 *   { "error": { "code": string, "message": string } }
 *
 * 兼容历史/第三方形状（string、{ error: string }、直接 { message }）——
 * extractErrorMessage 逐层降级解析，normalizeErrorMessage 保证永远返回 string。
 *
 * 背景（bugfix 2026-09-06）：UnifiedCheckout handlePayNow 曾把后端 404 的
 * 对象错误体 `{ error: { code, message } }` 直接传给 sonner toast.error()，
 * sonner 尝试把对象渲染为 React 子节点 → React error #31 → global-error 整页
 * 白屏。UI 展示前必须经此归一化，禁止把 unknown/object 直接交给 toast/JSX。
 */

/** 结构化错误体 { error: { code, message } }（后端 v3 契约）。 */
interface StructuredErrorEnvelope {
  code?: unknown;
  message?: unknown;
}

function asNonEmptyString(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim().length > 0) return value.trim();
  return undefined;
}

/**
 * 从任意错误值提取可展示的字符串消息；取不到返回 undefined。
 * 兼容形状（按优先级）：
 *   1. string
 *   2. Error（读 .message）
 *   3. { error: { message } }          ← 后端 v3 / BFF 统一契约
 *   4. { error: "string" }
 *   5. { message: "string" }
 */
export function extractErrorMessage(value: unknown): string | undefined {
  const asString = asNonEmptyString(value);
  if (asString) return asString;

  if (value instanceof Error) {
    const message = asNonEmptyString(value.message);
    if (message) return message;
  }

  if (value && typeof value === "object") {
    const obj = value as Record<string, unknown>;
    const err = obj.error;

    // { error: { code, message } }
    if (err && typeof err === "object") {
      const structured = err as StructuredErrorEnvelope;
      const message = asNonEmptyString(structured.message);
      if (message) return message;
    }
    // { error: "string" }
    const errorAsString = asNonEmptyString(err);
    if (errorAsString) return errorAsString;
    // 直接 { message: "string" }
    const message = asNonEmptyString(obj.message);
    if (message) return message;
  }

  return undefined;
}

/**
 * toast/UI 展示的唯一出口：永远返回 string。
 * 取不到可读消息时回退到调用方提供的 fallback（i18n key 已解析的文案）。
 */
export function normalizeErrorMessage(
  value: unknown,
  fallback: string,
): string {
  return extractErrorMessage(value) ?? fallback;
}
