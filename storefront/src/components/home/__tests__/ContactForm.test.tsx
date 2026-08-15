import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ContactForm } from "@/components/home/ContactForm";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/lib/data/contact", () => ({
  createContactMessage: vi.fn(),
}));

import { createContactMessage } from "@/lib/data/contact";

// # PRD-20260815-catalog-邮件管理整合 AC-007
describe("ContactForm", () => {
  it("renders the form with kind, email and message fields", () => {
    render(<ContactForm />);
    expect(screen.getByLabelText("emailLabel")).toBeTruthy();
    expect(screen.getByLabelText("bodyLabel")).toBeTruthy();
    expect(screen.getByRole("button", { name: "submit" })).toBeTruthy();
  });

  it("shows an error for an invalid email", async () => {
    const user = userEvent.setup();
    render(<ContactForm />);
    await user.type(screen.getByLabelText("emailLabel"), "not-an-email");
    await user.type(screen.getByLabelText("bodyLabel"), "Hello");
    await user.click(screen.getByRole("button", { name: "submit" }));
    expect(screen.getByRole("alert").textContent).toBe("invalidEmail");
  });

  it("shows an error when the message is empty", async () => {
    const user = userEvent.setup();
    render(<ContactForm />);
    await user.type(screen.getByLabelText("emailLabel"), "jane@example.com");
    await user.click(screen.getByRole("button", { name: "submit" }));
    expect(screen.getByRole("alert").textContent).toBe("emptyBody");
  });

  it("submits a valid message and shows the success state", async () => {
    vi.mocked(createContactMessage).mockResolvedValue({ success: true });
    const user = userEvent.setup();
    render(<ContactForm />);
    await user.selectOptions(screen.getByLabelText("kindLabel"), "complaint");
    await user.type(screen.getByLabelText("emailLabel"), "jane@example.com");
    await user.type(screen.getByLabelText("bodyLabel"), "Broken item");
    await user.click(screen.getByRole("button", { name: "submit" }));

    expect(createContactMessage).toHaveBeenCalledWith({
      kind: "complaint",
      name: undefined,
      email: "jane@example.com",
      subject: undefined,
      body: "Broken item",
    });
    expect(screen.getByRole("status").textContent).toBe("success");
  });

  it("shows an error when the server action fails", async () => {
    vi.mocked(createContactMessage).mockResolvedValue({
      success: false,
      error: "Failed to submit your message. Please try again.",
    });
    const user = userEvent.setup();
    render(<ContactForm />);
    await user.type(screen.getByLabelText("emailLabel"), "jane@example.com");
    await user.type(screen.getByLabelText("bodyLabel"), "Hello");
    await user.click(screen.getByRole("button", { name: "submit" }));
    expect(screen.getByRole("alert").textContent).toBe(
      "Failed to submit your message. Please try again.",
    );
  });
});
