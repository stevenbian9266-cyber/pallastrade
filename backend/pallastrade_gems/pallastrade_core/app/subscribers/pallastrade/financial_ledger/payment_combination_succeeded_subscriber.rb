# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-4 (PRD-20260906-payments-fin-p4-4)
#
# FinancialLedger::PaymentCombinationSucceededSubscriber —— payment_combination.succeeded
# → PostCombinationAllocations 接线（FR-4P4-07）。
#
# 事件源：PaymentCombination after_transition to: :succeeded → publish_event
#   'payment_combination.succeeded'（Settlement 在锁内先写各 split captured_amount 再 succeed!——
#   事件在 succeed 调用点发布；subscriber 默认 async（SubscriberJob）→ 提交后执行读到最终 captured）。
#
# 可靠性：PostAllocation 幂等（显式稳定 key `fact:ORDER_ALLOCATION:<txn>:<split>`）→ 重放/重试不重复；
# 硬失败 rescue → Rails.logger.error（不阻断组合资金流；P4-8 repair/recovery 可重放）。
# 健壮性：payload id 支持 prefixed（pcom_）或 raw integer 双模式；legacy 无 txn 组合 → PostAllocation
# skipped（安全 no-op）。
module PallasTrade
  module FinancialLedger
    class PaymentCombinationSucceededSubscriber < PallasTrade::Subscriber
      subscribes_to 'payment_combination.succeeded'

      def handle(event)
        combination = find_combination(event.payload)
        return if combination.nil?

        result = PallasTrade::FinancialLedger::PostCombinationAllocations.call(combination: combination)
        return if result.success?

        Rails.logger.error(
          "[FinancialLedger::PaymentCombinationSucceededSubscriber] allocation posting failed for combination #{combination.prefixed_id}: #{result.error}"
        )
      rescue StandardError => e
        Rails.logger.error(
          "[FinancialLedger::PaymentCombinationSucceededSubscriber] allocation posting failed for combination #{combination&.prefixed_id}: #{e.class} #{e.message}"
        )
      end

      private

      # payment_combination.succeeded payload 走 event_payload（含 prefixed id pcom_）。
      def find_combination(payload)
        id = payload.try(:[], 'id') || payload.try(:[], :id)
        return if id.blank?

        if id.to_s.start_with?('pcom_')
          PallasTrade::PaymentCombination.find_by_param(id)
        else
          PallasTrade::PaymentCombination.find_by(id: id)
        end
      end
    end
  end
end
