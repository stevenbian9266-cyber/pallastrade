import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CookieSettings } from "@/components/cookie/CookieSettings";
import { CookieConsentProvider } from "@/contexts/CookieConsentContext";
import { CONSENT_COOKIE_NAME } from "@/lib/constants/cookies";
import { readConsentFromDocument } from "@/lib/cookie-consent";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

function Harness() {
  return (
    <CookieConsentProvider>
      <CookieSettings />
    </CookieConsentProvider>
  );
}

// # PRD-20260812-storefront-商城前台新增cookie功能 AC-003 / AC-004
describe("CookieSettings", () => {
  beforeEach(() => {
    // biome-ignore lint/suspicious/noDocumentCookie: test cookie cleanup
    document.cookie = `${CONSENT_COOKIE_NAME}=; max-age=0; path=/`;
  });

  it("renders all categories with necessary locked on", () => {
    render(<Harness />);

    const necessary = screen.getByRole("checkbox", {
      name: "categories.necessary",
    });
    expect(necessary).toBeDisabled();
    expect(necessary).toBeChecked();

    expect(
      screen.getByRole("checkbox", { name: "categories.functional" }),
    ).not.toBeDisabled();
    expect(
      screen.getByRole("checkbox", { name: "categories.analytics" }),
    ).not.toBeDisabled();
    expect(
      screen.getByRole("checkbox", { name: "categories.marketing" }),
    ).not.toBeDisabled();
  });

  it("necessary stays checked and cannot be toggled", () => {
    render(<Harness />);

    const necessary = screen.getByRole("checkbox", {
      name: "categories.necessary",
    });
    fireEvent.click(necessary);
    expect(necessary).toBeChecked();
  });

  it("saving writes the selected categories to the consent cookie", async () => {
    render(<Harness />);

    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "categories.functional" }),
      ).toBeInTheDocument(),
    );

    // Toggle analytics on, keep functional/marketing off.
    fireEvent.click(screen.getByRole("checkbox", { name: "categories.analytics" }));
    fireEvent.click(screen.getByRole("button", { name: "savePreferences" }));

    const consent = readConsentFromDocument();
    expect(consent?.functional).toBe(false);
    expect(consent?.analytics).toBe(true);
    expect(consent?.marketing).toBe(false);
    expect(consent?.necessary).toBe(true);

    expect(screen.getByRole("status")).toHaveTextContent("saved");
  });
});
