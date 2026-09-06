# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-4 (PRD-20260906-payments-fin-p4-4)
#
# FinancialLedger::PostCombinationAllocations —— 组合批量 allocation posting 编排（FR-4P4-06）。
#
# 遍历 combination.payment_splits 逐 split PostAllocation（幂等原语），供
# `payment_combination.succeeded` subscriber 与 repair/recovery 复用。
#
# 失败语义：逐条独立执行（一条失败不阻断其余）；全部尝试后若存在硬失败（非 skipped）→ failure
# （subscriber job 据此重试——已成功条目幂等跳过，安全）；全 skipped/全成功 → success 聚合。
module PallasTrade
  module FinancialLedger
    class PostCombinationAllocations
      prepend PallasTrade::ServiceModule::Base

      # @param combination [PallasTrade::PaymentCombination]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ posted: Integer, skipped: Integer, results: Array }) / failure(combination, message)
      def call(combination:)
        return failure(nil, 'Payment combination not found') if combination.nil?

        results = combination.payment_splits.reload.to_a.map do |split|
          { split: split, result: PallasTrade::FinancialLedger::PostAllocation.call(split: split) }
        end

        failures = results.reject { |r| r[:result].success? }
        return failure(combination, "Allocation posting failed for #{failures.size} split(s)") if failures.any?

        posted = results.count { |r| r[:result].success? && !r[:result].value[:skipped] }
        skipped = results.count { |r| r[:result].success? && r[:result].value[:skipped] }

        success(posted: posted, skipped: skipped, results: results)
      end
    end
  end
end
