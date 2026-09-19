import { describe, expect, it } from "vitest";
import { stripeLocaleFor } from "@/lib/utils/stripe";

/**
 * PRD-20260919-payments-checkout-top-express-pay-locale AC-006：
 * 站点语种 → Stripe `locale` 映射（站点五语种同码；未知/缺省回落 `auto`，
 * 即维持既有的「跟随浏览器语言」行为，不劣于现状）。
 */
describe("stripeLocaleFor", () => {
  it("maps every storefront locale to the matching Stripe locale", () => {
    expect(stripeLocaleFor("en")).toBe("en");
    expect(stripeLocaleFor("de")).toBe("de");
    expect(stripeLocaleFor("es")).toBe("es");
    expect(stripeLocaleFor("fr")).toBe("fr");
    expect(stripeLocaleFor("pl")).toBe("pl");
  });

  it("normalizes region-tagged and cased locales to the base language", () => {
    expect(stripeLocaleFor("en-US")).toBe("en");
    expect(stripeLocaleFor("DE")).toBe("de");
    expect(stripeLocaleFor("pt-BR")).toBe("auto");
  });

  it("falls back to auto when the locale is missing or unsupported", () => {
    expect(stripeLocaleFor(undefined)).toBe("auto");
    expect(stripeLocaleFor(null)).toBe("auto");
    expect(stripeLocaleFor("")).toBe("auto");
    expect(stripeLocaleFor("zh-CN")).toBe("auto");
  });
});
