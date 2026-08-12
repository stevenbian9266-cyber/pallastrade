/**
 * Cookie consent helpers — pure logic (parse/serialize/factories) plus the
 * thin browser (document.cookie) read/write layer.
 *
 * The pure functions are unit-testable without a DOM; the DOM helpers guard
 * on `typeof document` so they are safe to import from server code paths.
 *
 * # PRD-20260812-storefront-商城前台新增cookie功能 FR-003 / FR-006
 */

import {
  CONSENT_COOKIE_NAME,
  CONSENT_VERSION,
  type CookieConsent,
} from "./constants/cookies";

/** Categories the user may toggle on the settings UI. */
export interface ToggleablePreferences {
  functional: boolean;
  analytics: boolean;
  marketing: boolean;
}

/** Consent cookie lifetime: 1 year. */
const CONSENT_MAX_AGE = 60 * 60 * 24 * 365;

export function createDeniedConsent(): CookieConsent {
  return {
    necessary: true,
    functional: false,
    analytics: false,
    marketing: false,
    version: CONSENT_VERSION,
    updatedAt: new Date().toISOString(),
  };
}

export function createAcceptedConsent(): CookieConsent {
  return {
    necessary: true,
    functional: true,
    analytics: true,
    marketing: true,
    version: CONSENT_VERSION,
    updatedAt: new Date().toISOString(),
  };
}

export function createConsentFromPreferences(
  prefs: ToggleablePreferences,
): CookieConsent {
  return {
    necessary: true,
    functional: prefs.functional,
    analytics: prefs.analytics,
    marketing: prefs.marketing,
    version: CONSENT_VERSION,
    updatedAt: new Date().toISOString(),
  };
}

/**
 * Parse a raw consent cookie value. Returns `null` when the value is missing,
 * malformed, or the `necessary` flag is not explicitly true (treat as
 * undecided so the banner shows again).
 */
export function parseConsent(
  raw: string | null | undefined,
): CookieConsent | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<CookieConsent>;
    if (parsed.necessary !== true) return null;
    if (
      typeof parsed.functional !== "boolean" ||
      typeof parsed.analytics !== "boolean" ||
      typeof parsed.marketing !== "boolean"
    ) {
      return null;
    }
    return {
      necessary: true,
      functional: parsed.functional,
      analytics: parsed.analytics,
      marketing: parsed.marketing,
      version:
        typeof parsed.version === "number" ? parsed.version : CONSENT_VERSION,
      updatedAt:
        typeof parsed.updatedAt === "string"
          ? parsed.updatedAt
          : new Date().toISOString(),
    };
  } catch {
    return null;
  }
}

export function serializeConsent(consent: CookieConsent): string {
  return JSON.stringify(consent);
}

function getDocumentCookie(name: string): string | undefined {
  if (typeof document === "undefined") return undefined;
  const row = document.cookie
    .split("; ")
    .find((entry) => entry.startsWith(`${name}=`));
  if (!row) return undefined;
  return decodeURIComponent(row.slice(name.length + 1));
}

/** Read the consent cookie in the browser (client-only). */
export function readConsentFromDocument(): CookieConsent | null {
  return parseConsent(getDocumentCookie(CONSENT_COOKIE_NAME));
}

/** Persist the consent cookie in the browser (client-only). */
export function writeConsentToDocument(consent: CookieConsent): void {
  if (typeof document === "undefined") return;
  const value = encodeURIComponent(serializeConsent(consent));
  // Consent cookie must be readable by plain JS (document.cookie) for the
  // client-side gates; Cookie Store API is used only as a progressive
  // enhancement elsewhere, so we keep one synchronous path here.
  // biome-ignore lint/suspicious/noDocumentCookie: consent cookie read/write
  document.cookie = `${CONSENT_COOKIE_NAME}=${value}; path=/; max-age=${CONSENT_MAX_AGE}; SameSite=Lax`;
}
