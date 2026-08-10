"use client";

import { Mail, Check } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

/**
 * Newsletter signup — client component with front-end validation and a success
 * state. No backend submission yet (webhook integration is a future extension).
 *
 * # PRD-20260810-storefront-对商城前台进行重新规划 AC-109
 */
export function NewsletterSignup() {
  const t = useTranslations("home");
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [subscribed, setSubscribed] = useState(false);

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const value = email.trim();
    if (!value) {
      setError(t("newsletterEmpty"));
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
      setError(t("newsletterInvalid"));
      return;
    }
    setError(null);
    setSubscribed(true);
  };

  return (
    <section
      aria-labelledby="newsletter-heading"
      className="bg-gray-50 py-16"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-xl text-center">
          <h2
            id="newsletter-heading"
            className="text-2xl md:text-3xl font-bold text-gray-900"
          >
            {t("newsletterTitle")}
          </h2>
          <p className="mt-3 text-gray-600">{t("newsletterDescription")}</p>

          {subscribed ? (
            <p
              role="status"
              className="mt-6 inline-flex items-center gap-2 rounded-full bg-green-50 px-5 py-3 text-sm font-medium text-green-700"
            >
              <Check className="size-5" aria-hidden="true" />
              {t("newsletterSuccess")}
            </p>
          ) : (
            <form
              onSubmit={handleSubmit}
              noValidate
              className="mt-6 flex flex-col sm:flex-row gap-3"
            >
              <label htmlFor="newsletter-email" className="sr-only">
                {t("newsletterPlaceholder")}
              </label>
              <Input
                id="newsletter-email"
                type="email"
                autoComplete="email"
                placeholder={t("newsletterPlaceholder")}
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                aria-invalid={error ? true : undefined}
                aria-describedby={error ? "newsletter-error" : undefined}
                className="flex-1"
              />
              <Button type="submit" className="shrink-0">
                {t("newsletterButton")}
              </Button>
            </form>
          )}
          {error && (
            <p
              id="newsletter-error"
              role="alert"
              className="mt-3 text-sm text-red-600"
            >
              {error}
            </p>
          )}
        </div>
      </div>
    </section>
  );
}
