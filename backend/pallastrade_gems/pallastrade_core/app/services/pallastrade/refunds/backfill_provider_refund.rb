# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8m (PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run-)
#
# Refunds::BackfillProviderRefund —— 孤儿（provider-only）退款本地补记（RISK-REV-01 收口）。
#
# 语义：孤儿 = provider 已退款、本地无 durable Refund 行（8a 前 legacy/异常）。本服务把该已发生资金
# **记录**为本地 Refund 行并直接落终态：
#   create!(requested + transaction_id=provider_id + metadata{backfilled_orphan})
#     → apply_success!(authorization: provider_id)   # 幂等 succeeded + update_order（可证明投影）
#     → after_commit refund.succeeded → PostRefund = REFUND_SUCCEEDED Journal（本地账/对账闭合）
#
# **绝不调用 PSP / 绝不 enqueue ExecuteJob**（补记 ≠ 发起退款；REV-INV-04 精神）。
# 幂等：同 payment + transaction_id 已存在 → noop；金额不可证明 → skip。
# 孤儿 target_order/payment_split 不可证明 → 不猜（AC-6029；update_order 仅可证明投影——组合 order nil
# 无 target 时仅 fact/journal 落）。
#
# 调用方：人工 rake（dry-run 默认；--apply 才写）。审计：Audit.record(action: 'refund_orphan_backfill')。
module PallasTrade
  module Refunds
    class BackfillProviderRefund
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment]
      # @param provider_id [String] provider 退款引用（transaction_id）
      # @param amount [Numeric, String] provider 权威金额（major units；8h retrieve_refund）
      # @param currency [String, nil]
      # @param actor [String, Object] Audit actor（默认 'rake'）
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ status: 'backfilled'|'already_backfilled'|'skipped', reason:, refund_id: })
      #   failure(message) 支付缺失 / 意外异常
      def call(payment:, provider_id:, amount:, currency: nil, actor: 'rake')
        return failure('Payment not found') if payment.nil?
        if amount.blank? || amount.to_f <= 0
          return success(status: 'skipped', reason: 'orphan_amount_unavailable', provider_id: provider_id.to_s)
        end

        existing = PallasTrade::Refund.find_by(payment_id: payment.id, transaction_id: provider_id.to_s)
        if existing
          return success(status: 'already_backfilled', refund_id: existing.prefixed_id, provider_id: provider_id.to_s)
        end

        refund = payment.refunds.create!(
          amount: amount,
          transaction_id: provider_id.to_s,
          state: 'requested',
          reason: PallasTrade::RefundReason.orphan_backfill_reason,
          metadata: {
            'backfilled_orphan' => true,
            'backfilled_at' => Time.current.iso8601,
            'backfilled_currency' => currency.to_s.presence || payment.currency
          }
        )

        # provider 已退 → 直接落 succeeded（幂等；同事务投影；Journal 经 after_commit refund.succeeded）。
        # 绝不调 PSP / ExecuteJob。
        refund.apply_success!(authorization: provider_id.to_s)

        PallasTrade::Audit.record(
          actor: actor || 'rake',
          action: 'refund_orphan_backfill',
          resource: refund,
          after: {
            payment_id: payment.prefixed_id,
            provider_refund_id: provider_id.to_s,
            amount: refund.amount.to_s,
            currency: currency.to_s.presence || refund.currency
          }
        )

        success(status: 'backfilled', refund_id: refund.prefixed_id, provider_id: provider_id.to_s)
      rescue StandardError => e
        failure("#{e.class}: #{e.message}")
      end
    end
  end
end
