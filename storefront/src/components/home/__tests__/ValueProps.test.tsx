import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ValueProps } from "@/components/home/ValueProps";

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-108
describe("ValueProps", () => {
  it("renders at least 4 value props", async () => {
    const element = await ValueProps({ locale: "en" });
    render(element);

    const titles = [
      "fastShipping",
      "authenticProducts",
      "easyReturns",
      "support",
    ];
    for (const title of titles) {
      expect(screen.getByText(title)).toBeTruthy();
    }
    const h3s = screen.getAllByRole("heading", { level: 3 });
    expect(h3s.length).toBeGreaterThanOrEqual(3);
  });
});
