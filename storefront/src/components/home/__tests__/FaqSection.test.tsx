import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { FaqSection } from "@/components/home/FaqSection";

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-113
describe("FaqSection", () => {
  it("renders at least 3 visible Q&A pairs and matching FAQPage JSON-LD", async () => {
    const element = await FaqSection({ locale: "en" });
    const { container } = render(element);

    const h3s = screen.getAllByRole("heading", { level: 3 });
    expect(h3s.length).toBeGreaterThanOrEqual(3);

    const jsonLd = container.querySelector(
      'script[type="application/ld+json"]',
    );
    expect(jsonLd).not.toBeNull();
    const parsed = JSON.parse(jsonLd?.textContent ?? "{}");
    expect(parsed["@type"]).toBe("FAQPage");
    expect(parsed.mainEntity.length).toBeGreaterThanOrEqual(3);
    expect(parsed.mainEntity[0]["@type"]).toBe("Question");
    expect(parsed.mainEntity[0].acceptedAnswer["@type"]).toBe("Answer");
  });
});
