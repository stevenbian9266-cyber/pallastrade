import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config 切片2）——
// 前端密钥下发双读迁移：**先读服务端 client_config，回落构建期 NEXT_PUBLIC_***。
// 目标：换支付商 / 换环境 = 后台改配置即生效（不再重建镜像）。
import {
  getStripePromise,
  isStripeConfigured,
  type PaymentClientConfig,
  resolveStripePublishableKey,
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
    expect(loadStripeMock).toHaveBeenCalledWith("pk_api_cached");
  });

  // PRD-20260915-payments-d10-client-config AC-006
  it("reloads Stripe.js when the environment switches to a different key", async () => {
    await getStripePromise(apiConfig("pk_test_sandbox"));
    await getStripePromise(apiConfig("pk_live_production"));

    expect(loadStripeMock).toHaveBeenCalledTimes(2);
    expect(loadStripeMock).toHaveBeenNthCalledWith(1, "pk_test_sandbox");
    expect(loadStripeMock).toHaveBeenNthCalledWith(2, "pk_live_production");
    expect(isStripeConfigured(apiConfig("pk_live_production"))).toBe(true);
  });
});
