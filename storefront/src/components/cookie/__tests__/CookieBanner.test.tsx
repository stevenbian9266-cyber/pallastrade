import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CookieBanner } from "@/components/cookie/CookieBanner";
import { CookieConsentProvider } from "@/contexts/CookieConsentContext";
import { CONSENT_COOKIE_NAME } from "@/lib/constants/cookies";
import {
  createDeniedConsent,
  readConsentFromDocument,
} from "@/lib/cookie-consent";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

function Harness() {
  return (
    <CookieConsentProvider>
      <CookieBanner />
    </CookieConsentProvider>
  );
}

// # PRD-20260812-storefront-商城前台新增cookie功能 AC-001 / AC-002 / AC-003
describe("CookieBanner", () => {
  beforeEach(() => {
    // biome-ignore lint/suspicious/noDocumentCookie: test cookie cleanup
    document.cookie = `${CONSENT_COOKIE_NAME}=; max-age=0; path=/`;
  });

  it("shows the banner for first-time visitors after hydration", async () => {
    render(<Harness />);
    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());

    expect(
      screen.getByRole("button", { name: "acceptAll" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "necessaryOnly" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "customize" }),
    ).toBeInTheDocument();
  });

  it("hides after accept-all and writes the consent cookie", async () => {
    render(<Harness />);
    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "acceptAll" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    const consent = readConsentFromDocument();
    expect(consent?.analytics).toBe(true);
    expect(consent?.marketing).toBe(true);
  });

  it("hides after necessary-only and keeps analytics/marketing off", async () => {
    render(<Harness />);
    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "necessaryOnly" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    const consent = readConsentFromDocument();
    expect(consent?.functional).toBe(false);
    expect(consent?.analytics).toBe(false);
    expect(consent?.marketing).toBe(false);
  });

  it("does not show for returning visitors with a stored consent", async () => {
    // biome-ignore lint/suspicious/noDocumentCookie: seed a stored consent cookie
    document.cookie = `${CONSENT_COOKIE_NAME}=${encodeURIComponent(
      JSON.stringify(createDeniedConsent()),
    )}; path=/`;

    render(<Harness />);

    // Give the mount effect a chance to read the stored cookie.
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("customize reveals the category panel and saving hides the banner", async () => {
    render(<Harness />);
    await waitFor(() => expect(screen.getByRole("dialog")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "customize" }));

    expect(
      screen.getByRole("checkbox", { name: "categories.functional" }),
    ).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "savePreferences" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});
