# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-3 (PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile)
#
# FinancialLedger::DisputeFundsSubscriber —— 争议资金事件 → PostDispute 接线（FR-P73-09）。
#
# 事件源：`PallasTrade::Dispute` 在 `funds_withdrawn_at` / `funds_reinstated_at` **由空变非空**
#   的 after_commit 发布 `dispute.funds_withdrawn` / `dispute.funds_reinstated`
#   （提交后触发 → posting 恒在争议事实落库提交后执行，对齐 payment.paid / refund.succeeded 模式）。
#
# 幂等：PostDispute → Post（idempotency_key = `fact:<type>:<txn>:dispute:<dsp_id>:<funds_at>`）
#   → 重复事件/重试/replay 不产生第二条 entry（AC-P73-02）。
# 守卫：非现金事实（OPENED/WON/LOST）与未证实事实（AMBIGUOUS/UNSUPPORTED）永不入账 ——
#   skip reason 记日志，不抛错（AC-P73-05/06）。
# 健壮性：payload id 支持 prefixed（dsp_）或 raw integer 双模式；异常 rescue → 日志（不阻断争议落库）。
module PallasTrade
  module FinancialLedger
    class DisputeFundsSubscriber < PallasTrade::Subscriber
      subscribes_to 'dispute.funds_withdrawn', 'dispute.funds_reinstated'

      # 事件 → 入账事实类型（事件作用域；终态 won/lost 不吞掉后续资金事件——见 ResolveDispute 注释）
      FACT_TYPE_BY_EVENT = {
        'dispute.funds_withdrawn' => 'DISPUTE_FUNDS_WITHDRAWN',
        'dispute.funds_reinstated' => 'DISPUTE_FUNDS_REINSTATED'
      }.freeze

      def handle(event)
        dispute = find_dispute(event.payload)
        return if dispute.nil?

        result = PallasTrade::FinancialLedger::PostDispute.call(
          dispute: dispute, fact_type: FACT_TYPE_BY_EVENT[event.name]
        )
        return unless result.success?
        return unless result.value[:skipped]

        Rails.logger.info(
          "[FinancialLedger::DisputeFundsSubscriber] skip ledger posting for dispute #{dispute.prefixed_id}: #{result.value[:reason]}"
        )
      rescue StandardError => e
        Rails.logger.error(
          "[FinancialLedger::DisputeFundsSubscriber] ledger posting failed for dispute #{dispute&.prefixed_id}: #{e.class} #{e.message}"
        )
      end

      private

      def find_dispute(payload)
        id = payload.try(:[], 'id') || payload.try(:[], :id)
        return if id.blank?

        if id.to_s.start_with?('dsp_')
          PallasTrade::Dispute.find_by_param(id)
        else
          PallasTrade::Dispute.find_by(id: id)
        end
      end
    end
  end
end
