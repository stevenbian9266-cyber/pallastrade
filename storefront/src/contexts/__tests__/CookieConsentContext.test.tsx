import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it } from "vitest";
import {
  CookieConsentProvider,
  useCookieConsent,
} from "@/contexts/CookieConsentContext";
import { CONSENT_COOKIE_NAME } from "@/lib/constants/cookies";
import { createDeniedConsent } from "@/lib/cookie-consent";

function wrapper({ children }: { children: ReactNode }) {
  return <CookieConsentProvider>{children}</CookieConsentProvider>;
}

// # PRD-20260812-storefront-商城前台新增cookie功能 AC-001 / AC-002 / AC-003
describe("CookieConsentContext", () => {
  beforeEach(() => {
    // biome-ignore lint/suspicious/noDocumentCookie: test cookie cleanup
    document.cookie = `${CONSENT_COOKIE_NAME}=; max-age=0; path=/`;
  });

  it("throws when used outside CookieConsentProvider", () => {
    expect(() => {
      renderHook(() => useCookieConsent());
    }).toThrow("useCookieConsent must be used within a CookieConsentProvider");
  });

  it("starts undecided until the consent cookie is read on the client", async () => {
    const { result } = renderHook(() => useCookieConsent(), { wrapper });

    // The consent cookie is read in an effect on the client; until then the
    // consumer is undecided (null) so no banner/scripts render.
    await waitFor(() => expect(result.current.consent).toBeNull());
    expect(result.current.hasDecided).toBe(false);
  });

  it("acceptAll writes an all-consented cookie", async () => {
    const { result } = renderHook(() => useCookieConsent(), { wrapper });

    act(() => result.current.acceptAll());

    expect(result.current.consent?.necessary).toBe(true);
    expect(result.current.consent?.functional).toBe(true);
    expect(result.current.consent?.analytics).toBe(true);
    expect(result.current.consent?.marketing).toBe(true);
    expect(result.current.hasDecided).toBe(true);
    expect(document.cookie).toContain(CONSENT_COOKIE_NAME);
  });

  it("rejectAll writes necessary-only consent", async () => {
    const { result } = renderHook(() => useCookieConsent(), { wrapper });

    act(() => result.current.rejectAll());

    expect(result.current.consent?.necessary).toBe(true);
    expect(result.current.consent?.functional).toBe(false);
    expect(result.current.consent?.analytics).toBe(false);
    expect(result.current.consent?.marketing).toBe(false);
  });

  it("savePreferences writes the chosen categories", async () => {
    const { result } = renderHook(() => useCookieConsent(), { wrapper });

    act(() =>
      result.current.savePreferences({
        functional: true,
        analytics: false,
        marketing: false,
      }),
    );

    expect(result.current.consent?.functional).toBe(true);
    expect(result.current.consent?.analytics).toBe(false);
    expect(result.current.consent?.marketing).toBe(false);
  });

  it("restores a stored consent on mount", async () => {
    // biome-ignore lint/suspicious/noDocumentCookie: seed a stored consent cookie
    document.cookie = `${CONSENT_COOKIE_NAME}=${encodeURIComponent(
      JSON.stringify(createDeniedConsent()),
    )}; path=/`;

    const { result } = renderHook(() => useCookieConsent(), { wrapper });
    await waitFor(() => expect(result.current.hasDecided).toBe(true));

    expect(result.current.consent?.analytics).toBe(false);
    expect(result.current.consent?.marketing).toBe(false);
  });
});
