# PALLAS-CUSTOM (2026-09-19, PRD-20260919-checkout-billing-details-passthrough):
# 账单详情（`billing_details`）**唯一构造点** —— PaymentIntent 模式与 Checkout Session
# 模式共用，避免两处实现漂移。
#
# 来源 = `order.bill_address`（`Carts::Submit` 已按 `billing_mode` 落库：同配送 →
# 配送地址副本；自定义 → 显式账单地址），因此这里**不猜、不补齐**：
# 地址缺失或最小完整集不齐（`address1` 为空）→ 返回 nil，调用方整体不发该键
# （宁可不发，也不把半空地址送给 Stripe 触发 AVS 误判）。
module PallasTradeStripe
  class BillingDetailsPresenter
    def initialize(order:)
      @order = order
    end

    # @return [Hash{Symbol=>Object}, nil] Stripe `billing_details` 形状；不可用 → nil
    def call
      address = order.bill_address
      return nil if address.blank? || address.address1.blank?

      {
        name: address.full_name.presence,
        email: order.email.presence,
        phone: address.phone.presence,
        address: {
          city: address.city,
          country: address.country_iso,
          line1: address.address1,
          line2: address.address2,
          postal_code: address.zipcode,
          state: address.state_abbr
        }.compact
      }.compact.presence
    end

    private

    attr_reader :order
  end
end
