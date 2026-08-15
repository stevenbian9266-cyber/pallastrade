"use client";

import { Check, Send } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { type ContactKind, createContactMessage } from "@/lib/data/contact";

/**
 * Contact / feedback form (home page #contact anchor). Customers can submit a
 * complaint, feedback or general inquiry. Messages are sent via the Store API
 * and classified in the admin Email → Inbox & Feedback page.
 *
 * # PRD-20260815-catalog-邮件管理整合 AC-007
 */
export function ContactForm() {
  const t = useTranslations("contact");
  const [kind, setKind] = useState<ContactKind>("feedback");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);

    if (!email.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError(t("invalidEmail"));
      return;
    }
    if (!body.trim()) {
      setError(t("emptyBody"));
      return;
    }

    setSubmitting(true);
    const result = await createContactMessage({
      kind,
      name: name.trim() || undefined,
      email: email.trim(),
      subject: subject.trim() || undefined,
      body: body.trim(),
    });
    setSubmitting(false);

    if (result.success) {
      setSubmitted(true);
    } else {
      setError(result.error);
    }
  };

  if (submitted) {
    return (
      <ContactSection>
        <p
          role="status"
          className="mt-6 inline-flex items-center gap-2 rounded-full bg-green-50 px-5 py-3 text-sm font-medium text-green-700"
        >
          <Check className="size-5" aria-hidden="true" />
          {t("success")}
        </p>
      </ContactSection>
    );
  }

  return (
    <ContactSection>
      <form
        onSubmit={handleSubmit}
        noValidate
        className="mt-8 space-y-5 rounded-2xl border border-gray-200 bg-white p-6 sm:p-8 text-left"
      >
        <div>
          <Label htmlFor="contact-kind">{t("kindLabel")}</Label>
          <select
            id="contact-kind"
            value={kind}
            onChange={(event) => setKind(event.target.value as ContactKind)}
            className="mt-1.5 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
          >
            <option value="complaint">{t("kindComplaint")}</option>
            <option value="feedback">{t("kindFeedback")}</option>
            <option value="inquiry">{t("kindInquiry")}</option>
          </select>
        </div>

        <div className="grid gap-5 sm:grid-cols-2">
          <div>
            <Label htmlFor="contact-name">{t("nameLabel")}</Label>
            <Input
              id="contact-name"
              type="text"
              autoComplete="name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              className="mt-1.5"
            />
          </div>
          <div>
            <Label htmlFor="contact-email">{t("emailLabel")}</Label>
            <Input
              id="contact-email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="mt-1.5"
              aria-invalid={error === t("invalidEmail") ? true : undefined}
            />
          </div>
        </div>

        <div>
          <Label htmlFor="contact-subject">{t("subjectLabel")}</Label>
          <Input
            id="contact-subject"
            type="text"
            value={subject}
            onChange={(event) => setSubject(event.target.value)}
            className="mt-1.5"
          />
        </div>

        <div>
          <Label htmlFor="contact-body">{t("bodyLabel")}</Label>
          <Textarea
            id="contact-body"
            required
            rows={5}
            value={body}
            onChange={(event) => setBody(event.target.value)}
            className="mt-1.5"
            aria-invalid={error === t("emptyBody") ? true : undefined}
          />
        </div>

        {error && (
          <p role="alert" className="text-sm text-red-600">
            {error}
          </p>
        )}

        <Button type="submit" disabled={submitting} className="w-full">
          <Send className="size-4" aria-hidden="true" />
          {submitting ? t("submitting") : t("submit")}
        </Button>
      </form>
    </ContactSection>
  );
}

/**
 * Shared section shell for the contact form / success state — heading,
 * description and centered layout.
 */
function ContactSection({ children }: { children: React.ReactNode }) {
  const t = useTranslations("contact");
  return (
    <section
      id="contact"
      aria-labelledby="contact-heading"
      className="bg-gray-50 py-16"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <h2
            id="contact-heading"
            className="text-2xl md:text-3xl font-bold text-gray-900"
          >
            {t("title")}
          </h2>
          <p className="mt-3 text-gray-600">{t("description")}</p>
          {children}
        </div>
      </div>
    </section>
  );
}
