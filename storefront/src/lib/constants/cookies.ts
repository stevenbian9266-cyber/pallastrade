/**
 * Cookie consent categories and mappings.
 *
 * The storefront uses cookies for core functionality (cart, auth, locale)
 * and loads third-party scripts (GTM, Vercel Analytics, Sentry, Tawk.to).
 * This module is the single source of truth for the consent categories,
 * the consent cookie, and which scripts each category gates.
 *
 * # PRD-20260812-storefront-商城前台新增cookie功能 FR-001
 */

export type CookieCategory =
  | "necessary"
  | "functional"
  | "analytics"
  | "marketing";

export interface CookieConsent {
  /** Strictly necessary — always true, not user-toggleable. */
  necessary: true;
  functional: boolean;
  analytics: boolean;
  marketing: boolean;
  /** Consent schema version (bump to invalidate old consent values). */
  version: number;
  /** ISO timestamp of the last change. */
  updatedAt: string;
}

/** Name of the consent cookie. It is itself a necessary cookie. */
export const CONSENT_COOKIE_NAME = "pallastrade_cookie_consent";

/** Current consent schema version. */
export const CONSENT_VERSION = 1;

export interface CookieCategoryInfo {
  key: CookieCategory;
  /** i18n key under `cookie.categories.<titleKey>` (title). */
  titleKey: string;
  /** i18n key under `cookie.categories.<descriptionKey>` (description). */
  descriptionKey: string;
  /** Whether the category is mandatory (not user-toggleable). */
  required?: boolean;
}

export const COOKIE_CATEGORIES: CookieCategoryInfo[] = [
  {
    key: "necessary",
    titleKey: "necessary",
    descriptionKey: "necessaryDescription",
    required: true,
  },
  {
    key: "functional",
    titleKey: "functional",
    descriptionKey: "functionalDescription",
  },
  {
    key: "analytics",
    titleKey: "analytics",
    descriptionKey: "analyticsDescription",
  },
  {
    key: "marketing",
    titleKey: "marketing",
    descriptionKey: "marketingDescription",
  },
];

/** Categories the user may toggle (necessary is always enabled). */
export const TOGGLEABLE_CATEGORIES: CookieCategory[] = [
  "functional",
  "analytics",
  "marketing",
];

/**
 * Which third-party scripts / first-party cookies each toggleable category
 * gates. Used for documentation and to keep the mapping in one place.
 */
export const COOKIE_SCRIPT_MAP: Record<
  Exclude<CookieCategory, "necessary">,
  readonly string[]
> = {
  functional: ["pallastrade_country", "pallastrade_locale"],
  analytics: ["GTM", "Vercel Analytics", "Speed Insights", "Sentry"],
  marketing: ["Tawk.to live chat"],
};
