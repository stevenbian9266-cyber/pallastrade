import { beforeEach, describe, expect, it } from "vitest";
import { CONSENT_COOKIE_NAME } from "@/lib/constants/cookies";
import {
  createAcceptedConsent,
  createConsentFromPreferences,
  createDeniedConsent,
  parseConsent,
  readConsentFromDocument,
  serializeConsent,
  writeConsentToDocument,
} from "@/lib/cookie-consent";

// # PRD-20260812-storefront-商城前台新增cookie功能 AC-002 / AC-003
describe("cookie-consent pure helpers", () => {
  beforeEach(() => {
    // biome-ignore lint/suspicious/noDocumentCookie: test cookie cleanup
    document.cookie = `${CONSENT_COOKIE_NAME}=; max-age=0; path=/`;
  });

  it("createDeniedConsent enables only necessary", () => {
    const c = createDeniedConsent();
    expect(c.necessary).toBe(true);
    expect(c.functional).toBe(false);
    expect(c.analytics).toBe(false);
    expect(c.marketing).toBe(false);
    expect(c.version).toBe(1);
    expect(typeof c.updatedAt).toBe("string");
  });

  it("createAcceptedConsent enables every category", () => {
    const c = createAcceptedConsent();
    expect(c.necessary).toBe(true);
    expect(c.functional).toBe(true);
    expect(c.analytics).toBe(true);
    expect(c.marketing).toBe(true);
  });

  it("createConsentFromPreferences keeps the chosen categories", () => {
    const c = createConsentFromPreferences({
      functional: true,
      analytics: false,
      marketing: true,
    });
    expect(c.functional).toBe(true);
    expect(c.analytics).toBe(false);
    expect(c.marketing).toBe(true);
    expect(c.necessary).toBe(true);
  });

  it("parseConsent round-trips a serialized consent", () => {
    const c = createAcceptedConsent();
    expect(parseConsent(serializeConsent(c))).toEqual(c);
  });

  it("parseConsent returns null for missing or empty input", () => {
    expect(parseConsent(null)).toBeNull();
    expect(parseConsent(undefined)).toBeNull();
    expect(parseConsent("")).toBeNull();
  });

  it("parseConsent returns null for malformed JSON", () => {
    expect(parseConsent("{not-json")).toBeNull();
  });

  it("parseConsent returns null when necessary is not explicitly true", () => {
    expect(
      parseConsent(
        JSON.stringify({
          functional: true,
          analytics: true,
          marketing: true,
        }),
      ),
    ).toBeNull();
    expect(
      parseConsent(
        JSON.stringify({
          necessary: false,
          functional: true,
          analytics: true,
          marketing: true,
        }),
      ),
    ).toBeNull();
  });

  it("parseConsent returns null when boolean fields are missing", () => {
    expect(
      parseConsent(JSON.stringify({ necessary: true, analytics: true })),
    ).toBeNull();
  });

  it("readConsentFromDocument reads the consent cookie in the browser", () => {
    writeConsentToDocument(createDeniedConsent());
    const read = readConsentFromDocument();
    expect(read?.necessary).toBe(true);
    expect(read?.functional).toBe(false);
    expect(read?.analytics).toBe(false);
    expect(read?.marketing).toBe(false);
  });
});
