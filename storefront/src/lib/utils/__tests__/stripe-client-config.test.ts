import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config 切片2）——
// 前端密钥下发双读迁移：**先读服务端 client_config，回落构建期 NEXT_PUBLIC_***。
// 目标：换支付商 / 换环境 = 后台改配置即生效（不再重建镜像）。
import {
  getStripePromise,
  isStripeConfigured,
  type PaymentClientConfig,
  resolveStripePublishableKey,
  STRIPE_DEVELOPER_TOOLS_DISABLED,
} from "@/lib/utils/stripe";

const loadStripeMock = vi.fn();

vi.mock("@stripe/stripe-js", () => ({
  loadStripe: (...args: unknown[]) => loadStripeMock(...args),
}));

function apiConfig(publishableKey: string): PaymentClientConfig {
  return {
    provider: "stripe",
    environment: "live",
    publishable: { publishable_key: publishableKey },
    session_token: null,
  };
}

describe("D10 stripe client config (dual read)", () => {
  beforeEach(() => {
    loadStripeMock.mockReset();
    loadStripeMock.mockImplementation(() => Promise.resolve({ id: "stripe" }));
    vi.unstubAllEnvs();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  // PRD-20260915-payments-d10-client-config AC-006
  it("prefers the service-provided publishable key over the build-time env value", () => {
    vi.stubEnv("NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY", "pk_env_fallback");

    expect(resolveStripePublishableKey(apiConfig("pk_api_primary"))).toBe(
      "pk_api_primary",
    );
  });

  // PRD-20260915-payments-d10-client-config AC-006
  it("falls back to NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY during the migration window", () => {
    vi.stubEnv("NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY", "pk_env_fallback");

    expect(resolveStripePublishableKey(null)).toBe("pk_env_fallback");
    expect(resolveStripePublishableKey({ publishable: {} })).toBe(
      "pk_env_fallback",
    );
    expect(
      resolveStripePublishableKey({ publishable: { publishable_key: "  " } }),
    ).toBe("pk_env_fallback");
  });

  // PRD-20260915-payments-d10-client-config AC-007
  it("reports not-configured (and resolves to null) when neither source has a key", async () => {
    vi.stubEnv("NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY", "");

    expect(resolveStripePublishableKey(null)).toBeNull();
    expect(isStripeConfigured(null)).toBe(false);
    await expect(getStripePromise(null)).resolves.toBeNull();
    expect(loadStripeMock).not.toHaveBeenCalled();
  });

  // PRD-20260915-payments-d10-client-config AC-006
  it("lazily loads Stripe.js once per publishable key", async () => {
    const config = apiConfig("pk_api_cached");

    await getStripePromise(config);
    await getStripePromise(config);

    expect(loadStripeMock).toHaveBeenCalledTimes(1);
    expect(loadStripeMock).toHaveBeenCalledWith(
      "pk_api_cached",
      STRIPE_DEVELOPER_TOOLS_DISABLED,
    );
  });

  // PRD-20260915-payments-d10-client-config AC-006
  it("reloads Stripe.js when the environment switches to a different key", async () => {
    await getStripePromise(apiConfig("pk_test_sandbox"));
    await getStripePromise(apiConfig("pk_live_production"));

    expect(loadStripeMock).toHaveBeenCalledTimes(2);
    expect(loadStripeMock).toHaveBeenNthCalledWith(
      1,
      "pk_test_sandbox",
      STRIPE_DEVELOPER_TOOLS_DISABLED,
    );
    expect(loadStripeMock).toHaveBeenNthCalledWith(
      2,
      "pk_live_production",
      STRIPE_DEVELOPER_TOOLS_DISABLED,
    );
    expect(isStripeConfigured(apiConfig("pk_live_production"))).toBe(true);
  });
});

// PRD-20260918-payments-隐藏-stripe-elements-开发者工具入口：
// Stripe.js 在**测试模式**下会注入 "Stripe developer tools" 浮层（右下角黑色按钮 + 面板）；
// 用官方构造选项关闭（**不是** CSS 屏蔽 —— Easel 类名 hash 随版本漂移且承载真实支付 UI）。
describe("PRD-20260918 stripe developer tools off", () => {
  beforeEach(() => {
    loadStripeMock.mockReset();
    loadStripeMock.mockImplementation(() => Promise.resolve({ id: "stripe" }));
    vi.unstubAllEnvs();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  // AC-001：必须传官方关闭选项，且形状精确（Stripe.js 读的是 developerTools.assistant.enabled）
  it("passes the official developerTools opt-out to loadStripe (AC-001)", async () => {
    await getStripePromise(apiConfig("pk_test_ac001"));

    const options = loadStripeMock.mock.calls[0]?.[1];
    expect(options).toEqual({
      developerTools: { assistant: { enabled: false } },
    });
    expect(options.developerTools.assistant.enabled).toBe(false);
  });

  // AC-002：密钥来源（API 下发 / 环境变量回落）不得影响该选项
  it("applies the opt-out for both key sources (AC-002)", async () => {
    vi.stubEnv("NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY", "pk_env_ac002");

    await getStripePromise(apiConfig("pk_api_ac002"));
    await getStripePromise(null);

    expect(loadStripeMock).toHaveBeenNthCalledWith(
      1,
      "pk_api_ac002",
      STRIPE_DEVELOPER_TOOLS_DISABLED,
    );
    expect(loadStripeMock).toHaveBeenNthCalledWith(
      2,
      "pk_env_ac002",
      STRIPE_DEVELOPER_TOOLS_DISABLED,
    );
  });

  // AC-003：同 key 缓存语义不变（只 loadStripe 一次），且选项一致
  it("keeps the per-key cache and the same options (AC-003)", async () => {
    const config = apiConfig("pk_test_ac003");

    const first = await getStripePromise(config);
    const second = await getStripePromise(config);

    expect(first).toBe(second);
    expect(loadStripeMock).toHaveBeenCalledTimes(1);
    expect(loadStripeMock.mock.calls[0]?.[1]).toEqual(
      STRIPE_DEVELOPER_TOOLS_DISABLED,
    );
  });
});
