/**
 * Catalog F-2 (PRD-20260916-catalog-batch-f2-stock-shipping): the arrival
 * window shown on the PDP.
 *
 * Transit days are counted in **weekdays** (Mon–Fri) with no holiday calendar —
 * the API publishes the same assumption as `business_day_source: "weekdays"`,
 * so the storefront never promises more than the merchant configured.
 */

/** Add business days to a date, skipping Saturday and Sunday. */
export function addBusinessDays(from: Date, days: number): Date {
  const date = new Date(from.getTime());
  let remaining = Math.max(0, Math.floor(days));

  while (remaining > 0) {
    date.setDate(date.getDate() + 1);
    const weekday = date.getDay();
    if (weekday !== 0 && weekday !== 6) remaining -= 1;
  }

  return date;
}

export interface ArrivalRange {
  from: Date;
  to: Date;
  /** True when both ends fall on the same day (single-date rendering). */
  sameDay: boolean;
}

/**
 * Turn a transit window into concrete dates. A method that only publishes a
 * minimum yields a single date rather than an invented upper bound.
 */
export function estimatedArrivalRange(
  minDays: number | null | undefined,
  maxDays: number | null | undefined,
  from: Date = new Date(),
): ArrivalRange | null {
  if (minDays == null && maxDays == null) return null;

  const min = Math.max(
    0,
    Math.min(minDays ?? maxDays ?? 0, maxDays ?? minDays ?? 0),
  );
  const max = Math.max(min, maxDays ?? minDays ?? 0);

  const start = addBusinessDays(from, min);
  const end = addBusinessDays(from, max);

  return {
    from: start,
    to: end,
    sameDay: start.toDateString() === end.toDateString(),
  };
}

/** Locale-aware "Sep 22–25" (or "22.–26. Sept." where the locale says so). */
export function formatArrivalRange(
  range: ArrivalRange,
  locale: string,
  timeZone?: string,
): string {
  const formatter = new Intl.DateTimeFormat(locale, {
    month: "short",
    day: "numeric",
    timeZone,
  });

  if (range.sameDay) return formatter.format(range.from);

  return `${formatter.format(range.from)}–${formatter.format(range.to)}`;
}
