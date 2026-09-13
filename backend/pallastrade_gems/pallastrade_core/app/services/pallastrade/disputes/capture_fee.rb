# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-9 (PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics)
#
# Disputes::CaptureFee —— 争议**手续费事实采集**（FR-P79-03/04）。
#
# 背景（P7-0 §9.2，已实测）：Stripe 把「扣款 + 手续费」放在**同一条** `adjustment` BalanceTransaction
#   里（`amount=-争议额, fee=1500, net=-(争议额+1500)`），胜诉返还的 BT `fee=0` → **手续费永不退回**。
#   因此手续费必须被单独观测、单独入账（`DISPUTE_FEE`），绝不能把 `net` 当成单一发生额。
#
# 语义边界（铁律）：
#   - **只采集事实**：写 `Dispute#fee_amount`（本题唯一写入的列），不写账本/资金/订单/库存；
#     账本由 `Dispute` 的 after_commit 事件（`dispute.fee_recorded`）→ `FinancialLedger::PostDispute` 完成。
#   - **首次观测写入**：仅当本地为空且 provider 明确给出 `fee > 0` 时写入；重放/重复调用**不覆盖**。
#   - **不猜**：缺字段 / provider 降级 / fee ≤ 0 → 不写（保持 nil，由对账 `journal_missing` 侧暴露缺口）。
#   - fee 币种：`pallastrade_disputes` 无 `fee_currency` 列（零迁移边界）→ 取 dispute 自身 `currency`
#     （provider 实测：手续费与被扣款同币种）。
#
# 采集路径：收敛/只读快照路径（`Disputes::Recover` 已持有 provider 快照 → 顺带采集，零额外网络调用）；
#   也可由调用方传入已取快照（测试/复用）。
module PallasTrade
  module Disputes
    class CaptureFee
      prepend PallasTrade::ServiceModule::Base

      # @param dispute [PallasTrade::Dispute]
      # @param snapshot [Hash, nil] 已取的 provider 只读快照（含 `fee_amount`）；nil = 自行取（只读）
      # @param payment_method [PallasTrade::PaymentMethod, nil] 显式注入（测试/复用；缺省取 dispute.payment&.payment_method）
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ dispute_id:, recorded:, fee_amount:, currency:, degraded: })
      #   / failure(dispute, message)
      def call(dispute:, snapshot: nil, payment_method: nil)
        return failure(nil, 'Dispute not found') if dispute.nil?

        source = snapshot
        degraded = nil
        source, degraded = provider_snapshot(dispute, payment_method) if source.nil?
        return success(result(dispute, recorded: false, degraded: degraded)) if source.nil?

        fee = fee_from(source)
        return success(result(dispute, recorded: false, degraded: degraded)) if fee.nil? || fee <= 0
        return success(result(dispute, recorded: false, degraded: degraded)) if dispute.fee_amount.present?

        dispute.update!(fee_amount: fee)
        success(result(dispute, recorded: true, degraded: degraded))
      end

      private

      # provider 只读快照（缺 payment / 无契约 / 故障 → 降级枚举，绝不猜测）
      # @return [Array(Hash|nil, String|nil)]
      def provider_snapshot(dispute, payment_method)
        method = payment_method || dispute.payment&.payment_method
        return [nil, 'UNLINKED_PAYMENT'] if method.nil?
        return [nil, 'PROVIDER_CONTRACT_UNSUPPORTED'] unless implements_dispute_details?(method)

        [method.fetch_dispute_details(dispute: dispute), nil]
      rescue PallasTrade::Core::GatewayError, (defined?(Stripe::StripeError) ? Stripe::StripeError : StandardError)
        [nil, 'PROVIDER_UNAVAILABLE']
      end

      # capability 判定与 P7-2/P7-4 同口径：**类级** method owner 非 base 才是真实现
      # （实例级会被测试打桩成「假装有契约」）。
      def implements_dispute_details?(payment_method)
        return false unless payment_method.respond_to?(:fetch_dispute_details)

        payment_method.method(:fetch_dispute_details).owner != PallasTrade::PaymentMethod
      end

      # 快照 → fee（仅接受正数；缺失/畸形一律 nil，不猜金额）
      def fee_from(snapshot)
        raw = snapshot.is_a?(Hash) ? (snapshot[:fee_amount] || snapshot['fee_amount']) : nil
        return nil if raw.nil? || raw.to_s.strip.empty?

        fee = raw.to_d
        fee.positive? ? fee : nil
      rescue ArgumentError, TypeError
        nil
      end

      def result(dispute, recorded:, degraded:)
        {
          dispute_id: dispute.prefixed_id,
          recorded: recorded,
          fee_amount: dispute.fee_amount&.to_d,
          currency: dispute.currency,
          degraded: degraded
        }
      end
    end
  end
end
