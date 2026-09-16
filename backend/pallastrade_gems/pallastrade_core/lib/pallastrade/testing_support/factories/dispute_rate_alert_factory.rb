# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# 拒付率预警台账工厂。`dedupe_key` 用模型自身的唯一口径生成（一店 × 一组织 × 一评估日）。
FactoryBot.define do
  factory :dispute_rate_alert, class: PallasTrade::DisputeRateAlert do
    store
    network { 'visa' }
    tier { PallasTrade::DisputeRateAlert::APPROACHING }
    evaluated_on { Date.current }
    window_days { 30 }
    count_ratio_bps { 65 }
    amount_ratio_bps { 40 }
    count_threshold_bps { 80 }
    amount_threshold_bps { 90 }
    transactions_count { 1_000 }
    disputes_count { 7 }
    currency { 'USD' }
    triggered_metrics { ['count'] }
    detected_at { Time.current }
    dedupe_key do
      PallasTrade::DisputeRateAlert.key_for(
        store_id: store&.id, network: network, evaluated_on: evaluated_on
      )
    end
  end
end
