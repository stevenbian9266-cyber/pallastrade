import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GatedScripts } from "@/components/cookie/GatedScripts";
import {
  CookieConsentProvider,
  useCookieConsent,
} from "@/contexts/CookieConsentContext";
import { CONSENT_COOKIE_NAME } from "@/lib/constants/cookies";

vi.mock("@next/third-parties/google", () => ({
  GoogleTagManager: ({ gtmId }: { gtmId: string }) => (
    <div data-testid="gtm">{gtmId}</div>
  ),
}));

vi.mock("@vercel/analytics/next", () => ({
  Analytics: () => <div data-testid="vercel-analytics" />,
}));

vi.mock("@vercel/speed-insights/next", () => ({
  SpeedInsights: () => <div data-testid="speed-insights" />,
}));

vi.mock("@/components/layout/TawkToWidget", () => ({
  TawkToWidget: () => <div data-testid="tawk" />,
}));

function ActionButtons() {
  const { acceptAll, rejectAll, savePreferences } = useCookieConsent();
  return (
    <>
      <button type="button" onClick={acceptAll}>
        accept-all
      </button>
      <button type="button" onClick={rejectAll}>
        reject-all
      </button>
      <button
        type="button"
        onClick={() =>
          savePreferences({
            functional: false,
            analytics: false,
            marketing: true,
          })
        }
      >
        marketing-only
      </button>
    </>
  );
}

function Harness() {
  return (
    <CookieConsentProvider>
      <ActionButtons />
      <GatedScripts />
    </CookieConsentProvider>
  );
}

// # PRD-20260812-storefront-商城前台新增cookie功能 AC-005
describe("GatedScripts", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  beforeEach(() => {
    // biome-ignore lint/suspicious/noDocumentCookie: test cookie cleanup
    document.cookie = `${CONSENT_COOKIE_NAME}=; max-age=0; path=/`;
  });

  it("loads nothing before consent is known", async () => {
    vi.stubEnv("NEXT_PUBLIC_GTM_ID", "GTM-123");

    render(<Harness />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "accept-all" })).toBeInTheDocument(),
    );

    expect(screen.queryByTestId("gtm")).toBeNull();
    expect(screen.queryByTestId("tawk")).toBeNull();
    expect(screen.queryByTestId("vercel-analytics")).toBeNull();
  });

  it("loads GTM + Tawk.to when everything is accepted", async () => {
    vi.stubEnv("NEXT_PUBLIC_GTM_ID", "GTM-123");

    render(<Harness />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "accept-all" })).toBeInTheDocument(),
    );
    fireEvent.click(screen.getByRole("button", { name: "accept-all" }));

    expect(screen.getByTestId("gtm")).toHaveTextContent("GTM-123");
    expect(screen.getByTestId("tawk")).toBeInTheDocument();
  });

  it("loads Tawk.to but not GTM when only marketing is consented", async () => {
    vi.stubEnv("NEXT_PUBLIC_GTM_ID", "GTM-123");

    render(<Harness />);
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "marketing-only" }),
      ).toBeInTheDocument(),
    );
    fireEvent.click(screen.getByRole("button", { name: "marketing-only" }));

    expect(screen.queryByTestId("gtm")).toBeNull();
    expect(screen.getByTestId("tawk")).toBeInTheDocument();
  });

  it("loads nothing when only necessary is accepted", async () => {
    vi.stubEnv("NEXT_PUBLIC_GTM_ID", "GTM-123");

    render(<Harness />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "reject-all" })).toBeInTheDocument(),
    );
    fireEvent.click(screen.getByRole("button", { name: "reject-all" }));

    expect(screen.queryByTestId("gtm")).toBeNull();
    expect(screen.queryByTestId("tawk")).toBeNull();
  });

  it("loads Vercel analytics only when analytics is consented and enabled", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("NEXT_PUBLIC_VERCEL_ANALYTICS", "true");

    render(<Harness />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "accept-all" })).toBeInTheDocument(),
    );
    fireEvent.click(screen.getByRole("button", { name: "accept-all" }));

    expect(screen.getByTestId("vercel-analytics")).toBeInTheDocument();
    expect(screen.getByTestId("speed-insights")).toBeInTheDocument();
  });
});
