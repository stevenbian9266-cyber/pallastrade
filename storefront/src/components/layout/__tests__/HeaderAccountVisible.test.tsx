import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Header } from "@/components/layout/Header";

// # PRD-20260908-storefront-小屏下个人中心入口可见与移动菜单search弹出搜索框
// AC-001: <md Header 账户链接可见（不再被 hidden md:block 包裹）

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

vi.mock("@/lib/store", () => ({
  getStoreName: () => "PallasTrade",
}));

// Server-component child dynamic imports (MobileMenu / CountrySwitcher) and the
// cart button are irrelevant to the account-entry assertion.
vi.mock("next/dynamic", () => ({
  __esModule: true,
  default: () => {
    const Stub = () => null;
    Stub.displayName = "DynamicStub";
    return Stub;
  },
}));

vi.mock("@/components/layout/CartButton", () => ({
  CartButton: () => null,
}));

const rootCategories = [
  { id: "c1", name: "Kitchen", permalink: "kitchen", children: [] },
] as never[];

describe("Header account entry (AC-001)", () => {
  it("renders the account link without a mobile-hidden wrapper", async () => {
    const element = await Header({
      rootCategories,
      basePath: "/us/en",
      locale: "en",
    });
    const { container } = render(element);

    const link = container.querySelector('a[href="/us/en/account"]');
    expect(link).not.toBeNull();
    expect(link?.getAttribute("aria-label")).toBe("account");

    // Walk ancestors: none may carry `hidden` / `md:hidden` (the old gating).
    let node: Element | null = link as Element | null;
    while (node) {
      const className = node.getAttribute("class") ?? "";
      expect(className).not.toMatch(/(^|\s)(md:)?hidden(\s|$)/);
      node = node.parentElement;
    }
  });

  it("does not render duplicate account links", async () => {
    const element = await Header({
      rootCategories,
      basePath: "/us/en",
      locale: "en",
    });
    render(element);
    expect(screen.getAllByRole("link", { name: "account" })).toHaveLength(1);
  });
});
