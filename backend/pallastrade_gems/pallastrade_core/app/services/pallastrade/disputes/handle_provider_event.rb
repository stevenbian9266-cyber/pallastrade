# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PRD-20260911-payments-dsp-p7-1 (DSP-P7-1)
    #
    # `Disputes::HandleProviderEvent` — provider dispute 事件的**唯一落库入口**。
    #
    # 链路（P7-0 §6/§8）：
    #   Stripe webhook 验签 → PaymentWebhookEvent（dedupe/replay 复用 P0）
    #     → HandleWebhookJob 分流 → 本服务
    #     → 解析载荷（ProviderPayload）→ 解析本地锚点（payment_intent = Payment#response_code）
    #     → Dispute.upsert_from_event!（幂等）→ 状态单向收敛
    #
    # 边界（P7-0 B2/B3/B4/B5）：
    #   - **零业务副作用**：不写 order / inventory / payment / 财务账本
    #   - **无锚点不丢事件**：解析不到 Payment 时仍落行，标 attention_reason=unlinked_payment
    #   - webhook 只是证据：绝不在此取消订单、重算库存或补记资金
    #
    # 未知 provider 状态 → 保持既有状态（不猜、不回退）。
    class HandleProviderEvent
      prepend PallasTrade::ServiceModule::Base

      # @param webhook_event [PallasTrade::PaymentWebhookEvent]
      # @return [PallasTrade::ServiceModule::Result]
      #   success(dispute:, payment:, action:) / failure(webhook_event, message)
      def call(webhook_event:)
        return failure(nil, 'Webhook event required') if webhook_event.nil?

        payload = ProviderPayload.new(provider: webhook_event.provider, payload: webhook_event.payload)
        return failure(webhook_event, 'Malformed dispute payload (no dispute object/id)') unless payload.valid?

        payment = resolve_payment(payload)
        attributes = build_attributes(payload, payment)
        dispute = PallasTrade::Dispute.upsert_from_event!(
          provider: webhook_event.provider,
          reference: payload.reference,
          attributes: attributes
        )

        apply_state(dispute, payload, webhook_event)
        success(dispute: dispute.reload, payment: payment, action: webhook_event.action)
      end

      private

      # provider 事件 → 本地锚点：payment_intent 即 `Payment#response_code`（P7-0 Q3/Q4 结论）
      def resolve_payment(payload)
        reference = payload.payment_reference
        return nil if reference.blank?

        PallasTrade::Payment.find_by(response_code: reference)
      end

      def build_attributes(payload, payment)
        attributes = {
          provider_charge_reference: payload.charge_reference,
          provider_payment_reference: payload.payment_reference,
          kind: payload.kind,
          reason: payload.reason,
          network_reason_code: payload.network_reason_code,
          amount: payload.amount,
          currency: payload.currency,
          evidence_due_at: payload.evidence_due_at,
          evidence_submitted_at: payload.evidence_submitted_at,
          outcome: payload.outcome
        }

        link_attributes = payment_links(payment)
        attributes.merge!(link_attributes) if link_attributes.present?
        attributes[:attention_reason] = attention_reason(payload, payment)
        attributes[:private_metadata] = { 'provider_status' => payload.provider_status }
        attributes
      end

      def payment_links(payment)
        return {} if payment.nil?

        transaction = PallasTrade::FinancialFacts::OwnershipResolver.call(payment: payment).value[:transaction]

        {
          payment_id: payment.id,
          order_id: payment.order_id,
          store_id: payment.order&.store_id,
          payment_combination_id: payment.payment_combination_id,
          commerce_transaction_id: transaction&.id
        }
      end

      def attention_reason(payload, payment)
        return 'unlinked_payment' if payment.nil?

        amount = payload.amount
        return 'non_positive_amount' if amount.present? && amount <= 0

        nil
      end

      # 状态收敛：known 状态走状态机（非法边不炸事件，转 manual_review 记录偏差）
      def apply_state(dispute, payload, webhook_event)
        target = payload.state
        return dispute if target.blank?
        return dispute if dispute.state == target

        dispute.transition_to!(target, at: webhook_event.provider_created_at || Time.current)
      rescue PallasTrade::Dispute::InvalidTransition
        # provider 语义跳跃（乱序事件/回退）→ 保留事实 + 人工关注，绝不丢事件
        dispute.update!(attention_reason: dispute.attention_reason.presence || 'invalid_transition',
                        private_metadata: (dispute.private_metadata || {}).merge(
                          'invalid_transition' => { 'from' => dispute.state,
                                                    'to' => target,
                                                    'event_type' => webhook_event.event_type }
                        ))
      end
    end
  end
end
