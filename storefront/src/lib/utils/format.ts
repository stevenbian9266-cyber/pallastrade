export function formatDate(
  dateString: string | null,
  fallback = "-",
  locale = "en-US",
): string {
  if (!dateString) return fallback;
  return new Date(dateString).toLocaleDateString(locale, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export function formatDateTime(
  dateString: string | null,
  locale = "en-US",
): string {
  if (!dateString) return "-";
  return new Date(dateString).toLocaleString(locale, {
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function getPaymentStatusColor(state: string | null): string {
  switch (state) {
    case "paid":
      return "bg-green-100 text-green-800";
    case "balance_due":
    case "pending":
      return "bg-yellow-100 text-yellow-800";
    case "failed":
    case "void":
      return "bg-red-100 text-red-800";
    default:
      return "bg-gray-100 text-gray-800";
  }
}

export function getFulfillmentStatusColor(state: string | null): string {
  switch (state) {
    case "shipped":
    case "delivered":
      return "bg-green-100 text-green-800";
    case "ready":
    case "pending":
      return "bg-yellow-100 text-yellow-800";
    case "canceled":
      return "bg-red-100 text-red-800";
    default:
      return "bg-gray-100 text-gray-800";
  }
}

// ── Safe amount helpers ────────────────────────────────────────────────
// SDK monetary fields are `string | null` — these helpers prevent
// `parseFloat(null)` and `string | null` assignment errors.

/** Parse a nullable amount for boolean conditionals (> 0, !== 0).
 *  Returns NaN for null/empty so comparisons evaluate to false. */
export function safeParseFloat(value: string | null | undefined): number {
  if (value == null || value === "") return NaN;
  const n = Number.parseFloat(value);
  return Number.isFinite(n) ? n : NaN;
}

/** Return numeric fallback for nullable display values. */
export function nullableAmount(
  value: string | null | undefined,
  fallback = 0,
): number {
  if (value == null || value === "") return fallback;
  const n = Number.parseFloat(value);
  return Number.isFinite(n) ? n : fallback;
}

/** Pass through a nullable display string for translation interpolation. */
export function nullableDisplay(
  value: string | null | undefined,
  fallback = "",
): string {
  return value ?? fallback;
}
