# frozen_string_literal: true

require "spec_helper"

# ── API v1 Contract Tests ───────────────────────────────────────────
# Verifies that /api/v1/store/* and /api/v1/admin/* endpoints exist
# and return valid JSON responses (reusing v3 controllers).
#
# These are minimal smoke tests — full contract tests should go in
# spec/requests/api/v1/ with OpenAPI validation.

RSpec.describe "API v1 routing", type: :request do
  let(:api_key) { create(:api_key, :publishable, store: @default_store) }
  let(:store_headers) { { 'X-PallasTrade-Api-Key' => api_key.token } }
  # ── Store API (publishable key) ──────────────────────────────────

  describe "GET /api/v1/store/products" do
    it "returns 200 with JSON product list" do
      get "/api/v1/store/products", headers: store_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /api/v1/store/markets" do
    it "returns 200 with JSON market list" do
      get "/api/v1/store/markets", headers: store_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /api/v1/store/categories" do
    it "returns 200 with JSON category list" do
      get "/api/v1/store/categories", headers: store_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /api/v1/store/countries" do
    it "returns 200 with JSON country list" do
      get "/api/v1/store/countries", headers: store_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "GET /api/v1/store/currencies" do
    it "returns 200 with JSON currency list" do
      get "/api/v1/store/currencies", headers: store_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end
  end

  # ── Error responses ──────────────────────────────────────────────

  describe "GET /api/v1/store/nonexistent" do
    it "returns 404 JSON (not HTML)" do
      get "/api/v1/store/nonexistent", headers: store_headers
      expect(response).to have_http_status(:not_found)
      expect(response.content_type).to include("application/json")
    end
  end

  # ── Admin API (requires auth) ────────────────────────────────────

  describe "GET /api/v1/admin/me (unauthenticated)" do
    it "returns 401 JSON" do
      get "/api/v1/admin/me"
      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "POST /api/v1/admin/auth/login (invalid credentials)" do
    it "returns 401 JSON" do
      post "/api/v1/admin/auth/login", params: { email: "no@no.com", password: "wrong" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "admin payment mutations (unauthenticated)" do
    let(:product) { create(:product_in_stock, store: @default_store) }
    let(:order) { create(:completed_order_with_totals, store: @default_store, variants: [product.default_variant]) }
    let(:payment_method) { create(:check_payment_method, store: @default_store) }
    let(:payment) do
      create(
        :payment,
        order: order,
        payment_method: payment_method,
        amount: order.total,
        state: "checkout"
      )
    end

    it "rejects Capture before changing payment state" do
      patch "/api/v1/admin/orders/#{order.prefixed_id}/payments/#{payment.prefixed_id}/capture"

      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).to include("application/json")
      expect(payment.reload).to be_checkout
    end

    it "rejects Refund before creating a refund record" do
      expect do
        post "/api/v1/admin/orders/#{order.prefixed_id}/refunds", params: { payment_id: payment.prefixed_id, amount: 1 }
      end.not_to change(PallasTrade::Refund, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).to include("application/json")
    end
  end
end
