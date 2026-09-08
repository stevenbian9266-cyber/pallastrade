import {
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { MobileMenu } from "@/components/layout/MobileMenu";
import { SearchToggle } from "@/components/layout/SearchToggle";

// # PRD-20260908-storefront-小屏下个人中心入口可见与移动菜单search弹出搜索框
// AC-002: 移动菜单点 Search → 关闭菜单并打开头部搜索浮层（出现搜索输入框）
// AC-003: 桌面头部搜索按钮可开合浮层；菜单页脚 My Account 入口保留

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/contexts/StoreContext", () => ({
  useStore: () => ({
    country: "US",
    currency: "USD",
    countries: [
      { iso: "US", name: "United States", currency: "USD" },
      { iso: "CA", name: "Canada", currency: "CAD" },
    ],
  }),
}));

vi.mock("@/hooks/useCountrySwitch", () => ({
  useCountrySwitch: () => ({
    isCountryNavigating: false,
    handleCountrySelect: vi.fn(),
  }),
}));

// SearchBar is loaded lazily inside SearchToggle via next/dynamic; stub it with
// a plain search input so the wiring (open/close of the single overlay) is
// asserted without depending on the real async suggestion widget. The real
// SearchBar is covered by browser E2E verification.
vi.mock("@/components/search/SearchBar", () => ({
  SearchBar: () => <input type="search" data-testid="mobile-search-input" />,
}));

const rootCategories = [
  { id: "c1", name: "Kitchen", permalink: "kitchen", children: [] },
] as never[];

function renderHeaderShell(left: React.ReactNode) {
  return render(
    <SearchToggle
      basePath="/us/en"
      left={left}
      center={<div />}
      rightStart={null}
      rightEnd={<div />}
    />,
  );
}

describe("SearchToggle — shared search overlay (AC-003 desktop)", () => {
  it("opens the overlay with a search input from the header search button", async () => {
    renderHeaderShell(<div />);
    fireEvent.click(screen.getByRole("button", { name: "openSearch" }));
    expect(await screen.findByTestId("mobile-search-input")).toBeTruthy();
  });

  it("closes the overlay when clicking the close button", async () => {
    const { container } = renderHeaderShell(<div />);
    fireEvent.click(screen.getByRole("button", { name: "openSearch" }));
    expect(await screen.findByTestId("mobile-search-input")).toBeTruthy();

    const overlay = container.querySelector(
      "#search-overlay",
    ) as HTMLElement | null;
    expect(overlay?.hasAttribute("inert")).toBe(false);

    fireEvent.click(screen.getByRole("button", { name: "closeSearch" }));
    await waitFor(() => {
      expect(overlay?.hasAttribute("inert")).toBe(true);
    });
  });
});

describe("MobileMenu — Search opens overlay + account row kept (AC-002/AC-003)", () => {
  it("opens the drawer, keeps My Account, and Search opens the overlay & closes the drawer", async () => {
    renderHeaderShell(
      <MobileMenu rootCategories={rootCategories} basePath="/us/en" />,
    );

    // Open the mobile drawer
    fireEvent.click(screen.getByRole("button", { name: "openMenu" }));
    const dialog = await screen.findByRole("dialog");

    // AC-003 regression: "My Account" entry still present in the drawer footer
    const accountLink = within(dialog).getByRole("link", { name: "myAccount" });
    expect(accountLink.getAttribute("href")).toBe("/us/en/account");

    // AC-002: clicking Search opens the shared header search overlay …
    fireEvent.click(within(dialog).getByRole("button", { name: "search" }));
    expect(await screen.findByTestId("mobile-search-input")).toBeTruthy();

    // … and the drawer closes.
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});
