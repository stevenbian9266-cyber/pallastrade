import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { NewsletterSignup } from "@/components/home/NewsletterSignup";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-109
describe("NewsletterSignup", () => {
  it("renders email input and subscribe button", () => {
    render(<NewsletterSignup />);
    expect(screen.getByPlaceholderText("newsletterPlaceholder")).toBeTruthy();
    expect(
      screen.getByRole("button", { name: "newsletterButton" }),
    ).toBeTruthy();
  });

  it("shows an error when submitting an empty email", async () => {
    const user = userEvent.setup();
    render(<NewsletterSignup />);
    await user.click(screen.getByRole("button", { name: "newsletterButton" }));
    expect(screen.getByRole("alert").textContent).toBe("newsletterEmpty");
  });

  it("shows an error for an invalid email", async () => {
    const user = userEvent.setup();
    render(<NewsletterSignup />);
    await user.type(
      screen.getByPlaceholderText("newsletterPlaceholder"),
      "not-an-email",
    );
    await user.click(screen.getByRole("button", { name: "newsletterButton" }));
    expect(screen.getByRole("alert").textContent).toBe("newsletterInvalid");
  });

  it("shows a success state for a valid email", async () => {
    const user = userEvent.setup();
    render(<NewsletterSignup />);
    await user.type(
      screen.getByPlaceholderText("newsletterPlaceholder"),
      "jane@example.com",
    );
    await user.click(screen.getByRole("button", { name: "newsletterButton" }));
    expect(screen.getByRole("status").textContent).toBe("newsletterSuccess");
  });
});
