import { describe, expect, it } from "vitest";
import { emptyAddress } from "@/lib/utils/address";
import {
  billingDetailsFromFormData,
  billingDetailsFromWallet,
  isCompleteBillingAddress,
} from "@/lib/utils/stripe-billing";

/**
 * PRD-20260919-checkout-billing-details-passthrough AC-003/AC-004：
 * 账单详情 → Stripe 形状的唯一映射点；**不完整就不发**（与后端
 * `Carts::Update#validate_billing_address!` 同口径的最小完整集）。
 */
describe("stripe-billing 映射（PRD-20260919-checkout-billing-details-passthrough）", () => {
  const completeAddress = {
    line1: "1 Billing St",
    line2: null,
    city: "Billingville",
    state: null,
    postal_code: "EC1A 1BB",
    country: "GB",
  };

  describe("isCompleteBillingAddress", () => {
    it("requires line1 + city + postal_code + country", () => {
      expect(isCompleteBillingAddress(completeAddress)).toBe(true);
      for (const key of ["line1", "city", "postal_code", "country"] as const) {
        expect(
          isCompleteBillingAddress({ ...completeAddress, [key]: "" }),
        ).toBe(false);
        expect(
          isCompleteBillingAddress({ ...completeAddress, [key]: null }),
        ).toBe(false);
      }
    });

    it("treats whitespace-only fields as missing", () => {
      expect(
        isCompleteBillingAddress({ ...completeAddress, postal_code: "   " }),
      ).toBe(false);
    });

    it("is false for null/undefined payloads", () => {
      expect(isCompleteBillingAddress(null)).toBe(false);
      expect(isCompleteBillingAddress(undefined)).toBe(false);
    });
  });

  describe("billingDetailsFromFormData", () => {
    it("maps the checkout form state to Stripe billing_details", () => {
      const details = billingDetailsFromFormData({
        ...emptyAddress,
        address1: "1 Billing St",
        address2: "Apt 4",
        city: "Billingville",
        postal_code: "EC1A 1BB",
        country_iso: "GB",
        state_abbr: "LDN",
      });

      expect(details).toEqual({
        address: {
          line1: "1 Billing St",
          line2: "Apt 4",
          city: "Billingville",
          postal_code: "EC1A 1BB",
          country: "GB",
          state: "LDN",
        },
      });
    });

    it("falls back to state_name when state_abbr is empty", () => {
      const details = billingDetailsFromFormData({
        ...emptyAddress,
        address1: "1 Billing St",
        city: "Billingville",
        postal_code: "EC1A 1BB",
        country_iso: "GB",
        state_name: "Greater London",
      });

      expect(details?.address.state).toBe("Greater London");
    });

    it("omits optional keys instead of sending blank strings", () => {
      const details = billingDetailsFromFormData({
        ...emptyAddress,
        address1: "1 Billing St",
        city: "Billingville",
        postal_code: "EC1A 1BB",
        country_iso: "GB",
      });

      expect(details?.address).not.toHaveProperty("line2");
      expect(details?.address).not.toHaveProperty("state");
    });

    it("returns null for an incomplete address (nothing is sent)", () => {
      expect(
        billingDetailsFromFormData({
          ...emptyAddress,
          address1: "1 Billing St",
          city: "Billingville",
        }),
      ).toBeNull();
      expect(billingDetailsFromFormData(emptyAddress)).toBeNull();
    });
  });

  describe("billingDetailsFromWallet", () => {
    it("adopts the wallet's billing details when complete", () => {
      expect(
        billingDetailsFromWallet({
          name: "Ada Lovelace",
          email: "ada@example.com",
          phone: "555-0100",
          address: completeAddress,
        }),
      ).toEqual({
        name: "Ada Lovelace",
        email: "ada@example.com",
        phone: "555-0100",
        address: {
          line1: "1 Billing St",
          city: "Billingville",
          postal_code: "EC1A 1BB",
          country: "GB",
        },
      });
    });

    it("returns null when the wallet billing address is incomplete (degrade to same as shipping)", () => {
      expect(
        billingDetailsFromWallet({
          name: "Ada Lovelace",
          address: { ...completeAddress, postal_code: null },
        }),
      ).toBeNull();
      expect(billingDetailsFromWallet(null)).toBeNull();
      expect(billingDetailsFromWallet(undefined)).toBeNull();
    });
  });
});
