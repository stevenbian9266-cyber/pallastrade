"use client";

import {
  CheckoutProvider,
  PaymentElement,
  useCheckout,
} from "@stripe/react-stripe-js/checkout";
import { CircleAlert } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { normalizeClientSecret, stripePromise } from "@/lib/utils/stripe";

export interface StripePaymentFormHandle {
  confirmPayment: (returnUrl: string) => Promise<{ error?: string }>;
  fetchUpdates: () => Promise<void>;
}

interface StripePaymentFormProps {
  clientSecret: string;
  onReady: (handle: StripePaymentFormHandle) => void;
}

function StripePaymentFormInner({
  onReady,
}: {
  onReady: (handle: StripePaymentFormHandle) => void;
}) {
  const checkoutState = useCheckout();
  const [error, setError] = useState<string | null>(null);

  const confirmPayment = useCallback(
    async (returnUrl: string) => {
      if (checkoutState.type !== "success") {
        return { error: "Stripe has not loaded yet" };
      }

      setError(null);

      // PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): Checkout Session
      // (ui_mode: elements) is confirmed via `checkout.confirm`, not
      // `stripe.confirmPayment({ elements })`.
      const result = await checkoutState.checkout.confirm({
        returnUrl,
        redirect: "if_required",
      });

      if (result.type === "error") {
        const message =
          result.error.message || "An error occurred during payment.";
        setError(message);
        return { error: message };
      }

      return {};
    },
    [checkoutState],
  );

  const fetchUpdates = useCallback(async () => {
    // Checkout Sessions load their own updates via loadActions; nothing to do.
  }, []);

  useEffect(() => {
    if (checkoutState.type === "success") {
      onReady({ confirmPayment, fetchUpdates });
    }
  }, [checkoutState, confirmPayment, fetchUpdates, onReady]);

  if (checkoutState.type === "loading") {
    return <p className="text-sm text-gray-500">Loading payment form...</p>;
  }

  if (checkoutState.type === "error") {
    return (
      <p className="text-sm text-red-600" role="alert">
        {checkoutState.error.message}
      </p>
    );
  }

  return (
    <div>
      <PaymentElement
        options={{
          layout: "tabs",
        }}
      />
      {error && (
        <Alert variant="destructive" className="mt-3">
          <CircleAlert />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}

export function StripePaymentForm({
  clientSecret,
  onReady,
}: StripePaymentFormProps) {
  return (
    <CheckoutProvider
      stripe={stripePromise}
      options={{
        clientSecret: normalizeClientSecret(clientSecret),
        elementsOptions: {
          appearance: {
            theme: "stripe",
            variables: {
              fontFamily: 'Geist, "Geist Fallback", system-ui, sans-serif',
              fontSizeBase: "14px",
              colorPrimary: "#171717",
              borderRadius: "6px",
              focusBoxShadow: "0 0 0 1px #171717",
            },
            rules: {
              ".Input": {
                paddingTop: "13px",
                paddingBottom: "13px",
                boxShadow: "",
              },
            },
          },
        },
      }}
    >
      <StripePaymentFormInner onReady={onReady} />
    </CheckoutProvider>
  );
}
