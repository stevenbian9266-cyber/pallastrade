# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Rates::Resolver` —— 给定币种对与参照时刻，取**唯一生效汇率行**。
#
# 排序（与 `CurrencyRate.by_priority` 同一 SQL 口径，确定性）：
#   `priority DESC` → **本店优先于全局** → `effective_from DESC` → `id DESC`。
# 无候选 → `rate: nil` + `signals: ['no_rate']`（**不猜**；锁汇因此不写快照）。
#
# 只读：不写库、不外呼。
module PallasTrade
  module Currencies
    module Rates
      class Resolver
        prepend PallasTrade::ServiceModule::Base

        # @param store [PallasTrade::Store, nil]
        # @param base [String] 结算侧币种
        # @param quote [String] 展示侧币种
        # @param at [Time] 参照时刻（生效窗口判定）
        # @param candidates [Array<PallasTrade::CurrencyRate>, nil] 预加载候选（批量场景，避免 N+1）
        # @return [PallasTrade::ServiceModule::Result] success({ rate:, candidates:, signals: })
        def call(store: nil, base:, quote:, at: Time.current, candidates: nil)
          return failure(nil, 'Base currency is required') if base.blank?
          return failure(nil, 'Quote currency is required') if quote.blank?

          pair = [base.to_s.upcase, quote.to_s.upcase]
          return success({ rate: nil, candidates: 0, signals: ['same_currency'] }) if pair.uniq.size == 1

          list = candidates || candidates_for(store, pair, at)
          row = list.find do |candidate|
            candidate.base_currency == pair[0] && candidate.quote_currency == pair[1]
          end

          success({
                    rate: row,
                    candidates: list.size,
                    signals: row.nil? ? ['no_rate'] : []
                  })
        end

        private

        def candidates_for(store, pair, at)
          PallasTrade::CurrencyRate.for_store(store).active.effective_at(at).for_pair(*pair).by_priority.to_a
        end
      end
    end
  end
end
