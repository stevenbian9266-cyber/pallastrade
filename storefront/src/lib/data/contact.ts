"use server";

import { getClient } from "@/lib/pallastrade";
import { actionResult } from "./utils";

export type ContactKind = "complaint" | "feedback" | "inquiry";

export interface ContactMessageInput {
  kind: ContactKind;
  name?: string;
  email: string;
  subject?: string;
  body: string;
}

/**
 * Submit a complaint / feedback / inquiry from the storefront contact form.
 * Guest-accessible Store API endpoint; the message is classified by `kind`
 * and appears in the admin Email → Inbox & Feedback page.
 *
 * Runs on the server (env vars are server-only), so client components must call
 * this action instead of building an SDK client in the browser.
 */
export async function createContactMessage(
  input: ContactMessageInput,
): Promise<{ success: true } | { success: false; error: string }> {
  return actionResult(async () => {
    await getClient().contactMessages.create({
      kind: input.kind,
      name: input.name,
      email: input.email,
      subject: input.subject,
      body: input.body,
    });
    return {};
  }, "Failed to submit your message. Please try again.");
}
