import * as Sentry from "@sentry/nextjs";
import { readConsentFromDocument } from "@/lib/cookie-consent";

const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

// Opt-in to sending PII (IP addresses, cookies, user data) to Sentry.
// Defaults to false for privacy. Set NEXT_PUBLIC_SENTRY_SEND_DEFAULT_PII=true to enable.
const sendDefaultPii =
  process.env.NEXT_PUBLIC_SENTRY_SEND_DEFAULT_PII === "true";

/**
 * Only report to Sentry after the visitor has given analytics consent.
 * Runs per-event on the client; before consent is known (or when rejected)
 * every event/trace is dropped — the privacy-safe default.
 *
 * # PRD-20260812-storefront-商城前台新增cookie功能 FR-008
 */
function hasAnalyticsConsent(): boolean {
  return readConsentFromDocument()?.analytics === true;
}

if (dsn) {
  Sentry.init({
    dsn,
    sendDefaultPii,
    tracesSampleRate: process.env.NODE_ENV === "development" ? 1.0 : 0.1,
    beforeSend(event) {
      return hasAnalyticsConsent() ? event : null;
    },
    beforeSendTransaction(event) {
      return hasAnalyticsConsent() ? event : null;
    },
  });
}

export const onRouterTransitionStart = dsn
  ? Sentry.captureRouterTransitionStart
  : undefined;
